import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../../core/errors/exceptions.dart';
import 'audio_extractor.dart';

/// Output of one yt-dlp run.
class YtDlpRunResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const YtDlpRunResult(this.exitCode, this.stdout, this.stderr);
}

/// Runs a process and collects its output. Must throw [TimeoutException] (and
/// stop the process) when [timeout] elapses. Injectable so tests never need a
/// real `yt-dlp.exe`.
abstract interface class YtDlpProcessRunner {
  Future<YtDlpRunResult> run(String executable, List<String> arguments, {required Duration timeout});
}

/// Real runner. Dart starts attached children of a GUI (Flutter Windows) app
/// with `CREATE_NO_WINDOW`, so no console window flashes up.
class IoYtDlpProcessRunner implements YtDlpProcessRunner {
  const IoYtDlpProcessRunner();

  @override
  Future<YtDlpRunResult> run(String executable, List<String> arguments, {required Duration timeout}) async {
    final process = await Process.start(executable, arguments);
    final decoder = const Utf8Decoder(allowMalformed: true);
    final stdoutFuture = process.stdout.transform(decoder).join();
    final stderrFuture = process.stderr.transform(decoder).join();
    final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      await _killTree(process);
      rethrow;
    }
    return YtDlpRunResult(exitCode, await stdoutFuture, await stderrFuture);
  }

  /// The official yt-dlp builds are PyInstaller one-file builds: the visible
  /// process spawns the real interpreter as a child, so kill the whole tree.
  static Future<void> _killTree(Process process) async {
    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/PID', '${process.pid}', '/T', '/F']);
      } else {
        await Process.run('pkill', ['-KILL', '-P', '${process.pid}']);
        process.kill(ProcessSignal.sigkill);
      }
    } catch (_) {
      process.kill();
    }
  }
}

/// Saves [url] to [target]. Injectable so tests never download anything.
typedef BinaryDownloader = Future<void> Function(Uri url, File target);

Future<void> _httpDownload(Uri url, File target) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('Download failed with ${response.statusCode}', uri: url);
    }
    await response.pipe(target.openWrite());
  } finally {
    client.close();
  }
}

/// Runs yt-dlp on the user's computer — no Symphony server. Windows and macOS.
///
/// macOS: the app downloads `yt-dlp_macos` into `<app support>/yt-dlp/` on
/// first start ([install]) and keeps it current with [update]. It is not
/// shipped inside the app: a binary inside a downloaded, un-notarized app is
/// quarantined and macOS refuses to run it, while one the app downloads
/// itself is not.
///
/// Windows binary lookup, in order:
/// 1. `<dir of Symphony.exe>\yt-dlp\yt-dlp.exe` — the official *folder*
///    build shipped by CI. It starts ~0.5 s faster per run than the one-file
///    build (no self-extraction to %TEMP%); [update] runs `-U` on it in place.
/// 2. `<app support>\yt-dlp\yt-dlp.exe` — writable one-file copy kept current
///    by [update] for installs from before the folder build;
/// 3. `<dir of Symphony.exe>\yt-dlp.exe` — one-file build from older zips.
///
/// If `deno.exe` or `qjs.exe` sits next to the binary in use, it is passed via
/// `--js-runtimes`. None is bundled today: YouTube audio currently extracts
/// and range-seeks fine without one (see CHANGELOG 2026-10-11).
class DesktopYtDlpExtractor implements AudioExtractor {
  static const windowsBinaryName = 'yt-dlp.exe';
  static const macBinaryName = 'yt-dlp_macos';
  static final macDownloadUrl = Uri.parse('https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos');
  static const formatSelector = 'ba[ext=m4a]/ba[acodec^=mp4a]/ba';
  static const defaultExtractTimeout = Duration(seconds: 25);
  static const defaultUpdateTimeout = Duration(minutes: 3);

  /// Set while any instance runs `yt-dlp -U`; extraction then uses the bundled
  /// binary so playback never waits on (or races) the self-update.
  static Future<String?>? _updateInFlight;

  final YtDlpProcessRunner _runner;
  final Future<Directory> Function() _supportDir;
  final String Function() _exeDir;
  final TargetPlatform? _platform;
  final BinaryDownloader _download;
  final Duration _timeout;

  bool? _available;
  Future<bool>? _installing;
  final Map<String, Future<ExtractedAudio>> _inFlight = {};

  /// Each yt-dlp.exe launch unpacks itself and starts Python, so cap how many
  /// run at once; extra lookups wait their turn.
  /// Background work (next-song warm-up + link prefetch) uses at most two,
  /// so a song the user taps always has a free slot.
  static const maxConcurrentRuns = 3;
  int _running = 0;
  final _waiting = <Completer<void>>[];

