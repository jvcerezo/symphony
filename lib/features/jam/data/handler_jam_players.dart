import 'package:rxdart/rxdart.dart';

import '../../audio_player/data/services/symphony_audio_handler.dart';
import '../../audio_player/domain/entities/track.dart';
import '../../audio_player/domain/playback_remote.dart';
import 'jam_players.dart';

/// The app's [SymphonyAudioHandler] as a Jam host's player.
class HandlerJamHostPlayer implements JamHostPlayer {
  HandlerJamHostPlayer(this._handler);

  final SymphonyAudioHandler _handler;

  @override
  List<Track> get queue => _handler.currentQueue;
  @override
  int get index => _handler.currentIndex;
  @override
  bool get isPlaying => _handler.isPlayingHere && !_handler.isLoadingTrack;
  @override
  Duration get position => _handler.position;
  @override
  String? get currentVideoId => _handler.resolvedVideoIdStream.value;
  @override
  Future<String?> videoIdFor(Track track) => _handler.streamResolver.knownVideoId(track);

  @override
  Stream<void> get changes => Rx.merge<Object?>([
        _handler.playlistQueueStream,
        _handler.currentIndexStream,
        _handler.playbackState,
        _handler.resolvedVideoIdStream,
      ]);

  @override
  Future<void> play() => _handler.play();
  @override
  Future<void> pause() => _handler.pause();
  @override
  Future<void> seek(Duration position) => _handler.seek(position);
  @override
  Future<void> next() => _handler.skipToNext();
  @override
  Future<void> previous() => _handler.skipToPrevious();
  @override
  Future<void> jumpTo(int index) => _handler.skipToQueueItem(index);
  @override
  void add(Track track) => _handler.enqueue(track);
  @override
  void playNext(Track track) => _handler.playNext(track);
  @override
  void remove(int index) => _handler.removeFromQueue(index);
  @override
  void move(int from, int to) => _handler.moveInQueue(from, to);
}

/// The app's [SymphonyAudioHandler] as a Jam guest's player.
class HandlerJamGuestPlayer implements JamGuestPlayer {
  HandlerJamGuestPlayer(this._handler);

  final SymphonyAudioHandler _handler;

  @override
  set remote(PlaybackRemote? remote) => _handler.remote = remote;

  @override
  void followQueue(List<Track> tracks, int index) => _handler.followQueue(tracks, index);
  @override
  Future<void> loadCurrent({required Duration startAt, required bool play}) =>
      _handler.followLoadCurrent(startAt: startAt, play: play);
  @override
  Future<void> setPlaying(bool playing) => _handler.followPlaying(playing);
  @override
  Future<void> seek(Duration position) => _handler.followSeek(position);

  @override
  Duration get position => _handler.position;
  @override
  bool get isPlaying => _handler.isPlayingHere;
  @override
  bool get isLoading => _handler.isLoadingTrack;
}
