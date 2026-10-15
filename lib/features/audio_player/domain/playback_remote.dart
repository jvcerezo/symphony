import 'entities/track.dart';

/// Takes the user's playback actions while this device follows another one
/// (a Jam guest): they are sent there instead of played here.
///
/// Indexes are positions in play order, as in the handler's queue.
abstract interface class PlaybackRemote {
  void play();
  void pause();
  void seek(Duration position);
  void next();
  void previous();
  void jumpTo(int index);
  void add(Track track);
  void playNext(Track track);
  void remove(int index);
  void move(int from, int to);
}
