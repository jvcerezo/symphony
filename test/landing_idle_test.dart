import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/landing/presentation/views/symphony_landing_page.dart';

void main() {
  testWidgets('landing page goes idle (no endless animations)', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: SymphonyLandingPage())));

    // Times out if anything on the page keeps requesting frames.
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
