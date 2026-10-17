import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/core/widgets/motion.dart';

void main() {
  testWidgets('StaggeredEntrance fades items in, later items later', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            StaggeredEntrance(index: 0, child: Text('first')),
            StaggeredEntrance(index: 5, child: Text('sixth')),
          ],
        ),
      ),
    );

    double opacityOf(String text) => tester
        .widget<FadeTransition>(find.ancestor(of: find.text(text), matching: find.byType(FadeTransition)).first)
        .opacity
        .value;

    // Item 0 starts on the next frame; item 5 waits 175 ms.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(opacityOf('first'), greaterThan(0));
    expect(opacityOf('sixth'), 0);

    await tester.pumpAndSettle();
    expect(opacityOf('first'), 1);
    expect(opacityOf('sixth'), 1);
  });

  testWidgets('StaggeredEntrance shows everything at once with reduced motion', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: StaggeredEntrance(index: 3, child: Text('row')),
        ),
      ),
    );
    final fade = tester.widget<FadeTransition>(find.byType(FadeTransition));
    expect(fade.opacity.value, 1);
  });

  testWidgets('PressLift lets taps through to its child', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: PressLift(child: TextButton(onPressed: () => taps++, child: const Text('card'))),
        ),
      ),
    );
    await tester.tap(find.text('card'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('PlayPauseIcon morphs when playback changes', (tester) async {
    Widget icon(bool playing) => MaterialApp(home: PlayPauseIcon(isPlaying: playing));
    await tester.pumpWidget(icon(false));
    expect(tester.widget<AnimatedIcon>(find.byType(AnimatedIcon)).progress.value, 0);

    await tester.pumpWidget(icon(true));
    await tester.pump(const Duration(milliseconds: 100));
    final mid = tester.widget<AnimatedIcon>(find.byType(AnimatedIcon)).progress.value;
    expect(mid, inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedIcon>(find.byType(AnimatedIcon)).progress.value, 1);
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
  });
}
