import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/core/theme/symphony_theme.dart';
import 'package:symphony/core/widgets/hover_widgets.dart';
import 'package:symphony/features/audio_player/data/services/symphony_audio_handler.dart';
import 'package:symphony/features/audio_player/presentation/controllers/audio_player_providers.dart';
import 'package:symphony/features/audio_player/presentation/controllers/navigation_history_provider.dart';
import 'package:symphony/features/audio_player/presentation/desktop/desktop_shell.dart';

Color? _iconColor(WidgetTester tester) => tester.widget<Icon>(find.byIcon(Icons.skip_next)).color;

void main() {
  testWidgets('icon buttons brighten under the mouse', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(child: HoverIconButton(icon: Icons.skip_next, onPressed: () {})),
    ));
    expect(_iconColor(tester), SymphonyTheme.textSecondary);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(HoverIconButton)));
    await tester.pump();
    expect(_iconColor(tester), SymphonyTheme.textPrimary);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(_iconColor(tester), SymphonyTheme.textSecondary);
  });

  testWidgets('mouse back and forward buttons walk navigation history', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handler = SymphonyAudioHandler();
    addTearDown(() {
      handler.release();
    });
    final container = ProviderContainer(overrides: [audioHandlerProvider.overrideWithValue(handler)]);
    addTearDown(container.dispose);
    final history = container.read(navigationHistoryProvider.notifier);
    history.record('home', null);
    history.record('search', null);
    container.read(activeNavTabProvider.notifier).state = 'search';

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DesktopShell(content: SizedBox.expand())),
    ));
    await tester.pump();
    final at = tester.getCenter(find.byType(DesktopShell));

    final back = await tester.startGesture(at, kind: PointerDeviceKind.mouse, buttons: kBackMouseButton);
    await back.up();
    await tester.pump();
    expect(container.read(activeNavTabProvider), 'home');

    final forward = await tester.startGesture(at, kind: PointerDeviceKind.mouse, buttons: kForwardMouseButton);
    await forward.up();
    await tester.pump();
    expect(container.read(activeNavTabProvider), 'search');
  });
}
