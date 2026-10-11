import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Landing page backdrop: stacked sound-wave ridgelines (in the spirit of a
/// pulsar plot).
///
/// Painted once and only repainted when the viewport size changes: animating
/// dozens of gradient-stroked paths every frame made the page lag in the
/// browser. The ridges sit beside the hero copy on wide screens and below it
/// on narrow ones, fading out toward the text so nothing crosses it.
class WaveBackground extends StatelessWidget {
  const WaveBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: SoundwaveBackgroundPainter(
          progress: 0,
          mouseFactor: const Offset(0.5, 0.5),
          isInteractiveActive: false,
        ),
      ),
    );
  }
}

/// Paints the ridgeline field. Pure function of its inputs.
class SoundwaveBackgroundPainter extends CustomPainter {
  /// Loop position in [0.0, 1.0]; 0.0 and 1.0 render identically.
  final double progress;
  final Offset mouseFactor;
  final bool isInteractiveActive;

  static const background = Color(0xFF0A0A0A);

  /// Same breakpoint the landing page uses for its two-column hero.
  static const wideBreakpoint = 860.0;

  SoundwaveBackgroundPainter({
    required this.progress,
    required this.mouseFactor,
    required this.isInteractiveActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    final wide = w >= wideBreakpoint;
    final field = wide
        // Right of the hero copy, which ends near 60% of the width.
        ? Rect.fromLTRB(w * 0.38, h * 0.10, w + 24, math.max(h * 0.66, h * 0.10 + 360))
        // Below the hero copy and buttons on phones.
        : Rect.fromLTRB(-w * 0.06, h * 0.62, w * 1.06, h * 0.98);

    _drawRidges(
      canvas,
      field,
      lines: wide ? 38 : 22,
      // Opaque toward the right on wide screens; symmetric edge fade on phones.
      fadeStops: wide ? const [0.12, 0.46, 0.9, 1.0] : const [0.0, 0.12, 0.88, 1.0],
      strength: wide ? 1.0 : 0.65,
    );

    _drawVignette(canvas, size);
  }

  void _drawRidges(
    Canvas canvas,
    Rect field, {
    required int lines,
    required List<double> fadeStops,
    required double strength,
  }) {
    final t = progress * 2 * math.pi;
    final spacing = field.height / (lines + 6);
    final maxAmp = spacing * 7.5;
    final peakCenter = 0.56 + (mouseFactor.dx - 0.5) * 0.08;
    final step = math.max(3.0, field.width / 220);

    final fill = Paint()..color = background;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeJoin = StrokeJoin.round;

    // Back (top) to front (bottom): each ridge's fill hides the ones behind.
    for (var i = 0; i < lines; i++) {
      final baseY = field.top + spacing * (i + 6);
      final depth = i / (lines - 1); // 0 = back, 1 = front
      final lineGain = 0.75 + 0.25 * math.sin(i * 1.31 + t);

      final ridge = Path()..moveTo(field.left, baseY);
      for (var x = field.left; x <= field.right + step; x += step) {
        final u = ((x - field.left) / field.width).clamp(0.0, 1.0);
        ridge.lineTo(x, baseY - _ridgeHeight(u, i, t, peakCenter) * maxAmp * lineGain);
      }

      final body = Path.from(ridge)
        ..lineTo(field.right + step, baseY + spacing)
        ..lineTo(field.left, baseY + spacing)
        ..close();
      canvas.drawPath(body, fill);

      final alpha = (0.14 + 0.46 * depth) * strength;
      stroke.shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: alpha),
          Colors.white.withValues(alpha: alpha),
          Colors.white.withValues(alpha: 0),
        ],
        stops: fadeStops,
      ).createShader(Rect.fromLTWH(field.left, baseY - maxAmp, field.width, maxAmp + spacing));
      canvas.drawPath(ridge, stroke);
    }
  }

  /// Normalized ridge height (0..~1.2) at horizontal position [u] for ridge [i].
  double _ridgeHeight(double u, int i, double t, double peakCenter) {
    final d = (u - peakCenter) / 0.17;
    final envelope = math.exp(-d * d);

    final v = 0.45 * math.sin(2 * math.pi * 3 * u + i * 0.91 + t) +
        0.30 * math.sin(2 * math.pi * 7 * u - i * 0.37 - 2 * t) +
        0.17 * math.sin(2 * math.pi * 13 * u + i * 1.73 + 3 * t) +
        0.08 * math.sin(2 * math.pi * 23 * u + i * 2.29 - 4 * t);

    // Sharpen into spiky peaks with flat valleys.
    final spike = math.pow((v + 1) / 2, 2.4).toDouble();
    final grain = 0.035 * (1 + math.sin(2 * math.pi * 31 * u + i * 0.53 + 5 * t));

    return envelope * (0.18 + 1.05 * spike) + grain * (1 - envelope);
  }

  void _drawVignette(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.2, -0.2),
          radius: 1.15,
          colors: [Colors.transparent, background.withValues(alpha: 0.85)],
          stops: const [0.55, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant SoundwaveBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.mouseFactor != mouseFactor ||
        oldDelegate.isInteractiveActive != isInteractiveActive;
  }
}
