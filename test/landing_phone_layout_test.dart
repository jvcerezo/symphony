import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/landing/presentation/views/symphony_landing_page.dart';

void main() {
  testWidgets('landing page fits a 390px-wide phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: SymphonyLandingPage())));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    final headline = tester.getRect(find.textContaining('A minimalist music player'));
    expect(headline.right, lessThanOrEqualTo(390));
    final card = tester.getRect(find.text('Windows Desktop'));
    expect(card.right, lessThanOrEqualTo(390));
  });
}
