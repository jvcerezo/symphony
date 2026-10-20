import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';
import 'package:symphony/features/for_you/data/play_recorder.dart';
import 'package:symphony/features/for_you/domain/play_event.dart';

void main() {
  late StreamController<MediaItem?> items;
  late StreamController<PlaybackState> states;
  late DateTime clock;
  late List<PlayEvent> plays;
  late PlayRecorder recorder;
  Track? current;

  const a = Track(id: 'a', title: 'Song A', artist: 'Artist', artworkUri: null);
  const b = Track(id: 'b', title: 'Song B', artist: 'Artist');

  Future<void> show(Track t) async {
    current = t;
    items.add(t.toMediaItem(actualDuration: const Duration(minutes: 3)));
    await pumpEventQueue();
  }

  Future<void> state(bool playing, [AudioProcessingState s = AudioProcessingState.ready]) async {
    states.add(PlaybackState(playing: playing, processingState: s));
    await pumpEventQueue();
  }

  Future<void> wait(Duration d) async => clock = clock.add(d);

  setUp(() {
    items = StreamController<MediaItem?>();
    states = StreamController<PlaybackState>();
    clock = DateTime(2026, 10, 20, 22);
    plays = [];
    current = null;
    recorder = PlayRecorder(
      mediaItems: items.stream,
      states: states.stream,
      currentTrack: () => current,
      onPlay: plays.add,
      now: () => clock,
    );
  });

  tearDown(() => recorder.dispose());

  test('a song heard to the end, then the next one: one completed play', () async {
    await show(a);
    await state(true);
    await wait(const Duration(minutes: 3));
    await show(b);

    expect(plays, hasLength(1));
    expect(plays.single.title, 'Song A');
    expect(plays.single.outcome, PlayOutcome.completed);
    expect(plays.single.at, DateTime(2026, 10, 20, 22));
  });

  test('paused and loading time are not listening', () async {
    await show(a);
    await state(true, AudioProcessingState.buffering);
    await wait(const Duration(seconds: 20));
    await state(true);
    await wait(const Duration(seconds: 10));
    await state(false);
    await wait(const Duration(minutes: 10));
    await show(b);

    expect(plays.single.listened, const Duration(seconds: 10));
    expect(plays.single.outcome, PlayOutcome.skipped);
  });

  test('flicking past a song in under 2 seconds records nothing', () async {
    await show(a);
    await state(true);
    await wait(const Duration(seconds: 1));
    await show(b);
    expect(plays, isEmpty);
  });

  test('stopping records what was heard', () async {
    await show(a);
    await state(true);
    await wait(const Duration(seconds: 100));
    await state(false, AudioProcessingState.idle);

    expect(plays.single.listened, const Duration(seconds: 100));
    expect(plays.single.outcome, PlayOutcome.partial);
  });
}
