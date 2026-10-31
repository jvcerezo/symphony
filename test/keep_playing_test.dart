import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/data/services/symphony_audio_handler.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';

import 'support/fake_audio.dart';

final _a = song('aaaaaaaaaaa');
final _b = song('bbbbbbbbbbb');
final _c = song('ccccccccccc');

Uri _uri(String id) => Uri.parse('https://media.example/$id');

/// A song that won't load must not end the music. Reporting it idle (or even
/// paused) on the way to the next song ends Android's playback service, which
/// an app in the background can't start again: the music stopped and its
/// notification went away, about once an hour.
void main() {
  late FakePlayer player;
  late SymphonyAudioHandler handler;
  late List<PlaybackState> states;

  setUp(() {
    player = FakePlayer();
    handler = handlerFor(player);
    handler.autoplay = (_, __) async => const [];
    states = [];
    handler.playbackState.listen(states.add);
  });

  Future<void> finish() async {
    states.clear();
    player.finishSong();
    await pumpEventQueue();
  }

  void expectNeverStopped() {
    expect(states.where((s) => s.processingState == AudioProcessingState.idle), isEmpty);
    expect(states.where((s) => !s.playing), isEmpty);
  }

  test('a song that will not load is passed over without ever reporting stopped', () async {
    player.failing.add(_uri('bbbbbbbbbbb'));
    await handler.playQueue([_a, _b, _c]);
    await finish();

    expect(handler.currentTrack?.id, _c.id);
    expect(player.playing, isTrue);
    expectNeverStopped();
    expect(states.last.processingState, AudioProcessingState.ready);
  });

  test('the last song failing carries on with autoplay', () async {
    final asked = <Track>[];
    handler.autoplay = (last, _) async {
      asked.add(last);
      return [_c];
    };
    player.failing.add(_uri('bbbbbbbbbbb'));
    await handler.playQueue([_a, _b]);
    await finish();

    expect(asked.single.id, _b.id);
    expect(handler.currentTrack?.id, _c.id);
    expect(player.playing, isTrue);
    expectNeverStopped();
  });

  test('the connection dropping while it looks for the next song never reports stopped', () async {
    // Autoplay is slow, as on a weak signal; the player reports the dropped
    // connection meanwhile. That once started a second "move on" that
    // cleared the first one's "still playing", so Android was told the music
    // stopped, then started again from the background, which crashes the app.
    final more = Completer<List<Track>>();
    handler.autoplay = (_, __) => more.future;
    player.failing.add(_uri('bbbbbbbbbbb'));
    await handler.playQueue([_a, _b]);
    await finish();

    player.dropConnection();
    await pumpEventQueue();
    player.reportBuffered(const Duration(seconds: 1));
    await pumpEventQueue();
    more.complete([_c]);
    await pumpEventQueue();

    expect(handler.currentTrack?.id, _c.id);
    expect(player.playing, isTrue);
    expectNeverStopped();
  });

  test('nothing left that plays: stops paused, not idle', () async {
    player.failing.add(_uri('bbbbbbbbbbb'));
    await handler.playQueue([_a, _b]);
    await finish();

    expect(player.playing, isFalse);
    expect(states.last.playing, isFalse);
    expect(states.where((s) => s.processingState == AudioProcessingState.idle), isEmpty);
  });

  test('songs that keep failing stop autoplay instead of looping forever', () async {
    var made = 0;
    var asked = 0;
    handler.autoplay = (_, __) async {
      asked++;
      return [
        for (var i = 0; i < 3; i++) song('f${(made++).toString().padLeft(10, '0')}'),
      ];
    };
    // Every song autoplay finds fails to load, as on a dead connection.
    final loads = player.loaded.length;
    player.failing.addAll([for (var i = 0; i < 100; i++) _uri('f${i.toString().padLeft(10, '0')}')]);
    player.failing.add(_uri('bbbbbbbbbbb'));
    await handler.playQueue([_a, _b]);
    await finish();
    await pumpEventQueue();

    expect(asked, lessThanOrEqualTo(2));
    expect(player.loaded.length - loads, lessThan(12));
    expect(player.playing, isFalse);
    expect(states.where((s) => s.processingState == AudioProcessingState.idle), isEmpty);
  });

  test('a song picked by the user that fails shows an error, not idle', () async {
    player.failing.add(_uri('bbbbbbbbbbb'));
    await expectLater(handler.playTrack(_b), throwsA(anything));
    await pumpEventQueue();

    expect(handler.playbackState.value.processingState, AudioProcessingState.error);
    expect(handler.playbackState.value.playing, isFalse);
  });
}
