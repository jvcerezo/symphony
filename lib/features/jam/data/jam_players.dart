import '../../audio_player/domain/entities/track.dart';
import '../../audio_player/domain/playback_remote.dart';

/// The host's player, as the Jam host service sees it.
abstract interface class JamHostPlayer {
  /// Play order.
  List<Track> get queue;
  int get index;

  /// Audible right now: playing and not loading a song.
  bool get isPlaying;
  Duration get position;

  /// The YouTube video the current song is playing from, once known.
  String? get currentVideoId;

  /// The video [track] will play from, if already known. Never searches.
  Future<String?> videoIdFor(Track track);

  /// Fires when the queue, the current song or playback changes.
  Stream<void> get changes;

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> next();
  Future<void> previous();
  Future<void> jumpTo(int index);
  void add(Track track);
  void playNext(Track track);
  void remove(int index);
  void move(int from, int to);
}

/// A guest's player, as the Jam guest service drives it.
abstract interface class JamGuestPlayer {
  /// While set, the user's own actions go to it instead of playing here,
  /// and the player doesn't move on by itself when a song ends.
  set remote(PlaybackRemote? remote);

  /// Shows [tracks] as the queue with [index] current, playing nothing.
  void followQueue(List<Track> tracks, int index);

  /// Loads the current song at [startAt]; plays it unless [play] is false.
  Future<void> loadCurrent({required Duration startAt, required bool play});

  Future<void> setPlaying(bool playing);
  Future<void> seek(Duration position);

  Duration get position;
  bool get isPlaying;
  bool get isLoading;
}
