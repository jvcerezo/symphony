import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/data/services/symphony_audio_handler.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';
import 'package:symphony/features/audio_player/domain/playback_remote.dart';

import 'support/fake_audio.dart';

final _a = song('aaaaaaaaaaa');
final _more = song('ccccccccccc');

class _NoRemote implements PlaybackRemote {
  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

void main() {
  late FakePlayer player;
  late SymphonyAudioHandler handler;
  late List<Track> asked;

  setUp(() {
    player = FakePlayer();
    handler = handlerFor(player);
    asked = [];
    handler.autoplay = (last, queue) async {
      asked.add(last);
      return [_more];
    };
  });

  Future<void> finish() async {
    player.finishSong();
    await pumpEventQueue();
  }

  test('when the queue runs out, similar songs are added and play on', () async {
    await handler.playTrack(_a);
    await finish();

    expect(asked.single.id, _a.id);
    expect(handler.currentQueue.map((t) => t.id), [_a.id, _more.id]);
    expect(handler.currentTrack?.id, _more.id);
    expect(player.playing, isTrue);
  });

  test('skipping past the last song also continues', () async {
    await handler.playTrack(_a);
    await handler.skipToNext();
    expect(handler.currentTrack?.id, _more.id);
  });

  test('not with repeat on, nor in a Jam', () async {
    await handler.playTrack(_a);
    await handler.setRepeatMode(AudioServiceRepeatMode.all);
    await finish();
    expect(asked, isEmpty);

    await handler.setRepeatMode(AudioServiceRepeatMode.none);
    handler.remote = _NoRemote();
    await finish();
    expect(asked, isEmpty);
  });

  test('no songs found: stops at the end as before', () async {
    handler.autoplay = (_, __) async => const [];
    await handler.playTrack(_a);
    await finish();
    expect(handler.currentQueue, hasLength(1));
    expect(player.playing, isFalse);
  });

  test('offline: not asked', () async {
    var online = true;
    handler = handlerFor(player = FakePlayer(), isOnline: () => online);
    handler.autoplay = (last, queue) async {
      asked.add(last);
      return [_more];
    };
    await handler.playTrack(_a);
    online = false;
    await finish();
    expect(asked, isEmpty);
  });
}
