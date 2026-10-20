import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';
import 'package:symphony/features/for_you/domain/listening_log.dart';
import 'package:symphony/features/for_you/domain/play_event.dart';
import 'package:symphony/features/for_you/domain/recap.dart';
import 'package:symphony/features/for_you/domain/taste_profile.dart';

const _len = Duration(minutes: 3);

PlayEvent play(String title, String artist, DateTime at, {Duration listened = _len, Duration length = _len}) =>
    PlayEvent.of(Track(id: 'id_$title', title: title, artist: artist), listened: listened, length: length, at: at);

void main() {
  group('PlayOutcome', () {
    test('a few seconds is a skip, most of a song is a completion', () {
      expect(PlayOutcome.of(listened: const Duration(seconds: 10), length: _len), PlayOutcome.skipped);
      expect(PlayOutcome.of(listened: const Duration(seconds: 90), length: _len), PlayOutcome.partial);
      expect(PlayOutcome.of(listened: const Duration(seconds: 150), length: _len), PlayOutcome.completed);
      // The last 15 seconds are often an outro or silence.
      expect(PlayOutcome.of(listened: const Duration(seconds: 166), length: _len), PlayOutcome.completed);
    });

    test('a short song is a skip only under half of it', () {
      const short = Duration(seconds: 40);
      expect(PlayOutcome.of(listened: const Duration(seconds: 15), length: short), PlayOutcome.skipped);
      expect(PlayOutcome.of(listened: const Duration(seconds: 25), length: short), PlayOutcome.partial);
    });
  });

  test('songs from different sources are the same song', () {
    expect(songKeyOf('drivers license', 'Olivia Rodrigo'), songKeyOf('Drivers License (Remastered)', 'Olivia Rodrigo, Someone'));
    expect(leadArtistOf('Calvin Harris feat. Dua Lipa'), 'Calvin Harris');
    expect(leadArtistOf('Simon & Garfunkel'), 'Simon');
  });

  group('ListeningLog', () {
    test('keeps monthly totals after single plays age out', () {
      final log = ListeningLog();
      log.add(play('Old', 'A', DateTime(2026, 1, 5, 9)));
      log.add(play('New', 'B', DateTime(2026, 10, 1, 21)));

      expect(log.recent.map((e) => e.title), ['New'], reason: 'January is past the 120 days kept');
      expect(log.months.keys, containsAll(['2026-01', '2026-10']));
      expect(log.months['2026-01']!.songs.values.single.plays, 1);
    });

    test('a skip adds listening time but not a play', () {
      final log = ListeningLog()..add(play('S', 'A', DateTime(2026, 10, 2), listened: const Duration(seconds: 5)));
      final tally = log.months['2026-10']!.songs.values.single;
      expect(tally.plays, 0);
      expect(tally.listened, const Duration(seconds: 5));
    });

    test('survives a save and load', () {
      final log = ListeningLog()
        ..add(play('One', 'A', DateTime(2026, 10, 2, 8)))
        ..add(play('Two', 'B', DateTime(2026, 10, 3, 23), listened: const Duration(seconds: 3)));
      final back = ListeningLog.fromJson(log.toJson());
      expect(back.recent.map((e) => (e.title, e.outcome)), [('One', PlayOutcome.completed), ('Two', PlayOutcome.skipped)]);
      expect(back.months['2026-10']!.days, {2, 3});
      expect(back.months['2026-10']!.byHour[8], _len);
    });
  });

  group('TasteProfile', () {
    final now = DateTime(2026, 10, 20);

    test('ranks artists by plays heard through; skips count against', () {
      final log = ListeningLog();
      for (var i = 0; i < 3; i++) {
        log.add(play('Song $i', 'Loved', now.subtract(Duration(days: i))));
      }
      log.add(play('Meh', 'Okay', now));
      for (var i = 0; i < 3; i++) {
        log.add(play('Nope $i', 'Skipped', now, listened: const Duration(seconds: 4)));
      }
      final taste = TasteProfile.from(log, now: now);

      expect(taste.topArtists(), ['Loved', 'Okay']);
      expect(taste.dislikesArtist('Skipped'), isTrue);
      expect(taste.heard, contains(songKeyOf('Nope 0', 'Skipped')));
    });

    test('recent plays count more than old ones', () {
      final log = ListeningLog()
        ..add(play('Old', 'Then', now.subtract(const Duration(days: 90))))
        ..add(play('Old 2', 'Then', now.subtract(const Duration(days: 91))))
        ..add(play('New', 'Now', now));
      expect(TasteProfile.from(log, now: now).topArtists().first, 'Now');
    });

    test('imported playlists give a new user a starting point', () {
      final taste = TasteProfile.from(ListeningLog(), now: now, seedTracks: const [
        Track(id: '1', title: 'A', artist: 'Imported'),
      ]);
      expect(taste.isEmpty, isFalse);
      expect(taste.topArtists(), ['Imported']);
    });
  });

  group('Recap', () {
    test('a year: totals, top songs and artists, peak hour and streak', () {
      final log = ListeningLog();
      // Played Oct 1, 2, 3 (a 3-day streak) and Nov 10, mostly at 10 PM.
      for (final d in [1, 2, 3]) {
        log.add(play('Hit', 'Star', DateTime(2026, 10, d, 22)));
      }
      log.add(play('Other', 'Band', DateTime(2026, 10, 2, 8)));
      log.add(play('Hit', 'Star', DateTime(2026, 11, 10, 22)));

      final recap = Recap.year(log, 2026);
      expect(recap.listened, _len * 5);
      expect(recap.plays, 5);
      expect(recap.topSongs.first.title, 'Hit');
      expect(recap.topSongs.first.plays, 4);
      expect(recap.topArtists.map((a) => a.name), ['Star', 'Band']);
      expect(recap.peakHour, 22);
      expect(recap.activeDays, 4);
      expect(recap.longestStreak, 3);
      expect(recap.byMonth[9], _len * 4);
      expect(recap.byMonth[10], _len);
    });

    test('a month only counts that month', () {
      final log = ListeningLog()
        ..add(play('Oct', 'A', DateTime(2026, 10, 5)))
        ..add(play('Nov', 'B', DateTime(2026, 11, 5)));
      final recap = Recap.month(log, 2026, 11);
      expect(recap.title, 'November 2026');
      expect(recap.topSongs.map((s) => s.title), ['Nov']);
    });

    test('nothing played: empty, and years lists only those with listening', () {
      final log = ListeningLog()..add(play('X', 'A', DateTime(2025, 3, 1)));
      expect(Recap.year(log, 2026).isEmpty, isTrue);
      expect(Recap.yearsIn(log), [2025]);
    });
  });
}
