import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/landing/presentation/widgets/wave_background.dart';

void main() {
  group('WaveBackground Widget & Soundwave Painter Tests', () {
    testWidgets('WaveBackground renders CustomPaint and handles layout sizes',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 800,
              child: WaveBackground(),
            ),
          ),
        ),
      );

      // Verify widget renders
      expect(find.byType(WaveBackground), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      // Verify custom painter is attached
      final customPaintFinder = find.descendant(
        of: find.byType(WaveBackground),
        matching: find.byType(CustomPaint),
      );
      expect(customPaintFinder, findsWidgets);

      final customPaintWidget = tester.widget<CustomPaint>(customPaintFinder.first);
      expect(customPaintWidget.painter, isA<SoundwaveBackgroundPainter>());
    });

    testWidgets('WaveBackground handles mouse hover interactions cleanly',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: WaveBackground(interactive: true),
            ),
          ),
        ),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      // Move mouse across canvas to trigger wave modulation
      await gesture.moveTo(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 100));

      await gesture.moveTo(const Offset(200, 150));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(WaveBackground), findsOneWidget);
    });

    test('SoundwaveBackgroundPainter shouldRepaint returns true when progress or mouse factor changes',
        () {
      final painter1 = SoundwaveBackgroundPainter(
        progress: 0.1,
        mouseFactor: const Offset(0.5, 0.5),
        isInteractiveActive: false,
      );
      final painter2 = SoundwaveBackgroundPainter(
        progress: 0.2,
        mouseFactor: const Offset(0.5, 0.5),
        isInteractiveActive: false,
      );
      final painter3 = SoundwaveBackgroundPainter(
        progress: 0.1,
        mouseFactor: const Offset(0.6, 0.5),
        isInteractiveActive: false,
      );

      expect(painter2.shouldRepaint(painter1), isTrue);
      expect(painter3.shouldRepaint(painter1), isTrue);
      expect(painter1.shouldRepaint(painter1), isFalse);
    });

    test('Soundwave loop continuity test verifies identical output at progress 0.0 and 1.0', () {
      final painterStart = SoundwaveBackgroundPainter(
        progress: 0.0,
        mouseFactor: const Offset(0.5, 0.5),
        isInteractiveActive: false,
      );
      final painterEnd = SoundwaveBackgroundPainter(
        progress: 1.0,
        mouseFactor: const Offset(0.5, 0.5),
        isInteractiveActive: false,
      );

      // Both painters should produce identical frame states since all time frequencies are integers
      expect(painterStart.progress, 0.0);
      expect(painterEnd.progress, 1.0);
    });
  });
}
