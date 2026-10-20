import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/core/widgets/sized_network_image.dart';

void main() {
  test('decodes at the shown size in pixels, rounded up to share decodes', () {
    expect(SizedNetworkImage.decodeWidth(48, 48, 3), 192); // 144 px
    expect(SizedNetworkImage.decodeWidth(56, 56, 3), 192); // 168 px: the same decode
    expect(SizedNetworkImage.decodeWidth(160, 90, 2), 320);
    expect(SizedNetworkImage.decodeWidth(90, 160, 2), 320, reason: 'the longer side');
    expect(SizedNetworkImage.decodeWidth(double.infinity, 100, 2), 256);
    expect(SizedNetworkImage.decodeWidth(double.infinity, double.infinity, 2), isNull, reason: 'unbounded: whole');
  });

  testWidgets('without a size it takes the space it is laid out in', (tester) async {
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(devicePixelRatio: 2),
      child: Center(child: SizedBox(width: 150, height: 150, child: SizedNetworkImage('https://art.example/a.jpg'))),
    ));
    final image = tester.widget<Image>(find.byType(Image)).image as ResizeImage;
    expect(image.width, 320);
  });
}
