import 'dart:async';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../../../domain/entities/resolved_audio_stream.dart';
import '../../../domain/entities/track.dart';
import 'local_track_store.dart';

/// Resolves a track to a remote stream. Normally
/// `AudioStreamResolverService.resolveBestAudioStream`.
typedef RemoteStreamResolver = Future<ResolvedAudioStream> Function(Track track);

/// Reports bytes received so far and the total if the server sent one.
typedef DownloadProgressCallback = void Function(int received, int? total);

/// Downloads a track's resolved audio stream into a [LocalTrackStore] so it
/// plays with no network. Not available on web ([isSupported] is false).
class OfflineDownloadService {
  OfflineDownloadService({
    required RemoteStreamResolver resolve,
    LocalTrackStore? store,
    http.Client? httpClient,
    this.headerTimeout = const Duration(seconds: 20),
    this.stallTimeout = const Duration(seconds: 30),
  })  : _resolve = resolve,
        _store = store ?? LocalTrackStore.platform(),
        _client = httpClient ?? http.Client();

  final RemoteStreamResolver _resolve;
  final LocalTrackStore _store;
  final http.Client _client;

  /// Max wait for response headers.
  final Duration headerTimeout;

  /// Max gap between body chunks before the download is abandoned.
  final Duration stallTimeout;

  final Map<String, Future<LocalTrackEntry>> _inFlight = {};

  bool get isSupported => _store.isSupported;
  LocalTrackStore get store => _store;

  /// Downloads [track] unless it is already on the device; concurrent calls
  /// for the same track share one download. Throws on failure.
  Future<LocalTrackEntry> download(Track track, {DownloadProgressCallback? onProgress}) {
    if (!isSupported) {
      return Future.error(UnsupportedError('On-device downloads are not available on this platform'));
    }
    // Block body: returning the removed Future would make whenComplete await itself.
    return _inFlight[track.id] ??= _download(track, onProgress).whenComplete(() {
      _inFlight.remove(track.id);
    });
  }

  Future<LocalTrackEntry> _download(Track track, DownloadProgressCallback? onProgress) async {
    final existing = await _store.lookup(track);
    if (existing != null) return existing;

    final stream = await _resolve(track);
    if (stream.streamUri.isScheme('file')) {
      // Resolver already returned a local file (e.g. raced with another download).
      final local = await _store.lookup(track);
      if (local != null) return local;
    }

    final request = http.Request('GET', stream.streamUri)..headers.addAll(requestHeadersFor(stream.streamUri));
    final response = await _client.send(request).timeout(headerTimeout);
    if (response.statusCode != 200) {
      await response.stream.drain<void>().catchError((_) {});
      throw http.ClientException('HTTP ${response.statusCode} downloading "${track.title}"', stream.streamUri);
    }

    final total = response.contentLength;
    var received = 0;
    final body = response.stream.timeout(stallTimeout).map((chunk) {
      received += chunk.length;
      onProgress?.call(received, total);
      return chunk;
    });

    final entry = await _store.save(
      track,
      body,
      format: stream.format,
      duration: stream.duration,
      sourceVideoId: stream.sourceVideoId,
      expectedBytes: total,
    );
    developer.log(
      'Saved "${track.title}" for offline playback (${entry.bytes} bytes, ${entry.format})',
      name: 'OfflineDownload',
    );
    return entry;
  }

  /// Removes [track] from the device; returns bytes freed.
  Future<int> remove(Track track) => _store.remove(track);

  Future<List<LocalTrackEntry>> entries() => _store.entries();

  Future<int> totalBytes() => _store.totalBytes();

  /// Mirrors the playback handler: YouTube CDN wants identity encoding; our
  /// own server and other hosts get no extra headers.
  static Map<String, String> requestHeadersFor(Uri uri) {
    if (uri.host.toLowerCase().contains('googlevideo.com')) {
      return const {'Accept': '*/*', 'Accept-Encoding': 'identity;q=1, *;q=0'};
    }
    return const {};
  }

  void dispose() => _client.close();
}