  Future<T> _withSlot<T>(Future<T> Function() body) async {
    if (_running >= maxConcurrentRuns) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _running++;
    try {
      return await body();
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }

  DesktopYtDlpExtractor({
    YtDlpProcessRunner runner = const IoYtDlpProcessRunner(),
    Future<Directory> Function()? supportDir,
    String Function()? exeDir,
    TargetPlatform? platform,
    BinaryDownloader? download,
    Duration timeout = defaultExtractTimeout,
  })  : _runner = runner,
        _supportDir = supportDir ?? getApplicationSupportDirectory,
        _exeDir = exeDir ?? (() => File(Platform.resolvedExecutable).parent.path),
        _platform = platform ?? (kIsWeb ? null : defaultTargetPlatform),
        _download = download ?? _httpDownload,
        _timeout = timeout;

  bool get _isWindows => _platform == TargetPlatform.windows;
  bool get _isMac => _platform == TargetPlatform.macOS;
  String get _binaryName => _isMac ? macBinaryName : windowsBinaryName;

  @override
  String get name => _isMac ? 'yt-dlp (macos)' : 'yt-dlp (windows)';

  @override
  Future<bool> isAvailable() async {
    if (_isMac) {
      if (_available == true) return true;
      final found = await _findBinary() != null;
      // Not downloaded yet: fetch it in the background; songs use the next
      // extractor until it is ready.
      if (!found) unawaited(install());
      return _available = found;
    }
    if (!_isWindows) return false;
    return _available ??= await _findBinary() != null;
  }

  /// macOS: downloads yt-dlp into app support if it isn't there yet. Returns
  /// whether it is ready. Never throws. Elsewhere, reports availability.
  Future<bool> install() {
    if (!_isMac) return isAvailable();
    return _installing ??= _install().whenComplete(() {
      _installing = null;
    });
  }

  Future<bool> _install() async {
    try {
      final target = File(await _supportBinaryPath());
      if (await target.exists()) return _available = true;
      await target.parent.create(recursive: true);
      final partial = File('${target.path}.download');
      developer.log('Downloading yt-dlp for macOS…', name: 'YtDlp');
      await _download(macDownloadUrl, partial);
      await _runner.run('chmod', ['755', partial.path], timeout: const Duration(seconds: 10));
      await partial.rename(target.path);
      developer.log('yt-dlp for macOS is ready', name: 'YtDlp');
      return _available = true;
    } catch (e) {
      developer.log('yt-dlp download failed: $e', name: 'YtDlp');
      return false;
    }
  }

  @override
  Future<ExtractedAudio> extract(String videoId) => _coalesced(
        videoId,
        () => _extract(videoId, 'https://www.youtube.com/watch?v=$videoId', const ['--no-playlist'], videoId),
      );

  /// YouTube Music "songs" search + extraction of the top result, in one run.
  @override
  Future<ExtractedAudio> searchSong(String query) {
    final q = query.trim();
    if (q.isEmpty) return Future.error(const AudioStreamResolutionException('Empty song search'));
    final url = 'https://music.youtube.com/search?q=${Uri.encodeQueryComponent(q)}#songs';
    return _coalesced('song:$q', () => _extract('song:$q', url, const ['--playlist-items', '1'], null));
  }

  Future<ExtractedAudio> _coalesced(String key, Future<ExtractedAudio> Function() run) {
    final pending = _inFlight[key];
    if (pending != null) return pending;
    // Block body: returning the removed future would make whenComplete wait on itself.
    final future = run().whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = future;
    return future;
  }

  Future<ExtractedAudio> _extract(String what, String url, List<String> extraArgs, String? videoId) async {
    final binary = await _findBinary(preferBundled: _updateInFlight != null);
    if (binary == null) {
      _available = false;
      throw AudioStreamResolutionException('yt-dlp not found for $what');
    }
    final args = [
      ..._jsRuntimeArgs(binary),
      '-f', formatSelector,
      '-j',
      ...extraArgs,
      '--no-warnings',
      url,
    ];
    final YtDlpRunResult result;
    final watch = Stopwatch()..start();
    try {
      result = await _withSlot(() => _runner.run(binary, args, timeout: _timeout));
    } on TimeoutException {
      throw AudioStreamResolutionException('yt-dlp timed out after ${_timeout.inSeconds}s for $what');
    } on ProcessException catch (e) {
      _available = null;
      throw AudioStreamResolutionException('Could not start yt-dlp for $what', e.message);
    }
    if (result.exitCode != 0) {
      throw AudioStreamResolutionException(
        'yt-dlp exited with ${result.exitCode} for $what',
        _tail(result.stderr),
      );
    }
    final audio = parseYtDlpJson(result.stdout, videoId ?? what, stderr: result.stderr);
    developer.log(
      'yt-dlp resolved $what -> ${audio.videoId} (${audio.container}, ${audio.bitrateKbps ?? '?'} kbps) in ${watch.elapsedMilliseconds} ms',
      name: 'YtDlp',
    );
    return audio;
  }

  /// Runs `yt-dlp -U` on the app-support copy, creating it from the bundled
  /// binary first. Returns the new version if it changed, else null. Never
  /// throws; failures are logged.
  Future<String?> update() {
    if (!_isWindows && !_isMac) return Future.value(null);
    return _updateInFlight ??= _update().whenComplete(() {
      _updateInFlight = null;
    });
  }

  Future<String?> _update() async {
    try {
      if (_isMac && !await install()) return null;
      final folderBuild = File(_bundledFolderBinaryPath());
      final target = await folderBuild.exists() ? folderBuild : File(await _supportBinaryPath());
      if (target != folderBuild && !await target.exists()) {
        final bundled = File(_bundledBinaryPath());
        if (!await bundled.exists()) return null;
        await target.parent.create(recursive: true);
        await bundled.copy(target.path);
      }
      final result = await _runner.run(target.path, const ['-U'], timeout: defaultUpdateTimeout);
      _available = null;
      if (result.exitCode != 0) {
        developer.log('yt-dlp -U failed (${result.exitCode}): ${_tail(result.stderr)}', name: 'YtDlp');
        return null;
      }
      final version = parseYtDlpUpdateOutput(result.stdout);
      developer.log(version != null ? 'yt-dlp updated to $version' : 'yt-dlp is up to date', name: 'YtDlp');
      return version;
    } catch (e) {
      developer.log('yt-dlp update error: $e', name: 'YtDlp');
      return null;
    }
  }

  Future<String> _supportBinaryPath() async =>
      '${(await _supportDir()).path}${Platform.pathSeparator}yt-dlp${Platform.pathSeparator}$_binaryName';

  String _bundledBinaryPath() => '${_exeDir()}${Platform.pathSeparator}$_binaryName';

  String _bundledFolderBinaryPath() =>
      '${_exeDir()}${Platform.pathSeparator}yt-dlp${Platform.pathSeparator}$_binaryName';

  Future<String?> _findBinary({bool preferBundled = false}) async {
    if (_isMac) {
      final downloaded = await _supportBinaryPath();
      return await File(downloaded).exists() ? downloaded : null;
    }
    final folderBuild = _bundledFolderBinaryPath();
    if (await File(folderBuild).exists()) return folderBuild;
    final candidates = <String>[];
    try {
      candidates.add(await _supportBinaryPath());
    } catch (_) {
      // No app-support dir (shouldn't happen on Windows); use the bundled one.
    }
    final bundled = _bundledBinaryPath();
    preferBundled ? candidates.insert(0, bundled) : candidates.add(bundled);
    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }
    return null;
  }

