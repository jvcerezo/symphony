import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';
import 'package:symphony/features/for_you/data/deezer_catalog.dart';
import 'package:symphony/features/for_you/data/listening_history.dart';
import 'package:symphony/features/for_you/data/mix_builder.dart';
import 'package:symphony/features/for_you/domain/listening_log.dart';
import 'package:symphony/features/for_you/domain/play_event.dart';
import 'package:symphony/features/for_you/domain/taste_profile.dart';
import 'package:symphony/features/for_you/presentation/for_you_providers.dart';

class _MemoryStore implements ListeningLogStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String? value) async => value == null ? values.remove(key) : values[key] = value;
}

PlayEvent _play(String title, DateTime at) => PlayEvent.of(Track(id: title, title: title, artist: 'Artist'),
    listened: const Duration(minutes: 3), length: const Duration(minutes: 3), at: at);

void main() {
  group('ListeningHistory', () {
    test('saves plays and reads them back', () async {
      final store = _MemoryStore();
      final history = ListeningHistory(store: store, saveDelay: Duration.zero);
      await history.loaded;
      history.record(_play('One', DateTime(2026, 10, 20)));
      await history.flush();

      final again = ListeningHistory(store: store);
      await again.loaded;
      expect(again.state.recent.single.title, 'One');
    });

    test('a song cut off by the app closing counts at the next start', () async {
      final store = _MemoryStore();
      final history = ListeningHistory(store: store);
      await history.loaded;
      await history.setInProgress(_play('Interrupted', DateTime(2026, 10, 20)));

      final next = ListeningHistory(store: store);
      await next.loaded;
      expect(next.state.recent.single.title, 'Interrupted');
      expect(store.values.containsKey(ListeningHistory.inProgressKey), isFalse);
    });

    test('clearing forgets everything', () async {
      final store = _MemoryStore();
      final history = ListeningHistory(store: store);
      await history.loaded;
      history.record(_play('One', DateTime(2026, 10, 20)));
      await history.clear();
      expect(history.state.isEmpty, isTrue);
      expect(store.values, isEmpty);
    });
  });

  group('MadeForYouNotifier', () {
    late int deezerCalls;
    late bool deezerDown;
    late _MemoryStore store;
    var now = DateTime(2026, 10, 20, 9);

    var taste = TasteProfile.from(ListeningLog(), now: now);

    MadeForYouNotifier notifier() => MadeForYouNotifier(
          builder: MixBuilder(
            catalog: DeezerCatalog(httpClient: MockClient((req) async {
              deezerCalls++;
              if (deezerDown) throw http.ClientException('offline');
              final tracks = [
                for (var i = 1; i <= 10; i++)
                  {'id': i, 'title': 'Hit $i', 'duration': 200, 'artist': {'id': 9, 'name': 'Star'}, 'album': {}},
              ];
              return http.Response(jsonEncode({'data': tracks}), 200);
            })),
            clock: () => now,
          ),
          store: store,
          taste: () => taste,
          clock: () => now,
          online: true,
        );

    setUp(() {
      deezerCalls = 0;
      deezerDown = false;
      store = _MemoryStore();
      now = DateTime(2026, 10, 20, 9);
      taste = TasteProfile.from(ListeningLog(), now: now);
    });

    const starterTitles = ['Pop Right Now', 'Hip-Hop Right Now', 'K-Pop & Asian Hits'];

    test('nothing played yet: top hits plus a mix per genre chart', () async {
      final mixes = notifier();
      await mixes.refresh();
      final titles = mixes.state.value!.map((p) => p.title).toList();
      expect(titles.first, 'Top Hits Right Now');
      expect(titles, containsAll(starterTitles));
      expect(titles, hasLength(1 + MixBuilder.starterGenres.length));
    });

    test('a cache from before starter mixes gets them the same day', () async {
      await store.write(MadeForYouNotifier.cacheKey, jsonEncode({'day': '2026-10-20', 'daily': [], 'top': null}));
      final mixes = notifier();
      await mixes.refresh();
      expect(mixes.state.value!.map((p) => p.title), containsAll(starterTitles));
      final calls = deezerCalls;

      await notifier().refresh();
      expect(deezerCalls, calls, reason: 'built once, then kept');
    });

    test('once there are plays, the genre charts make way', () async {
      await notifier().refresh();
      final log = ListeningLog();
      for (var i = 0; i < 6; i++) {
        log.add(_play('Song $i', DateTime(2026, 10, 19, 10 + i)));
      }
      taste = TasteProfile.from(log, now: now);
      final mixes = notifier();
      await mixes.refresh(force: true);
      expect(mixes.state.value!.map((p) => p.title), isNot(contains('Pop Right Now')));
    });

    test('built once a day, then opened from what was kept', () async {
      final first = notifier();
      await first.refresh();
      expect(first.state.value!.first.title, 'Top Hits Right Now');
      final callsAfterFirst = deezerCalls;

      final second = notifier();
      await second.refresh();
      expect(deezerCalls, callsAfterFirst, reason: 'same day: no new requests');
      expect(second.state.value!.first.title, 'Top Hits Right Now');

      now = DateTime(2026, 10, 21, 9);
      await notifier().refresh();
      expect(deezerCalls, greaterThan(callsAfterFirst), reason: 'a new day rebuilds');
    });

    test('offline keeps the last mixes and tries again next time', () async {
      await notifier().refresh();
      deezerDown = true;
      now = DateTime(2026, 10, 21, 9);
      final offline = notifier();
      await offline.refresh();
      expect(offline.state.value!.first.title, 'Top Hits Right Now');
      expect(offline.state.value!.map((p) => p.title), contains('Pop Right Now'));

      deezerDown = false;
      final calls = deezerCalls;
      await notifier().refresh();
      expect(deezerCalls, greaterThan(calls));
    });
  });
}
