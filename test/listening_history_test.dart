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

    final taste = TasteProfile.from(ListeningLog(), now: now);

    MadeForYouNotifier notifier() => MadeForYouNotifier(
          builder: MixBuilder(
            catalog: DeezerCatalog(httpClient: MockClient((req) async {
              deezerCalls++;
              if (deezerDown) throw http.ClientException('offline');
              final track = {'id': 1, 'title': 'Hit', 'duration': 200, 'artist': {'id': 9, 'name': 'Star'}, 'album': {}};
              return http.Response(jsonEncode({'data': [track]}), 200);
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
    });

    test('built once a day, then opened from what was kept', () async {
      final first = notifier();
      await first.refresh();
      expect(first.state.value!.map((p) => p.title), ['Top Hits Right Now']);
      final callsAfterFirst = deezerCalls;

      final second = notifier();
      await second.refresh();
      expect(deezerCalls, callsAfterFirst, reason: 'same day: no new requests');
      expect(second.state.value!.single.title, 'Top Hits Right Now');

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
      expect(offline.state.value!.single.title, 'Top Hits Right Now');

      deezerDown = false;
      final calls = deezerCalls;
      await notifier().refresh();
      expect(deezerCalls, greaterThan(calls));
    });
  });
}
