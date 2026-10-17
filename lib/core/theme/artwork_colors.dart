import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The main color of a cover image, toned for the dark UI, or null while it
/// loads or when the image cannot be read. Cached per URL for the session.
final artworkColorProvider = FutureProvider.family<Color?, String>((ref, url) => loadArtworkColor(url));

/// Downloads a tiny copy of the image at [url] and picks its main color.
Future<Color?> loadArtworkColor(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.isScheme('http') && !uri.isScheme('https')) return null;
  try {
    final image = await _resolveSmall(NetworkImage(url));
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data == null ? null : pickArtworkColor(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  } catch (e) {
    developer.log('No artwork color for $url: $e', name: 'ArtworkColors');
    return null;
  }
}

Future<ui.Image> _resolveSmall(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  final stream = ResizeImage(provider, width: 32, height: 32).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) completer.complete(info.image.clone());
      info.dispose();
      stream.removeListener(listener);
    },
    onError: (error, stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

/// Picks the most prominent color from RGBA pixels: the hue family with the
/// most colorful pixels wins (so a small red logo on grey still reads red),
/// then it is darkened and softened enough to sit behind white text.
/// Greyscale images give a neutral grey. Null for an empty image.
@visibleForTesting
Color? pickArtworkColor(Uint8List rgba) {
  const buckets = 12;
  final weight = List<double>.filled(buckets, 0);
  final sumR = List<double>.filled(buckets, 0);
  final sumG = List<double>.filled(buckets, 0);
  final sumB = List<double>.filled(buckets, 0);
  var allR = 0.0, allG = 0.0, allB = 0.0, count = 0;

  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    allR += r;
    allG += g;
    allB += b;
    count++;

    final hsl = HSLColor.fromColor(Color.fromARGB(255, r, g, b));
    if (hsl.saturation < 0.2 || hsl.lightness < 0.12 || hsl.lightness > 0.9) continue;
    // Vivid, mid-light pixels count most.
    final w = hsl.saturation * (1 - (hsl.lightness - 0.5).abs() * 1.4);
    final bucket = (hsl.hue / (360 / buckets)).floor() % buckets;
    weight[bucket] += w;
    sumR[bucket] += r * w;
    sumG[bucket] += g * w;
    sumB[bucket] += b * w;
  }
  if (count == 0) return null;

  var best = 0;
  for (var i = 1; i < buckets; i++) {
    if (weight[i] > weight[best]) best = i;
  }

  final Color picked;
  // Under ~5% colorful coverage the cover is effectively greyscale.
  if (weight[best] < count * 0.05) {
    picked = Color.fromARGB(255, allR ~/ count, allG ~/ count, allB ~/ count);
  } else {
    picked = Color.fromARGB(
      255,
      (sumR[best] / weight[best]).round(),
      (sumG[best] / weight[best]).round(),
      (sumB[best] / weight[best]).round(),
    );
  }
  final hsl = HSLColor.fromColor(picked);
  return hsl
      .withLightness(hsl.lightness.clamp(0.28, 0.46))
      .withSaturation(hsl.saturation.clamp(0.0, 0.72))
      .toColor();
}
