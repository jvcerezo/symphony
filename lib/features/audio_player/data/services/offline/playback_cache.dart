import 'dart:async';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../../../domain/entities/resolved_audio_stream.dart';
import '../../../domain/entities/track.dart';
import 'chunked_download.dart';
import 'local_track_store.dart';

/// Short-lived local copies of tracks for playback on native platforms.
///
/// Playing a downloaded file instead of a remote URL keeps network streaming
/// out of the media player (and out of just_audio's header proxy, which runs
/// on the UI isolate), makes seeking instant, and avoids YouTube's throttling
/// of long-lived connections. Separate from user downloads: entries here are
/// evicted oldest-first once [maxBytes] is exceeded.
class PlaybackCache {
  PlaybackCache({
    LocalTrackStore? store,
    http.Client? httpClient,
    this.maxBytes = 400 * 1024 * 1024,
  })  : _store = store ?? LocalTrackStore.playbackCache(),
        _client = httpClient ?? http.Client();

  final LocalTrackStore _store;
  final http.Client _client;
  final int maxBytes;

  final Map<String, Future<Uri>> _inFlight = {};

  bool get isSupported => _store.isSupported;

  /// Whether [stream] is something this cache should fetch (remote http/s).
  static bool shouldCache(ResolvedAudioStream stream) =>
      stream.streamUri.isScheme('http') || stream.streamUri.isScheme('https');

  /// A `file://` URI holding [track]'s audio, downloading [stream] if needed.
  /// Concurrent calls for one track share a download. Throws on failure.
  Future<Uri> fileFor(Track track, ResolvedAudioStream stream) {
    // Block body: returning the removed Future would make whenComplete await itself.
    return _inFlight[track.id] ??= _fetch(track, stream).whenComplete(() {
      _inFlight.remove(track.id);
    });
  }

  /// Drops [track]'s cached copy (e.g. after it failed to load).
  Future<void> forget(Track track) async {
    try {
      await _store.remove(track);
    } catch (_) {}
  }

  /// The cached file for [track] if present, without any network.
  Future<Uri?> cachedFileFor(Track track) async => (await _store.lookup(track))?.fileUri;

  Future<Uri> _fetch(Track track, ResolvedAudioStream stream) async {
    final existing = await _store.lookup(track);
    if (existing != null) return existing.fileUri;

    final sw = Stopwatch()..start();
    final entry = await _store.save(
      track,
      chunkedDownload(_client, stream.streamUri, headers: stream.headers),
      format: stream.format,
      duration: stream.duration,
      sourceVideoId: stream.sourceVideoId,
    );
    developer.log(
      'Cached "${track.title}" for playback (${entry.bytes} bytes in ${sw.elapsedMilliseconds} ms)',
      name: 'PlaybackCache',
    );
    unawaited(_evict(keepTrackId: track.id));
    return entry.fileUri;
  }

  Future<void> _evict({required String keepTrackId}) async {
    try {
      final entries = await _store.entries()
        ..sort((a, b) => a.downloadedAt.compareTo(b.downloadedAt));
      var total = entries.fold<int>(0, (sum, e) => sum + e.bytes);
      for (final e in entries) {
        if (total <= maxBytes) break;
        if (e.trackId == keepTrackId) continue;
        total -= e.bytes;
        await _store.remove(Track(id: e.trackId, title: e.title, artist: e.artist));
      }
    } catch (e) {
      developer.log('Cache eviction failed: $e', name: 'PlaybackCache');
    }
  }

  void dispose() => _client.close();
}
