import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:symphony/core/errors/exceptions.dart';
import 'package:symphony/features/audio_player/data/services/extraction/desktop_ytdlp_extractor_io.dart';
import 'package:symphony/features/audio_player/data/services/extraction/ytdlp_update_scheduler.dart';

class _Call {
  final String executable;
  final List<String> arguments;
  final Duration timeout;
  _Call(this.executable, this.arguments, this.timeout);
}

class _FakeRunner implements YtDlpProcessRunner {
  final calls = <_Call>[];
  Future<YtDlpRunResult> Function(_Call call) handler;

  _FakeRunner(this.handler);

  @override
  Future<YtDlpRunResult> run(String executable, List<String> arguments, {required Duration timeout}) {
    final call = _Call(executable, arguments, timeout);
    calls.add(call);
    return handler(call);
  }
}

const _sampleJson = {
  'id': 'abc123',
  'format_id': '140',
  'url': 'https://rr1---sn.googlevideo.com/videoplayback?itag=140&expire=1',
  'ext': 'm4a',
  'abr': 129.5,
  'duration': 231.4,
  'http_headers': {'User-Agent': 'Mozilla/5.0', 'Sec-Fetch-Mode': 'navigate'},
};

void main() {
  late Directory root;
  late Directory supportDir;
  late Directory exeDir;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ytdlp_test');
    supportDir = await Directory('${root.path}/support').create();
    exeDir = await Directory('${root.path}/app').create();
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  String sep(String a, String b) => '$a${Platform.pathSeparator}$b';
  String bundledPath() => sep(exeDir.path, 'yt-dlp.exe');
  String supportPath() => sep(sep(supportDir.path, 'yt-dlp'), 'yt-dlp.exe');

  Future<void> createBundled() => File(bundledPath()).writeAsString('bundled');
  String folderPath() => sep(sep(exeDir.path, 'yt-dlp'), 'yt-dlp.exe');
  Future<void> createFolderBuild() async {
    await Directory(sep(exeDir.path, 'yt-dlp')).create(recursive: true);
    await File(folderPath()).writeAsString('folder');
  }
  Future<void> createSupportCopy() async {
    await Directory(sep(supportDir.path, 'yt-dlp')).create(recursive: true);
    await File(supportPath()).writeAsString('support');
  }

  DesktopYtDlpExtractor build(
    _FakeRunner runner, {
    bool isWindows = true,
    TargetPlatform? platform,
    BinaryDownloader? download,
    Duration? timeout,
  }) =>
      DesktopYtDlpExtractor(
        runner: runner,
        supportDir: () async => supportDir,
        exeDir: () => exeDir.path,
        platform: platform ?? (isWindows ? TargetPlatform.windows : TargetPlatform.linux),
        download: download ?? (url, target) async => fail('unexpected download of $url'),
        timeout: timeout ?? DesktopYtDlpExtractor.defaultExtractTimeout,
      );

  YtDlpRunResult ok([Map<String, Object?> json = _sampleJson]) => YtDlpRunResult(0, '${jsonEncode(json)}\n', '');

  group('availability', () {
    test('false off Windows even when a binary exists', () async {
      await createBundled();
      final ext = build(_FakeRunner((_) async => ok()), isWindows: false);
      expect(await ext.isAvailable(), isFalse);
    });

    test('false on Windows without a binary', () async {
      final ext = build(_FakeRunner((_) async => ok()));
      expect(await ext.isAvailable(), isFalse);
    });

    test('true with the bundled binary', () async {
      await createBundled();
      expect(await build(_FakeRunner((_) async => ok())).isAvailable(), isTrue);
    });

    test('prefers the bundled folder build over every one-file copy', () async {
      await createBundled();
      await createSupportCopy();
      await createFolderBuild();
      final runner = _FakeRunner((_) async => ok());
      await build(runner).extract('abc123');
      expect(runner.calls.single.executable, folderPath());
    });

    test('prefers the app-support copy over the bundled one', () async {
      await createBundled();
      await createSupportCopy();
      final runner = _FakeRunner((_) async => ok());
      await build(runner).extract('abc123');
      expect(runner.calls.single.executable, supportPath());
    });
  });

  group('extract', () {
    test('passes the m4a-first format selector, url and timeout', () async {
      await createBundled();
      final runner = _FakeRunner((_) async => ok());
      await build(runner, timeout: const Duration(seconds: 7)).extract('abc123');
      final call = runner.calls.single;
      expect(call.executable, bundledPath());
      expect(call.arguments, containsAllInOrder(['-f', 'ba[ext=m4a]/ba[acodec^=mp4a]/ba', '-j']));
      expect(call.arguments, containsAll(['--no-playlist', '--no-warnings']));
      expect(call.arguments.last, 'https://www.youtube.com/watch?v=abc123');
      expect(call.timeout, const Duration(seconds: 7));
    });

    test('parses url, ext, abr, duration and headers', () async {
      await createBundled();
      final audio = await build(_FakeRunner((_) async => ok())).extract('abc123');
      expect(audio.url.toString(), _sampleJson['url']);
      expect(audio.container, 'm4a');
      expect(audio.bitrateKbps, 130);
      expect(audio.duration, const Duration(milliseconds: 231400));
      expect(audio.headers, {'User-Agent': 'Mozilla/5.0', 'Sec-Fetch-Mode': 'navigate'});
    });

    test('non-zero exit throws with stderr', () async {
      await createBundled();
      final runner = _FakeRunner((_) async => const YtDlpRunResult(1, '', 'ERROR: [youtube] abc123: Video unavailable'));
      await expectLater(
        build(runner).extract('abc123'),
        throwsA(isA<AudioStreamResolutionException>()
            .having((e) => '${e.cause}', 'cause', contains('Video unavailable'))),
      );
    });

    test('timeout becomes AudioStreamResolutionException', () async {
      await createBundled();
      final runner = _FakeRunner((_) async => throw TimeoutException('slow'));
      await expectLater(
        build(runner).extract('abc123'),
        throwsA(isA<AudioStreamResolutionException>().having((e) => e.message, 'message', contains('timed out'))),
      );
    });

    test('missing binary throws', () async {
      final runner = _FakeRunner((_) async => ok());
      await expectLater(build(runner).extract('abc123'), throwsA(isA<AudioStreamResolutionException>()));
      expect(runner.calls, isEmpty);
    });

    test('coalesces concurrent calls for the same id', () async {
      await createBundled();
      final gate = Completer<YtDlpRunResult>();
      final runner = _FakeRunner((_) => gate.future);
      final ext = build(runner);
      final a = ext.extract('abc123');
      final b = ext.extract('abc123');
      final other = ext.extract('zzz999');
      gate.complete(ok());
      await Future.wait([a, b, other]);
      expect(identical(await a, await b), isTrue);
      expect(runner.calls.length, 2);
      // Once settled, a new call runs again.
      await ext.extract('abc123');
      expect(runner.calls.length, 3);
    });
  });

  group('parseYtDlpJson', () {
    test('ignores non-JSON lines and missing optional fields', () {
      final audio = parseYtDlpJson('noise\n{"url":"https://x/y","ext":"webm"}\n', 'id');
      expect(audio.container, 'webm');
      expect(audio.bitrateKbps, isNull);
      expect(audio.duration, isNull);
      expect(audio.headers, isNull);
    });

    test('throws without a url', () {
      expect(() => parseYtDlpJson('{"ext":"m4a"}', 'id'), throwsA(isA<AudioStreamResolutionException>()));
    });

    test('throws on empty or invalid output', () {
      expect(() => parseYtDlpJson('', 'id'), throwsA(isA<AudioStreamResolutionException>()));
      expect(() => parseYtDlpJson('{not json', 'id'), throwsA(isA<AudioStreamResolutionException>()));
    });
  });

  group('update', () {
    test('copies the bundled binary to app support, then runs -U on the copy', () async {
      await createBundled();
      final runner = _FakeRunner((_) async => const YtDlpRunResult(
            0,
            'Updating to stable@2026.09.01 from yt-dlp/yt-dlp ...\nUpdated yt-dlp to stable@2026.09.01 from yt-dlp/yt-dlp\n',
            '',
          ));
      final version = await build(runner).update();
      expect(version, '2026.09.01');
      expect(await File(supportPath()).readAsString(), 'bundled');
      expect(runner.calls.single.executable, supportPath());
      expect(runner.calls.single.arguments, ['-U']);
    });

    test('updates the folder build in place without copying', () async {
      await createFolderBuild();
      final runner = _FakeRunner(
        (_) async => const YtDlpRunResult(0, 'yt-dlp is up to date (stable@2026.08.19 from yt-dlp/yt-dlp)\n', ''),
      );
      await build(runner).update();
      expect(runner.calls.single.executable, folderPath());
      expect(runner.calls.single.arguments, ['-U']);
      expect(File(supportPath()).existsSync(), isFalse);
    });

    test('returns null when already up to date', () async {
      await createSupportCopy();
      final runner = _FakeRunner((_) async =>
          const YtDlpRunResult(0, 'yt-dlp is up to date (stable@2026.08.19 from yt-dlp/yt-dlp)\n', ''));
      expect(await build(runner).update(), isNull);
    });

    test('never throws on failure', () async {
      await createBundled();
      final runner = _FakeRunner((_) async => throw TimeoutException('net'));
      expect(await build(runner).update(), isNull);
    });

    test('extraction uses the bundled binary while an update runs', () async {
      await createBundled();
      await createSupportCopy();
      final updateGate = Completer<YtDlpRunResult>();
      final runner = _FakeRunner((call) => call.arguments.contains('-U') ? updateGate.future : Future.value(ok()));
      final ext = build(runner);
      final updating = ext.update();
      await ext.extract('abc123');
      expect(runner.calls.last.executable, bundledPath());
      updateGate.complete(const YtDlpRunResult(0, '', ''));
      await updating;
      await ext.extract('def456');
      expect(runner.calls.last.executable, supportPath());
    });

    test('parseYtDlpUpdateOutput', () {
      expect(parseYtDlpUpdateOutput('Updated yt-dlp to stable@2026.09.01 from yt-dlp/yt-dlp'), '2026.09.01');
      expect(parseYtDlpUpdateOutput('yt-dlp is up to date (stable@2026.08.19)'), isNull);
    });
  });

  group('YtDlpUpdateScheduler', () {
    test('runs at most once per day', () async {
      SharedPreferences.setMockInitialValues({});
      var updates = 0;
      var now = DateTime(2026, 10, 11, 9);
      final scheduler = YtDlpUpdateScheduler(
        isAvailable: () async => true,
        update: () async {
          updates++;
          return null;
        },
        now: () => now,
      );
      expect(await scheduler.runIfDue(), isTrue);
      now = DateTime(2026, 10, 11, 23);
      expect(await scheduler.runIfDue(), isFalse);
      now = DateTime(2026, 10, 12, 0, 5);
      expect(await scheduler.runIfDue(), isTrue);
      expect(updates, 2);
    });

    test('skips when yt-dlp is unavailable and survives update errors', () async {
      SharedPreferences.setMockInitialValues({});
      final unavailable = YtDlpUpdateScheduler(isAvailable: () async => false, update: () async => 'x');
      expect(await unavailable.runIfDue(), isFalse);
      final failing = YtDlpUpdateScheduler(isAvailable: () async => true, update: () => throw StateError('boom'));
      expect(await failing.runIfDue(), isFalse);
    });
  });

  test('never runs more than maxConcurrentRuns yt-dlp processes at once', () async {
    await createBundled();
    var running = 0;
    var peak = 0;
    final runner = _FakeRunner((call) async {
      running++;
      peak = running > peak ? running : peak;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      running--;
      return YtDlpRunResult(0, jsonEncode(_sampleJson), '');
    });
    final extractor = build(runner);

    await Future.wait([for (final id in ['a', 'b', 'c', 'd', 'e']) extractor.extract('${id}aaaaaaaaaa')]);

    expect(runner.calls, hasLength(5));
    expect(peak, DesktopYtDlpExtractor.maxConcurrentRuns);
  });

  group('macOS', () {
    String macPath() => sep(sep(supportDir.path, 'yt-dlp'), DesktopYtDlpExtractor.macBinaryName);

    test('downloads yt-dlp on first start and makes it runnable', () async {
      final downloads = <Uri>[];
      final runner = _FakeRunner((_) async => const YtDlpRunResult(0, '', ''));
      final ext = build(runner, platform: TargetPlatform.macOS, download: (url, target) async {
        downloads.add(url);
        await target.writeAsString('binary');
      });

      expect(await ext.install(), isTrue);
      expect(downloads, [DesktopYtDlpExtractor.macDownloadUrl]);
      expect(await File(macPath()).exists(), isTrue);
      expect(runner.calls.single.executable, 'chmod');
      expect(await ext.isAvailable(), isTrue);
    });

    test('an installed copy is not downloaded again', () async {
      await Directory(sep(supportDir.path, 'yt-dlp')).create(recursive: true);
      await File(macPath()).writeAsString('binary');
      final ext = build(_FakeRunner((_) async => ok()), platform: TargetPlatform.macOS);

      expect(await ext.install(), isTrue);
      final audio = await ext.extract('abc123');
      expect(audio.videoId, isNotEmpty);
    });

    test('not available until downloaded; a failed download is retried later', () async {
      var attempts = 0;
      final ext = build(_FakeRunner((_) async => ok()), platform: TargetPlatform.macOS, download: (url, target) async {
        attempts++;
        throw const SocketException('offline');
      });

      expect(await ext.isAvailable(), isFalse);
      expect(await ext.install(), isFalse);
      expect(await ext.install(), isFalse);
      expect(attempts, greaterThanOrEqualTo(2));
    });
  });
}
