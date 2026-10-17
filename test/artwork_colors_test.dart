import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/core/theme/artwork_colors.dart';

/// RGBA pixels: [count] copies of each color in [colors].
Uint8List pixels(Map<Color, int> colors) {
  final bytes = <int>[];
  colors.forEach((color, count) {
    for (var i = 0; i < count; i++) {
      bytes.addAll([
        (color.r * 255).round(),
        (color.g * 255).round(),
        (color.b * 255).round(),
        255,
      ]);
    }
  });
  return Uint8List.fromList(bytes);
}

double hueOf(Color c) => HSLColor.fromColor(c).hue;

void main() {
  group('pickArtworkColor', () {
    test('a red cover gives a red tint', () {
      final color = pickArtworkColor(pixels({const Color(0xFFE53935): 100}))!;
      expect(hueOf(color), anyOf(lessThan(20), greaterThan(340)));
    });

    test('a small colorful area beats a large grey one', () {
      final color = pickArtworkColor(pixels({
        const Color(0xFF808080): 85,
        const Color(0xFF1E88E5): 15,
      }))!;
      expect(hueOf(color), inInclusiveRange(190, 230));
    });

    test('the largest hue family wins between two colors', () {
      final color = pickArtworkColor(pixels({
        const Color(0xFF43A047): 60,
        const Color(0xFF8E24AA): 30,
      }))!;
      expect(hueOf(color), inInclusiveRange(100, 140));
    });

    test('is toned for white text: never too light or too dark', () {
      for (final c in [const Color(0xFFFFF59D), const Color(0xFF0D0D40), const Color(0xFFFFFFFF), const Color(0xFF000000)]) {
        final l = HSLColor.fromColor(pickArtworkColor(pixels({c: 50}))!).lightness;
        expect(l, inInclusiveRange(0.27, 0.47), reason: '$c');
      }
    });

    test('a greyscale cover gives a neutral grey', () {
      final color = pickArtworkColor(pixels({const Color(0xFF303030): 50, const Color(0xFFB0B0B0): 50}))!;
      expect(HSLColor.fromColor(color).saturation, lessThan(0.05));
    });

    test('transparent or empty images give nothing', () {
      expect(pickArtworkColor(Uint8List(0)), isNull);
      expect(pickArtworkColor(Uint8List.fromList([255, 0, 0, 0])), isNull);
    });
  });
}
