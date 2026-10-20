import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_audio.dart';

void main() {
  test('download progress alone sends no update; changes people see do', () async {
    final player = FakePlayer();
    final handler = handlerFor(player);
    await handler.playTrack(song('aaaaaaaaaaa'));
    await pumpEventQueue();

    final sent = <PlaybackState>[];
    final sub = handler.playbackState.skip(1).listen(sent.add); // Skips the current one.
    addTearDown(sub.cancel);

    for (var s = 10; s <= 60; s += 10) {
      player.reportBuffered(Duration(seconds: s));
    }
    await pumpEventQueue();
    expect(sent, isEmpty, reason: 'nothing visible changed');

    player.jumpTo(const Duration(seconds: 90));
    await pumpEventQueue();
    expect(sent, hasLength(1), reason: 'a seek moves the position');
    expect(sent.last.updatePosition, const Duration(seconds: 90));

    await handler.pause();
    await pumpEventQueue();
    expect(sent.last.playing, isFalse);
  });
}
