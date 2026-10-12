import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/data/services/symphony_audio_handler.dart';
import 'package:symphony/features/audio_player/domain/play_queue.dart';
import 'package:symphony/features/audio_player/presentation/controllers/audio_player_providers.dart';
import 'package:symphony/features/audio_player/presentation/controllers/now_playing_panel_provider.dart';
import 'package:symphony/features/audio_player/presentation/desktop/desktop_shell.dart';
import 'package:symphony/features/audio_player/presentation/widgets/playback_mode_buttons.dart';

void main() {
  late SymphonyAudioHandler handler;

  setUp(() => handler = SymphonyAudioHandler());
  tearDown(() {
    handler.release();
  });

  Future<ProviderContainer> pumpShell(WidgetTester tester, {NowPlayingPanel? panel}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [audioHandlerProvider.overrideWithValue(handler)]);
    addTearDown(container.dispose);
    container.read(nowPlayingPanelProvider.notifier).state = panel;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DesktopShell(content: SizedBox.expand())),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('side panel switches between queue and lyrics and closes', (tester) async {
    final container = await pumpShell(tester, panel: NowPlayingPanel.queue);
    expect(find.text('Your queue is empty'), findsOneWidget);

    await tester.tap(find.text('Lyrics'));
    await tester.pump();
    expect(find.text('Play a song to see its lyrics here.'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(container.read(nowPlayingPanelProvider), isNull);
    expect(find.text('Lyrics'), findsNothing);
  });

  testWidgets('shuffle and repeat buttons drive the player', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioHandlerProvider.overrideWithValue(handler)],
        child: const MaterialApp(home: Scaffold(body: Row(children: [ShuffleButton(), RepeatButton()]))),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Shuffle'));
    await tester.pump();
    expect(handler.isShuffled, isTrue);
    expect(find.byTooltip('Turn off shuffle'), findsOneWidget);

    await tester.tap(find.byTooltip('Repeat'));
    await tester.pump();
    expect(handler.repeatMode, QueueRepeatMode.all);

    await tester.tap(find.byTooltip('Repeat this song'));
    await tester.pump();
    expect(handler.repeatMode, QueueRepeatMode.one);
    expect(handler.playbackState.value.repeatMode, AudioServiceRepeatMode.one);

    await tester.tap(find.byTooltip('Turn off repeat'));
    await tester.pump();
    expect(handler.repeatMode, QueueRepeatMode.off);
  });
}
