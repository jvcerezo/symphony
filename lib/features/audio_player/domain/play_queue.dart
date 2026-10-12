import 'dart:math';
import 'entities/track.dart';

/// What happens when a track or the whole queue ends.
enum QueueRepeatMode { off, all, one }

/// The play order of the current queue, with shuffle, repeat and edits.
///
/// [tracks] is always the order songs play in, and [index] points at the
/// current one. Shuffling reorders [tracks] (current song first, the rest
/// random) and remembers the original order so turning shuffle off restores
/// it. Tracks are matched by identity, so a song listed twice stays two
/// separate entries.
class PlayQueue {
  final Random _random;
  final List<Track> _tracks = [];

  /// Original (unshuffled) order while shuffle is on, otherwise null.
  List<Track>? _originalOrder;
  int _index = -1;

  QueueRepeatMode repeatMode = QueueRepeatMode.off;

  PlayQueue({Random? random}) : _random = random ?? Random();

  List<Track> get tracks => List.unmodifiable(_tracks);
  int get index => _index;
  int get length => _tracks.length;
  bool get isEmpty => _tracks.isEmpty;
  bool get isShuffled => _originalOrder != null;

  Track? get current => (_index >= 0 && _index < _tracks.length) ? _tracks[_index] : null;

  /// Replaces the queue and makes [startIndex] (of [tracks]) the current song.
  /// With shuffle on, that song plays first and the rest are shuffled.
  void load(List<Track> tracks, {int startIndex = 0}) {
    _tracks
      ..clear()
      ..addAll(tracks);
    if (_tracks.isEmpty) {
      _index = -1;
      if (isShuffled) _originalOrder = [];
      return;
    }
    _index = startIndex.clamp(0, _tracks.length - 1);
    if (isShuffled) {
      _originalOrder = List.of(_tracks);
      _shuffleAroundCurrent();
    }
  }

  void setShuffle(bool enabled) {
    if (enabled == isShuffled) return;
    if (enabled) {
      _originalOrder = List.of(_tracks);
      _shuffleAroundCurrent();
      return;
    }
    final current = this.current;
    _tracks
      ..clear()
      ..addAll(_originalOrder!);
    _originalOrder = null;
    _index = current == null ? (_tracks.isEmpty ? -1 : 0) : _indexOfIdentical(_tracks, current);
  }

  void _shuffleAroundCurrent() {
    final current = this.current;
    final rest = List.of(_tracks);
    if (current != null) rest.removeAt(_index);
    rest.shuffle(_random);
    _tracks
      ..clear()
      ..addAll([if (current != null) current, ...rest]);
    _index = current == null ? -1 : 0;
  }

  /// The index to play after the current song, or null to stop.
  /// [auto] is true when the song ended by itself (repeat-one replays it);
  /// a manual skip always moves on, wrapping to the start at the end.
  int? nextIndex({required bool auto}) {
    if (_tracks.isEmpty) return null;
    if (auto && repeatMode == QueueRepeatMode.one) return _index;
    if (_index + 1 < _tracks.length) return _index + 1;
    if (repeatMode != QueueRepeatMode.off || !auto) return 0;
    return null;
  }

  /// The index to play for "previous": the song before, the last one when
  /// repeating the queue, otherwise the current one again.
  int? previousIndex() {
    if (_tracks.isEmpty) return null;
    if (_index > 0) return _index - 1;
    if (repeatMode == QueueRepeatMode.all) return _tracks.length - 1;
    return _index;
  }

  /// Makes [index] the current song. Returns false when out of range.
  bool jumpTo(int index) {
    if (index < 0 || index >= _tracks.length) return false;
    _index = index;
    return true;
  }

  /// Songs that would play after the current one, in order (wrapping when
  /// the whole queue repeats). Used for preloading.
  List<Track> upcoming(int count) {
    final result = <Track>[];
    if (_tracks.isEmpty || count <= 0) return result;
    final wraps = repeatMode == QueueRepeatMode.all;
    for (int offset = 1; offset <= count && offset < _tracks.length; offset++) {
      final i = _index + offset;
      if (i < _tracks.length) {
        result.add(_tracks[i]);
      } else if (wraps) {
        result.add(_tracks[i % _tracks.length]);
      } else {
        break;
      }
    }
    return result;
  }

  /// Puts [track] right after the current song.
  void playNext(Track track) {
    final current = this.current;
    _tracks.insert(_index + 1, track);
    if (_tracks.length == 1) _index = 0;
    final original = _originalOrder;
    if (original != null) {
      final at = current == null ? -1 : _indexOfIdentical(original, current);
      original.insert(at + 1, track);
    }
  }

  /// Adds [track] to the end of the queue.
  void add(Track track) {
    _tracks.add(track);
    if (_tracks.length == 1) _index = 0;
    _originalOrder?.add(track);
  }

  /// Removes the song at [index]. The current song can't be removed.
  bool removeAt(int index) {
    if (index < 0 || index >= _tracks.length || index == _index) return false;
    final removed = _tracks.removeAt(index);
    final original = _originalOrder;
    if (original != null) {
      final at = _indexOfIdentical(original, removed);
      if (at >= 0) original.removeAt(at);
    }
    if (index < _index) _index--;
    return true;
  }

  /// Moves the song at [from] so it ends up at [to] (both in play order).
  bool move(int from, int to) {
    if (from < 0 || from >= _tracks.length || to < 0 || to >= _tracks.length) return false;
    if (from == to) return true;
    final current = this.current;
    final track = _tracks.removeAt(from);
    _tracks.insert(to, track);
    if (current != null) _index = _indexOfIdentical(_tracks, current);
    return true;
  }

  static int _indexOfIdentical(List<Track> list, Track track) {
    for (int i = 0; i < list.length; i++) {
      if (identical(list[i], track)) return i;
    }
    return -1;
  }
}
