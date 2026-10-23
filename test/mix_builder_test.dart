import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';
import 'package:symphony/features/for_you/data/deezer_catalog.dart';
import 'package:symphony/features/for_you/data/mix_builder.dart';
import 'package:symphony/features/for_you/domain/listening_log.dart';
import 'package:symphony/features/for_you/domain/play_event.dart';
import 'package:symphony/features/for_you/domain/taste_profile.dart';

/// A small Deezer: artists 1 (Fave) and 2 (Also Liked) are related to 3–6.
class _FakeDeezer {
  final requests = <String>[];
  bool down = false;

  static const names = {1: 'Fave', 2: 'Also Liked', 3: 'Similar One', 4: 'Similar Two', 5: 'Similar Three', 6: 'Similar Four'};

  Map<String, Object?> _track(int artist, int n) => {
        'id': artist * 100 + n,
        'title': '${names[artist]} hit $n',
        'duration': 200,
        'artist': {'id': artist, 'name': names[artist]},
        'album': {'title': 'Album', 'cover_xl': 'https://cdn.example/$artist-$n.jpg'},
      };

  late final client = MockClient((req) async {
    requests.add(req.url.path);
    if (down) throw http.ClientException('offline');
    final path = req.url.path;
    Object body;
    if (path == '/search/artist') {
      final q = req.url.queryParameters['q'];
      final hit = names.entries.where((e) => e.value == q);
      body = {'data': [for (final e in hit) {'id': e.key, 'name': e.value}]};
    } else if (path.endsWith('/related')) {
      final id = int.parse(path.split('/')[2]);
      body = {
        'data': [
          for (final r in id <= 2 ? [3, 4, 5, 6, if (id == 1) 2] : [1]) {'id': r, 'name': names[r]},
        ],
      };
    } else if (path.endsWith('/top') || path.endsWith('/radio')) {
      final id = int.parse(path.split('/')[2]);
      body = {
        'data': [
          for (var n = 1; n <= 5; n++) _track(id, n),
          // A duet credited to the user's favorite.
          if (id == 3) _track(1, 9),
        ],
      };
    } else if (path == '/chart/0/tracks') {
      body = {'data': [for (var n = 1; n <= 5; n++) _track(3, n)]};
    } else {
      body = {'error': {'code': 800}};
    }
    return http.Response(jsonEncode(body), 200);
  });
}

final _now = DateTime(2026, 10, 20, 12);

ListeningLog _likes(Map<String, int> playsByArtist) {
  final log = ListeningLog();
  for (final e in playsByArtist.entries) {
    for (var i = 0; i < e.value; i++) {
      log.add(PlayEvent.of(Track(id: '${e.key}$i', title: '${e.key} song $i', artist: e.key),
          listened: const Duration(minutes: 3), length: const Duration(minutes: 3), at: _now.subtract(Duration(hours: i))));
    }
  }
  return log;
}

void main() {
  late _FakeDeezer deezer;
  late MixBuilder builder;

  setUp(() {
    deezer = _FakeDeezer();
    builder = MixBuilder(catalog: DeezerCatalog(httpClient: deezer.client), clock: () => _now);
  });

  test('Daily Mix: the favorite\'s songs the user likes, then new ones from similar artists', () async {
    final taste = TasteProfile.from(_likes({'Fave': 6}), now: _now);
    final mixes = await builder.dailyMixes(taste, now: _now);

    expect(mixes, hasLength(1), reason: 'every other artist is in the first mix');
    final mix = mixes.single;
    expect(mix.title, 'Daily Mix 1');
    expect(mix.id, 'mix_daily_1_20261020');
    expect(mix.description, startsWith('Fave, Similar One'));
    final artists = mix.tracks.map((t) => t.artist).toSet();
    expect(artists, containsAll(['Fave', 'Similar One']));
    expect(mix.tracks.where((t) => t.title.startsWith('Fave song')), isNotEmpty, reason: 'familiar songs are in');
    final perArtist = <String, int>{};
    for (final t in mix.tracks) {
      perArtist[t.artist] = (perArtist[t.artist] ?? 0) + 1;
    }
    expect(perArtist.values.every((n) => n <= 4), isTrue);
  });

  test('the same day builds the same mix', () async {
    final taste = TasteProfile.from(_likes({'Fave': 6}), now: _now);
    final a = await builder.dailyMixes(taste, now: _now);
    final b = await builder.dailyMixes(taste, now: _now);
    expect(b.single.tracks.map((t) => t.id), a.single.tracks.map((t) => t.id));
  });

  test('Discover Weekly only has artists and songs the user hasn\'t heard', () async {
    final taste = TasteProfile.from(_likes({'Fave': 4, 'Also Liked': 3}), now: _now);
    final mix = await builder.discoverWeekly(taste, now: _now);

    expect(mix, isNotNull);
    expect(mix!.tracks.map((t) => t.artist).toSet().intersection({'Fave', 'Also Liked'}), isEmpty);
    final perArtist = <String, int>{};
    for (final t in mix.tracks) {
      perArtist[t.artist] = (perArtist[t.artist] ?? 0) + 1;
    }
    expect(perArtist.values.every((n) => n <= 2), isTrue);
    expect(MixBuilder.weekStart(_now), DateTime(2026, 10, 19), reason: 'weeks start on Monday');
  });

  test('autoplay radio leaves out what is already queued and the seed itself', () async {
    const seed = Track(id: 'x', title: 'Fave hit 1', artist: 'Fave');
    final radio = await builder.radioAfter(seed, exclude: {songKeyOf('Fave hit 2', 'Fave')});
    final titles = radio.map((t) => t.title);
    expect(titles, isNot(contains('Fave hit 1')));
    expect(titles, isNot(contains('Fave hit 2')));
    expect(radio.length, 3, reason: 'at most 3 songs per artist');
    expect(radio.first.id, startsWith('dz_'));
    expect(radio.first.expectedDuration, const Duration(seconds: 200));
  });

  test('autoplay after a queue falls back to earlier artists when the last one finds nothing', () async {
    const queue = [
      Track(id: 'f', title: 'Fave hit 1', artist: 'Fave'),
      Track(id: 'n', title: 'Unknown song', artist: 'Nobody Deezer Knows'),
    ];
    final radio = await builder.radioAfterQueue(queue);
    expect(radio, isNotEmpty);
    expect(radio.map((t) => t.title), isNot(contains('Fave hit 1')));
  });

  test('offline: nothing is built and nothing breaks', () async {
    deezer.down = true;
    final taste = TasteProfile.from(_likes({'Fave': 6}), now: _now);
    expect(await builder.dailyMixes(taste, now: _now), isEmpty);
    expect(await builder.discoverWeekly(taste, now: _now), isNull);
    expect(await builder.topHits(), isNull);
  });

  test('On Repeat and Recently Played come from the plays alone', () {
    final log = _likes({'A': 2, 'B': 2, 'C': 2, 'D': 2, 'E': 2});
    // Same song played twice for each artist: make the titles repeat.
    final repeat = ListeningLog();
    for (final e in log.recent) {
      repeat.add(PlayEvent.of(Track(id: e.artist, title: '${e.artist} anthem', artist: e.artist),
          listened: e.listened, length: e.length, at: e.at));
    }
    expect(builder.onRepeat(repeat, now: _now)!.tracks, hasLength(5));
    expect(builder.recentlyPlayed(repeat)!.tracks, hasLength(5));
    expect(deezer.requests, isEmpty);
  });
}
