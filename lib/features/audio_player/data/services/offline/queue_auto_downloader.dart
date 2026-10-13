import 'dart:async';
import 'dart:developer' as developer;

import '../../../domain/entities/track.dart';

/// Saves the playing queue's songs to the device in the background, so a
/// playlist listened to online is ready to play offline.
///
/// Runs beside playback, one song at a time. Songs from two ahead go first;
/// the next song and the current one go last, because the player saves a
/// playback copy of those itself and the download reuses it. Skipped: songs
/// already on the device, songs that failed [maxFailures] times, and songs
/// whose download the user removed. It waits while the player loads a song,
/// pauses while offline and retries every [offlineRetry].
class QueueAutoDownloader {
  QueueAutoDownloader({
    required this.isDownloaded,
    required this.download,
    required this.isOnline,
    bool Function()? isPlayerBusy,
    bool enabled = true,
    this.minQueueLength = 2,
    this.maxFailures = 2,
    this.busyPoll = const Duration(milliseconds: 500),
    this.offlineRetry = const Duration(seconds: 30),
  })  : _isPlayerBusy = isPlayerBusy ?? _never,
        _enabled = enabled;

  static bool _never() => false;

  final Future<bool> Function(Track track) isDownloaded;
  final Future<void> Function(Track track) download;
  final Future<bool> Function() isOnline;
  final bool Function() _isPlayerBusy;

  /// A single song (a search result, say) is not a playlist: left alone.
  final int minQueueLength;
  final int maxFailures;
  final Duration busyPoll;
  final Duration offlineRetry;

  bool _enabled;
  bool _running = false;
  bool _disposed = false;
  Timer? _retry;
  List<Track> _queue = const [];
  int _current = -1;
  List<Track> _pending = [];
  final Map<String, int> _failures = {};
  final Set<String> _removedByUser = {};

  /// Songs waiting to be saved, in order.
  List<Track> get pending => List.unmodifiable(_pending);

  bool get enabled => _enabled;
  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    if (value) {
      _plan();
    } else {
      _retry?.cancel();
      _pending = [];
    }
  }

  /// The player's queue changed, or moved on to [currentIndex].
  void queueChanged(List<Track> queue, int currentIndex) {
    _queue = queue;
    _current = currentIndex;
    _plan();
  }

  /// The user removed [track]'s download: it isn't saved again this session.
  void removedByUser(Track track) {
    _removedByUser.add(track.id);
    _pending.removeWhere((t) => t.id == track.id);
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _pending = [];
  }

  void _plan() {
    if (_disposed || !_enabled) return;
    if (_queue.length < minQueueLength) {
      _pending = [];
      return;
    }
    final current = _current >= 0 && _current < _queue.length ? _current : 0;
    final after = current + 1 < _queue.length ? current + 1 : null;
    final order = [
      ..._queue.skip(current + 2),
      ..._queue.take(current),
      if (after != null) _queue[after],
      _queue[current],
    ];
    final seen = <String>{};
    _pending = [
      for (final t in order)
        if (seen.add(t.id) && !_removedByUser.contains(t.id) && (_failures[t.id] ?? 0) < maxFailures) t,
    ];
    _retry?.cancel();
    unawaited(_run());
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    try {
      while (!_disposed && _enabled && _pending.isNotEmpty) {
        // Playback comes first.
        while (_isPlayerBusy() && !_disposed) {
          await Future<void>.delayed(busyPoll);
        }
        if (_disposed || !_enabled || _pending.isEmpty) break;
        if (!await isOnline()) {
          _retry?.cancel();
          _retry = Timer(offlineRetry, () => unawaited(_run()));
          break;
        }
        if (_pending.isEmpty) break;
        final track = _pending.removeAt(0);
        try {
          if (await isDownloaded(track)) continue;
          await download(track);
          developer.log('Saved "${track.title}" from the playing queue', name: 'QueueAutoDownload');
        } catch (e) {
          if (!await isOnline()) {
            // The connection dropped: not the song's fault, try it again later.
            _pending.insert(0, track);
            continue;
          }
          _failures[track.id] = (_failures[track.id] ?? 0) + 1;
          developer.log('Could not save "${track.title}": $e', name: 'QueueAutoDownload');
        }
      }
    } finally {
      _running = false;
    }
  }
}
