import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';
import 'package:symphony/features/audio_player/domain/play_queue.dart';

Track _t(String id) => Track(id: id, title: 'Song $id', artist: 'Artist');

List<String> _ids(PlayQueue q) => q.tracks.map((t) => t.id).toList();

void main() {
  late List<Track> songs;
  late PlayQueue queue;

  setUp(() {
    songs = ['a', 'b', 'c', 'd', 'e'].map(_t).toList();
    queue = PlayQueue(random: Random(7));
  });

  group('next and previous', () {
    test('auto-advance stops at the end when repeat is off', () {
      queue.load(songs, startIndex: 4);
      expect(queue.nextIndex(auto: true), isNull);
    });

    test('manual next at the end wraps to the start', () {
      queue.load(songs, startIndex: 4);
      expect(queue.nextIndex(auto: false), 0);
    });

    test('repeat all wraps when a song ends', () {
      queue
        ..repeatMode = QueueRepeatMode.all
        ..load(songs, startIndex: 4);
      expect(queue.nextIndex(auto: true), 0);
    });

    test('repeat one replays the song but a manual skip moves on', () {
      queue
        ..repeatMode = QueueRepeatMode.one
        ..load(songs, startIndex: 2);
      expect(queue.nextIndex(auto: true), 2);
      expect(queue.nextIndex(auto: false), 3);
    });

    test('previous on the first song restarts it unless repeating all', () {
      queue.load(songs);
      expect(queue.previousIndex(), 0);
      queue.repeatMode = QueueRepeatMode.all;
      expect(queue.previousIndex(), 4);
    });

    test('empty queue has nowhere to go', () {
      expect(queue.nextIndex(auto: false), isNull);
      expect(queue.previousIndex(), isNull);
      expect(queue.current, isNull);
    });
  });

  group('shuffle', () {
    test('keeps the current song first and the same set of songs', () {
      queue.load(songs, startIndex: 2);
      queue.setShuffle(true);
      expect(queue.index, 0);
      expect(queue.current!.id, 'c');
      expect(_ids(queue).toSet(), {'a', 'b', 'c', 'd', 'e'});
    });

    test('turning it off restores the order and keeps the current song', () {
      queue.load(songs);
      queue.setShuffle(true);
      queue.jumpTo(3);
      final playing = queue.current;
      queue.setShuffle(false);
      expect(_ids(queue), ['a', 'b', 'c', 'd', 'e']);
      expect(identical(queue.current, playing), isTrue);
    });

    test('loading while shuffled starts with the chosen song', () {
      queue.setShuffle(true);
      queue.load(songs, startIndex: 3);
      expect(queue.current!.id, 'd');
      expect(queue.index, 0);
      queue.setShuffle(false);
      expect(_ids(queue), ['a', 'b', 'c', 'd', 'e']);
      expect(queue.index, 3);
    });

    test('songs added while shuffled survive turning it off', () {
      queue.load(songs);
      queue.setShuffle(true);
      final extra = _t('x');
      queue.add(extra);
      queue.setShuffle(false);
      expect(_ids(queue), ['a', 'b', 'c', 'd', 'e', 'x']);
    });

    test('a song listed twice stays two entries', () {
      final twice = _t('z');
      queue.load([twice, songs[0], twice]);
      queue.setShuffle(true);
      queue.setShuffle(false);
      expect(_ids(queue), ['z', 'a', 'z']);
      expect(queue.index, 0);
    });
  });

  group('editing', () {
    test('play next inserts after the current song', () {
      queue.load(songs, startIndex: 1);
      queue.playNext(_t('x'));
      expect(_ids(queue), ['a', 'b', 'x', 'c', 'd', 'e']);
      expect(queue.current!.id, 'b');
    });

    test('play next into an empty queue makes it current', () {
      queue.playNext(_t('x'));
      expect(queue.index, 0);
      expect(queue.current!.id, 'x');
    });

    test('removing an earlier song keeps the current one', () {
      queue.load(songs, startIndex: 3);
      expect(queue.removeAt(1), isTrue);
      expect(_ids(queue), ['a', 'c', 'd', 'e']);
      expect(queue.current!.id, 'd');
    });

    test('the current song cannot be removed', () {
      queue.load(songs, startIndex: 2);
      expect(queue.removeAt(2), isFalse);
      expect(queue.length, 5);
    });

    test('moving songs follows the current one', () {
      queue.load(songs, startIndex: 1);
      expect(queue.move(4, 0), isTrue);
      expect(_ids(queue), ['e', 'a', 'b', 'c', 'd']);
      expect(queue.current!.id, 'b');
      expect(queue.move(2, 4), isTrue);
      expect(queue.current!.id, 'b');
      expect(queue.index, 4);
    });

    test('upcoming lists what plays next and wraps only when repeating all', () {
      queue.load(songs, startIndex: 3);
      expect(queue.upcoming(3).map((t) => t.id), ['e']);
      queue.repeatMode = QueueRepeatMode.all;
      expect(queue.upcoming(3).map((t) => t.id), ['e', 'a', 'b']);
    });
  });
}
