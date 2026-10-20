import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/data/services/offline/local_track_store.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';

import 'support/fake_audio.dart';

/// Records which songs a local copy was started for.
class _Copies extends NoStore {
  final started = <String>{};

  @override
  Future<LocalTrackEntry> save(Track track, Stream<List<int>> bytes,
      {required String format, required Duration duration, required String sourceVideoId, int? expectedBytes}) {
    started.add(track.id);
    return super.save(track, bytes,
        format: format, duration: duration, sourceVideoId: sourceVideoId, expectedBytes: expectedBytes);
  }
}

void main() {
  final songs = [song('aaaaaaaaaaa'), song('bbbbbbbbbbb'), song('ccccccccccc')];

  Future<Set<String>> copiesWhile({required bool metered}) async {
    final copies = _Copies();
    final handler = handlerFor(FakePlayer(), metered: metered, cacheStore: copies);
    await handler.playQueue(songs);
    await pumpEventQueue(times: 50);
    return copies.started;
  }

  test('on Wi-Fi the song playing and the next one are saved to the phone', () async {
    expect(await copiesWhile(metered: false), {'yt_aaaaaaaaaaa', 'yt_bbbbbbbbbbb'});
  });

  test('on mobile data nothing is downloaded beside the stream itself', () async {
    expect(await copiesWhile(metered: true), isEmpty);
  });
}
