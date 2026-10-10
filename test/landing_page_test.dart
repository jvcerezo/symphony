import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony/features/landing/presentation/views/symphony_landing_page.dart';

void main() {
  testWidgets('SymphonyLandingPage renders architectural branding and distribution cards',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SymphonyLandingPage(),
        ),
      ),
    );

    // Verify Brand title & taglines
    expect(find.text('SYMPHONY'), findsAtLeastNWidgets(1));
    expect(find.textContaining('OFFLINE-FIRST'), findsOneWidget);
    expect(find.textContaining('Sound, distilled.'), findsOneWidget);

    // Verify Platform Cards
    expect(find.text('Windows Desktop'), findsOneWidget);
    expect(find.text('Android Mobile'), findsOneWidget);
    // Web demo is off unless built with --dart-define=SYMPHONY_WEB_DEMO=true
    expect(find.text('Web Player Demo'), findsNothing);
    expect(find.textContaining('Web Demo'), findsNothing);

    // Verify Core Capabilities
    expect(find.text('Native Client Resolution'), findsOneWidget);
    expect(find.text('Offline-First Architecture'), findsOneWidget);
    expect(find.text('Tri-Platform Importer'), findsOneWidget);
  });
}