  static List<String> _jsRuntimeArgs(String binary) {
    final dir = File(binary).parent.path;
    final ext = Platform.isWindows ? '.exe' : '';
    for (final (runtime, exe) in const [('deno', 'deno'), ('quickjs', 'qjs')]) {
      final path = '$dir${Platform.pathSeparator}$exe$ext';
      if (File(path).existsSync()) return ['--js-runtimes', '$runtime:$path'];
    }
    return const [];
  }

  @override
  void dispose() {}
}

/// Parses `yt-dlp -j` output for a single video.
@visibleForTesting
ExtractedAudio parseYtDlpJson(String stdout, String videoId, {String stderr = ''}) {
  final line = const LineSplitter()
      .convert(stdout)
      .lastWhere((l) => l.trimLeft().startsWith('{'), orElse: () => '');
  final Object? decoded;
  try {
    decoded = line.isEmpty ? null : jsonDecode(line);
  } on FormatException catch (e) {
    throw AudioStreamResolutionException('yt-dlp returned invalid JSON for $videoId', e.message);
  }
  if (decoded is! Map<String, dynamic>) {
    throw AudioStreamResolutionException('yt-dlp returned no info for $videoId', _tail(stderr));
  }
  final url = decoded['url'];
  if (url is! String || url.isEmpty) {
    throw AudioStreamResolutionException('yt-dlp returned no URL for $videoId', _tail(stderr));
  }
  final seconds = decoded['duration'];
  final rawHeaders = decoded['http_headers'];
  return ExtractedAudio(
    url: Uri.parse(url),
    container: (decoded['ext'] as String?) ?? 'm4a',
    bitrateKbps: (decoded['abr'] as num?)?.round(),
    duration: seconds is num && seconds > 0 ? Duration(milliseconds: (seconds * 1000).round()) : null,
    headers: rawHeaders is Map && rawHeaders.isNotEmpty
        ? rawHeaders.map((k, v) => MapEntry('$k', '$v'))
        : null,
    videoId: (decoded['id'] as String?) ?? videoId,
    title: decoded['title'] as String?,
    channel: (decoded['channel'] as String?) ?? (decoded['uploader'] as String?),
  );
}

/// Extracts the new version from `yt-dlp -U` output ("Updated yt-dlp to
/// stable@2026.09.01 …"), or null when it was already current.
@visibleForTesting
String? parseYtDlpUpdateOutput(String stdout) =>
    RegExp(r'Updated yt-dlp to\s+(?:\S+@)?([\w.\-]+)').firstMatch(stdout)?.group(1);

String? _tail(String text, [int max = 600]) {
  final t = text.trim();
  if (t.isEmpty) return null;
  return t.length <= max ? t : '…${t.substring(t.length - max)}';
}
