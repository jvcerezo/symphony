import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/core/widgets/startup_splash.dart';

Widget _app({Duration hold = const Duration(milliseconds: 1800)}) => MaterialApp(
      home: StartupSplash(hold: hold, child: const Scaffold(body: Center(child: Text('the app')))),
    );

void main() {
  testWidgets('waves first, then the app', (tester) async {
    await tester.pumpWidget(_app());
    expect(find.text('SYMPHONY'), findsOneWidget);
    expect(find.text('the app'), findsOneWidget, reason: 'built underneath from the start');

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('SYMPHONY'), findsOneWidget, reason: 'still showing');

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('SYMPHONY'), findsNothing);
    expect(find.text('the app'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'the waves stop once gone');
  });

  testWidgets('a tap skips ahead', (tester) async {
    await tester.pumpWidget(_app(hold: const Duration(seconds: 30)));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('SYMPHONY'));
    await tester.pump(); // The fade starts on the next frame.
    await tester.pump(StartupSplash.fade + const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.text('SYMPHONY'), findsNothing);
  });

  testWidgets('with animations turned off the waves hold still', (tester) async {
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: _app(),
    ));
    double progress() => (tester.widget<CustomPaint>(
          find.descendant(of: find.byType(StartupSplash), matching: find.byType(CustomPaint)).first,
        ).painter! as dynamic).progress as double;
    final before = progress();
    await tester.pump(const Duration(milliseconds: 500));
    expect(progress(), before);
  });

  // Saves a frame for a look, when asked (SYMPHONY_SPLASH_PREVIEW=<file>).
  testWidgets('preview frame', (tester) async {
    final out = Platform.environment['SYMPHONY_SPLASH_PREVIEW'];
    if (out == null) return;
    final font = File(r'C:\Windows\Fonts\segoeuib.ttf');
    if (font.existsSync()) {
      await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())))).load();
    }
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: _app(hold: const Duration(seconds: 30))));
    await tester.pump(const Duration(milliseconds: 900));
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      return image.toByteData(format: ui.ImageByteFormat.png);
    });
    File(out).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
