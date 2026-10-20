import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../../audio_player/domain/entities/track.dart';
import '../domain/play_event.dart';

/// Watches the player and turns each song played into a [PlayEvent]:
/// how long it was actually heard (paused and loading time don't count)
/// and whether it was finished or skipped. A play is recorded when the
/// next song starts or the player stops.
class PlayRecorder {
  PlayRecorder({
    required Stream<MediaItem?> mediaItems,
    required Stream<PlaybackState> states,
    required Track? Function() currentTrack,
    required this.onPlay,
    this.onProgress,
    DateTime Function()? now,
    this.progressEvery = const Duration(seconds: 15),
  })  : _currentTrack = currentTrack,
        _now = now ?? DateTime.now {
    _subs = [
      mediaItems.listen(_onItem),
      states.listen(_onState),
    ];
    if (onProgress != null) {
      _progressTimer = Timer.periodic(progressEvery, (_) {
        if (_heardSince != null) onProgress!(_event());
      });
    }
  }

  final void Function(PlayEvent) onPlay;

  /// The song playing now as it stands, every [progressEvery] while heard,
  /// so a play survives the app being closed. Recording a play replaces it.
  final void Function(PlayEvent?)? onProgress;
  final Duration progressEvery;

  final Track? Function() _currentTrack;
  final DateTime Function() _now;
  late final List<StreamSubscription<Object?>> _subs;
  Timer? _progressTimer;

  /// Plays shorter than this aren't plays (flicking through songs).
  static const minListen = Duration(seconds: 2);

  Track? _track;
  Duration _length = Duration.zero;
  DateTime? _startedAt;
  Duration _heard = Duration.zero;
  DateTime? _heardSince;

  void _onItem(MediaItem? item) {
    if (item?.id == _track?.id) {
      // Same song, more detail (its real length, artwork).
      if (item?.duration != null && item!.duration! > Duration.zero) _length = item.duration!;
      final current = _currentTrack();
      if (current != null && current.id == _track?.id) _track = current.copyWith(artworkUri: item?.artUri);
      return;
    }
    finish();
    if (item == null) return;
    final current = _currentTrack();
    _track = current != null && current.id == item.id
        ? current.copyWith(artworkUri: item.artUri)
        : Track(id: item.id, title: item.title, artist: item.artist ?? '', album: item.album, artworkUri: item.artUri);
    _length = item.duration ?? Duration.zero;
    _startedAt = _now();
  }

  void _onState(PlaybackState state) {
    final hearing = state.playing && state.processingState == AudioProcessingState.ready;
    final now = _now();
    if (hearing && _heardSince == null) {
      _heardSince = now;
    } else if (!hearing && _heardSince != null) {
      _heard += now.difference(_heardSince!);
      _heardSince = null;
    }
    if (state.processingState == AudioProcessingState.idle && !state.playing && _heard >= minListen) {
      // Stopped (or the stream died): count what was heard so far, and
      // keep counting from zero if the same song carries on.
      final e = _event();
      if (e != null) onPlay(e);
      _heard = Duration.zero;
      onProgress?.call(null);
    }
  }

  PlayEvent? _event() {
    final track = _track;
    if (track == null) return null;
    final heard = _heard + (_heardSince == null ? Duration.zero : _now().difference(_heardSince!));
    if (heard < minListen) return null;
    return PlayEvent.of(
      track,
      listened: heard,
      length: _length > Duration.zero ? _length : (track.expectedDuration ?? Duration.zero),
      at: _startedAt ?? _now(),
    );
  }

  /// Records the current song (if heard long enough) and forgets it.
  void finish() {
    final e = _event();
    if (e != null) onPlay(e);
    _track = null;
    _length = Duration.zero;
    _startedAt = null;
    _heard = Duration.zero;
    _heardSince = _heardSince == null ? null : _now();
  }

  void dispose() {
    _progressTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
  }
}
