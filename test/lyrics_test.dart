import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:symphony/features/lyrics/data/lyrics_service.dart';
import 'package:symphony/features/lyrics/domain/lyrics.dart';

void main() {
  group('LRC parsing', () {
    test('reads timestamps in their different precisions', () {
      final lines = Lyrics.parseLrc('[00:01.5]a\n[00:02.25]b\n[00:03.125]c\n[01:04]d');
      expect(lines.map((l) => l.time.inMilliseconds), [1500, 2250, 3125, 64000]);
      expect(lines.map((l) => l.text), ['a', 'b', 'c', 'd']);
    });

    test('expands lines with several timestamps and sorts them', () {
      final lines = Lyrics.parseLrc('[00:10.00][00:30.00]chorus\n[00:20.00]verse');
      expect(lines.map((l) => l.text), ['chorus', 'verse', 'chorus']);
    });

    test('skips metadata tags and applies the offset', () {
      final lines = Lyrics.parseLrc('[ar:Someone]\n[offset:+500]\n[00:02.00]hi\n\n[00:00.20]start');
      expect(lines.map((l) => l.time.inMilliseconds), [0, 1500]);
    });

    test('keeps empty timed lines as pauses', () {
      final lines = Lyrics.parseLrc('[00:01.00]one\n[00:02.00]\n[00:03.00]two');
      expect(lines[1].text, '');
    });

    test('finds the line for a position', () {
      final lyrics = Lyrics(lines: Lyrics.parseLrc('[00:01.00]a\n[00:05.00]b\n[00:09.00]c'));
      expect(lyrics.lineIndexAt(Duration.zero), -1);
      expect(lyrics.lineIndexAt(const Duration(seconds: 1)), 0);
      expect(lyrics.lineIndexAt(const Duration(seconds: 7)), 1);
      expect(lyrics.lineIndexAt(const Duration(minutes: 3)), 2);
    });
  });

  group('LyricsService', () {
    test('drops featured guests but keeps duos', () {
      expect(LyricsService.primaryArtist('The Weeknd ft. Daft Punk'), 'The Weeknd');
      expect(LyricsService.primaryArtist('Drake, 21 Savage'), 'Drake');
      expect(LyricsService.primaryArtist('Simon & Garfunkel'), 'Simon & Garfunkel');
    });

    test('uses the exact match and caches it', () async {
      var calls = 0;
      final service = LyricsService(
        client: MockClient((req) async {
          calls++;
          expect(req.url.path, '/api/get');
          expect(req.url.queryParameters['track_name'], 'Starboy');
          expect(req.url.queryParameters['artist_name'], 'The Weeknd');
          expect(req.url.queryParameters['duration'], '230');
          return http.Response(jsonEncode({'syncedLyrics': '[00:01.00]hello', 'plainLyrics': 'hello'}), 200);
        }),
      );
      final first = await service.fetch(
        title: 'Starboy (feat. Daft Punk)',
        artist: 'The Weeknd ft. Daft Punk',
        duration: const Duration(seconds: 230),
      );
      final second = await service.fetch(title: 'Starboy', artist: 'The Weeknd', duration: const Duration(seconds: 230));
      expect(first!.isSynced, isTrue);
      expect(identical(first, second), isTrue);
      expect(calls, 1);
    });

    test('falls back to search and picks a synced result of the right length', () async {
      final service = LyricsService(
        client: MockClient((req) async {
          if (req.url.path == '/api/get') return http.Response('{}', 404);
          return http.Response(
            jsonEncode([
              {'duration': 300, 'syncedLyrics': '[00:01.00]wrong length'},
              {'duration': 201, 'plainLyrics': 'plain only'},
              {'duration': 199, 'syncedLyrics': '[00:01.00]right'},
            ]),
            200,
          );
        }),
      );
      final lyrics = await service.fetch(title: 'Song', artist: 'Artist', duration: const Duration(seconds: 200));
      expect(lyrics!.lines.single.text, 'right');
    });

    test('takes a result of another length when none is close', () {
      final picked = LyricsService.pickBest([
        {'duration': 300, 'plainLyrics': 'plain'},
        {'duration': 310, 'syncedLyrics': '[00:01.00]synced'},
      ], 180);
      expect(picked!.isSynced, isTrue);
    });

    test('returns null when nothing is found', () async {
      final service = LyricsService(
        client: MockClient((req) async => req.url.path == '/api/get' ? http.Response('{}', 404) : http.Response('[]', 200)),
      );
      expect(await service.fetch(title: 'Nope', artist: 'Nobody', duration: const Duration(seconds: 100)), isNull);
    });

    test('reports a failed lookup as an error, not as "no lyrics"', () async {
      final service = LyricsService(client: MockClient((_) async => http.Response('oops', 500)));
      expect(
        service.fetch(title: 'Song', artist: 'Artist'),
        throwsA(isA<LyricsLookupException>()),
      );
    });
  });
}
