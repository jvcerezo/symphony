import 'dart:async';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../../../domain/entities/resolved_audio_stream.dart';
import '../../../domain/entities/track.dart';
import 'chunked_download.dart';
import 'local_track_store.dart';

/// Resolves a track to a remote stream. Normally
/// `AudioStreamResolverService.resolveBestAudioStream`.
typedef RemoteStreamResolver = Future<ResolvedAudioStream> Function(Track track);

/// Given a download's track and the video it was made from, returns the
/// right recording's stream when it was the wrong one, or null. Throws when
/// it can't tell right now. Normally
/// `AudioStreamResolverService.checkDownloadedMatch`.
typedef DownloadMatchCheck = Future<ResolvedAudioStream?> Function(Track track, String downloadedVideoId);

/// Reports bytes received so far and the total if the server sent one.
typedef DownloadProgressCallback = void Function(int received, int? total);

/// Downloads a track's resolved audio stream into a [LocalTrackStore] so it
/// plays with no network. Not available on web ([isSupported] is false).
class OfflineDownloadService {
  OfflineDownloadService({
    required RemoteStreamResolver resolve,
    DownloadMatchCheck? checkMatch,
    LocalTrackStore? store,
    http.Client? httpClient,
    this.headerTimeout = const Duration(seconds: 20),
    this.stallTimeout = const Duration(seconds: 30),
  })  : _resolve = resolve,
        _checkMatch = checkMatch,
        _store = store ?? LocalTrackStore.platform(),
        _client = httpClient ?? http.Client();

  final RemoteStreamResolver _resolve;
  final DownloadMatchCheck? _checkMatch;
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

    return _save(track, stream, onProgress);
  }

  Future<LocalTrackEntry> _save(Track track, ResolvedAudioStream stream, DownloadProgressCallback? onProgress) async {
    // Ranged chunks: YouTube throttles one long GET to roughly playback speed.
    final body = chunkedDownload(
      _client,
      stream.streamUri,
      headers: stream.headers ?? requestHeadersFor(stream.streamUri),
      chunkTimeout: stallTimeout,
      onProgress: onProgress,
    );

    final entry = await _store.save(
      track,
      body,
      format: stream.format,
      duration: stream.duration,
      sourceVideoId: stream.sourceVideoId,
    );
    developer.log(
      'Saved "${track.title}" for offline playback (${entry.bytes} bytes, ${entry.format})',
      name: 'OfflineDownload',
    );
    return entry;
  }

  /// Checks each download whose match was never checked and re-downloads
  /// the ones that turn out to be a different recording. The old file stays
  /// until its replacement is complete. One at a time; stops at the first
  /// download it can't check (offline, no song search) to retry later.
  /// [trackFor] supplies the library's track (with its real length) for an
  /// entry. Returns how many downloads were replaced.
  Future<int> recheckDownloads({Track? Function(LocalTrackEntry entry)? trackFor}) async {
    final check = _checkMatch;
    if (check == null || !isSupported) return 0;
    var replaced = 0;
    for (final entry in await _store.entries()) {
      if (entry.sourceVideoId.isEmpty) continue;
      final track = trackFor?.call(entry) ?? Track(id: entry.trackId, title: entry.title, artist: entry.artist);
      final ResolvedAudioStream? right;
      try {
        right = await check(track, entry.sourceVideoId);
      } catch (e) {
        developer.log('Download check paused at "${entry.title}": $e', name: 'OfflineDownload');
        break;
      }
      if (right == null) continue;
      try {
        await _save(track, right, null);
        replaced++;
      } catch (e) {
        developer.log('Could not replace the download of "${entry.title}": $e', name: 'OfflineDownload');
      }
    }
    return replaced;
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
