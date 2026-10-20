import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/data/services/symphony_audio_handler.dart';

import 'support/fake_audio.dart';

final _a = song('aaaaaaaaaaa');
final _b = song('bbbbbbbbbbb');

final _shortLoss = AudioInterruptionEvent(true, AudioInterruptionType.pause);
final _lastingLoss = AudioInterruptionEvent(true, AudioInterruptionType.unknown);
final _focusBack = AudioInterruptionEvent(false, AudioInterruptionType.pause);

void main() {
  late FakePlayer player;
  late SymphonyAudioHandler handler;

  setUp(() {
    player = FakePlayer();
    handler = handlerFor(player);
  });

  test('a short loss of the audio pauses, then resumes', () async {
    await handler.playTrack(_a);

    handler.handleInterruption(_shortLoss);
    expect(player.playing, isFalse);

    handler.handleInterruption(_focusBack);
    await pumpEventQueue();
    expect(player.playing, isTrue);
  });

  test('a song the user had paused stays paused when the audio comes back', () async {
    await handler.playTrack(_a);
    await handler.pause();

    handler.handleInterruption(_shortLoss);
    handler.handleInterruption(_focusBack);
    await pumpEventQueue();
    expect(player.playing, isFalse);
  });

  test('pausing during the interruption is kept', () async {
    await handler.playTrack(_a);

    handler.handleInterruption(_shortLoss);
    await handler.pause();
    handler.handleInterruption(_focusBack);
    await pumpEventQueue();
    expect(player.playing, isFalse);
  });

  test('another player taking over pauses for good', () async {
    await handler.playTrack(_a);

    handler.handleInterruption(_lastingLoss);
    handler.handleInterruption(_focusBack);
    await pumpEventQueue();
    expect(player.playing, isFalse);
  });

  test('a song loading when the audio is lost finishes loading and waits for it', () async {
    await handler.playTrack(_a);
    player.gate = Completer<void>();
    final loading = handler.playTrack(_b);
    await pumpEventQueue();

    handler.handleInterruption(_shortLoss);
    player.gate!.complete();
    await loading;
    expect(player.loaded.last, Uri.parse('https://media.example/bbbbbbbbbbb'));
    expect(player.playing, isFalse, reason: 'another app still has the audio');

    handler.handleInterruption(_focusBack);
    await pumpEventQueue();
    expect(player.playing, isTrue);
    expect(handler.mediaItem.value?.id, _b.toMediaItem().id);
  });

  test('the audio coming back mid-load lets the song start when ready', () async {
    await handler.playTrack(_a);
    player.gate = Completer<void>();
    final loading = handler.playTrack(_b);
    await pumpEventQueue();

    handler.handleInterruption(_shortLoss);
    handler.handleInterruption(_focusBack);
    player.gate!.complete();
    await loading;
    expect(player.playing, isTrue);
  });

  test('ducking lowers the volume and restores it', () async {
    await handler.playTrack(_a);

    handler.handleInterruption(AudioInterruptionEvent(true, AudioInterruptionType.duck));
    expect(player.volumeSet, 0.5);
    handler.handleInterruption(AudioInterruptionEvent(false, AudioInterruptionType.duck));
    expect(player.volumeSet, 1.0);
    expect(player.playing, isTrue);
  });
}
