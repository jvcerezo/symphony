import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Architectural animated wave background for Symphony landing page.
/// 
/// Features:
/// - Multi-layered harmonic audio waves with fluid bezier ribbon curves.
/// - Atmospheric ambient top spotlight / radial glow.
/// - Architectural frequency guides & subtle crest energy nodes.
/// - Interactive mouse-following wave modulation on web/desktop.
/// - Ultra-efficient CustomPainter with zero widget rebuild thrash.
class WaveBackground extends StatefulWidget {
  final bool interactive;
  final double speedMultiplier;

  const WaveBackground({
    super.key,
    this.interactive = true,
    this.speedMultiplier = 1.0,
  });

  @override
  State<WaveBackground> createState() => _WaveBackgroundState();
}

class _WaveBackgroundState extends State<WaveBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Offset? _pointerPos;
  Offset _smoothedPointer = const Offset(0.5, 0.5);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerHover(PointerEvent event, Size size) {
    if (!widget.interactive || size.width == 0 || size.height == 0) return;
    final normalized = Offset(
      (event.position.dx / size.width).clamp(0.0, 1.0),
      (event.position.dy / size.height).clamp(0.0, 1.0),
    );
    setState(() {
      _pointerPos = normalized;
    });
  }

  void _onPointerExit(PointerEvent event) {
    setState(() {
      _pointerPos = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return MouseRegion(
          onHover: (e) => _onPointerHover(e, size),
          onExit: _onPointerExit,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                // Smooth pointer interpolation towards target
                final target = _pointerPos ?? const Offset(0.5, 0.5);
                _smoothedPointer = Offset(
                  _smoothedPointer.dx + (target.dx - _smoothedPointer.dx) * 0.05,
                  _smoothedPointer.dy + (target.dy - _smoothedPointer.dy) * 0.05,
                );

                return CustomPaint(
                  size: Size.infinite,
                  painter: WaveBackgroundPainter(
                    progress: _controller.value * widget.speedMultiplier,
                    mouseFactor: _smoothedPointer,
                    isInteractiveActive: _pointerPos != null,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Scalable CustomPainter rendering generative audio waves and architectural lighting.
class WaveBackgroundPainter extends CustomPainter {
  final double progress;
  final Offset mouseFactor;
  final bool isInteractiveActive;

  WaveBackgroundPainter({
    required this.progress,
    required this.mouseFactor,
    required this.isInteractiveActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // 1. Base Dark Canvas
    final baseBgPaint = Paint()..color = const Color(0xFF0A0A0A);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), baseBgPaint);

    // 2. Architectural Ambient Top Spotlight (Hero Radial Light)
    _drawAmbientSpotlight(canvas, size);

    // 3. Subtle Architectural Frequency Guidelines (Muted Audio Grid)
    _drawFrequencyGrid(canvas, size);

    // 4. Layered Harmonic Wave Ribbons
    _drawLayeredWaves(canvas, size);
  }

  void _drawAmbientSpotlight(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Dynamic light anchor slightly reacting to mouse
    final lightCenterX = w * (0.5 + (mouseFactor.dx - 0.5) * 0.1);
    final lightCenterY = math.min(h * 0.22, 280.0);
    final radius = math.max(w * 0.55, 360.0);

    final spotlightPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          const Color(0xFFFFFFFF).withOpacity(0.045),
          const Color(0xFF27272A).withOpacity(0.025),
          const Color(0xFF18181B).withOpacity(0.01),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 0.7, 1.0],
      ).createShader(
        Rect.fromCircle(
          center: Offset(lightCenterX, lightCenterY),
          radius: radius,
        ),
      );

    canvas.drawCircle(Offset(lightCenterX, lightCenterY), radius, spotlightPaint);
  }

  void _drawFrequencyGrid(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final gridPaint = Paint()
      ..color = const Color(0xFF27272A).withOpacity(0.12)
      ..strokeWidth = 1.0;

    // Vertical subtle measurement lines
    const lineCount = 8;
    for (int i = 1; i < lineCount; i++) {
      final x = w * (i / lineCount);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, h * 0.65),
        gridPaint,
      );
    }
  }

  void _drawLayeredWaves(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Base timeline oscillation
    final t = progress * 2.0 * math.pi;

    // Responsive wave center baseline: sits around 48% to 65% of screen height
    final baseY = math.max(h * 0.50, 320.0);

    // Interactive mouse influence on wave amplitude & phase
    final mouseModulation = isInteractiveActive
        ? (math.sin((mouseFactor.dx * 2 - 1) * math.pi) * 16.0)
        : 0.0;
    final mousePitch = isInteractiveActive ? (mouseFactor.dy - 0.5) * 35.0 : 0.0;

    // ==========================================
    // LAYER 1: Deep Atmosphere Wave (Low Freq, Back)
    // ==========================================
    _drawFilledWave(
      canvas: canvas,
      size: size,
      baseY: baseY + 50.0 + mousePitch,
      primaryAmp: 38.0 + mouseModulation * 0.5,
      secondaryAmp: 22.0,
      wavelength1: w * 0.95,
      wavelength2: w * 0.48,
      phase1: t * 0.7,
      phase2: -t * 0.5 + 1.2,
      topColor: const Color(0xFF1A1A1E).withOpacity(0.35),
      bottomColor: const Color(0xFF0A0A0A).withOpacity(0.0),
    );

    // ==========================================
    // LAYER 2: Harmonic Mid-Tone Wave
    // ==========================================
    _drawFilledWave(
      canvas: canvas,
      size: size,
      baseY: baseY + 15.0 + mousePitch * 0.8,
      primaryAmp: 48.0 + mouseModulation * 0.8,
      secondaryAmp: 26.0,
      wavelength1: w * 0.75,
      wavelength2: w * 0.38,
      phase1: -t * 0.9 + 2.0,
      phase2: t * 0.6 + 0.5,
      topColor: const Color(0xFF27272A).withOpacity(0.24),
      bottomColor: Colors.transparent,
    );

    // ==========================================
    // LAYER 3: Kinetic Audio Ribbon (Foreground Glow)
    // ==========================================
    _drawGlowingWaveRibbon(
      canvas: canvas,
      size: size,
      baseY: baseY - 20.0 + mousePitch * 0.6,
      primaryAmp: 56.0 + mouseModulation,
      secondaryAmp: 30.0,
      wavelength1: w * 0.65,
      wavelength2: w * 0.32,
      phase1: t * 1.1 + 0.8,
      phase2: -t * 0.8 + 2.4,
    );

    // ==========================================
    // LAYER 4: Secondary Subtle Counter-Wave Ribbon
    // ==========================================
    _drawAccentWaveRibbon(
      canvas: canvas,
      size: size,
      baseY: baseY - 60.0 + mousePitch * 0.4,
      primaryAmp: 36.0 - mouseModulation * 0.4,
      secondaryAmp: 18.0,
      wavelength1: w * 0.82,
      wavelength2: w * 0.42,
      phase1: -t * 0.75 + 1.5,
      phase2: t * 0.85 + 3.1,
    );
  }

  void _drawFilledWave({
    required Canvas canvas,
    required Size size,
    required double baseY,
    required double primaryAmp,
    required double secondaryAmp,
    required double wavelength1,
    required double wavelength2,
    required double phase1,
    required double phase2,
    required Color topColor,
    required Color bottomColor,
  }) {
    final w = size.width;
    final h = size.height;

    final path = Path();
    path.moveTo(0, h);

    // Generate smooth wave line
    const step = 8.0;
    for (double x = 0; x <= w + step; x += step) {
      final y = baseY +
          primaryAmp * math.sin((x / wavelength1) * 2 * math.pi + phase1) +
          secondaryAmp * math.cos((x / wavelength2) * 2 * math.pi + phase2);

      if (x == 0) {
        path.lineTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    path.lineTo(w, h);
    path.close();

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [topColor, bottomColor],
      ).createShader(Rect.fromLTWH(0, baseY - primaryAmp - secondaryAmp, w, h - baseY + 80));

    canvas.drawPath(path, paint);
  }

  void _drawGlowingWaveRibbon({
    required Canvas canvas,
    required Size size,
    required double baseY,
    required double primaryAmp,
    required double secondaryAmp,
    required double wavelength1,
    required double wavelength2,
    required double phase1,
    required double phase2,
  }) {
    final w = size.width;
    final path = Path();

    const step = 6.0;
    final points = <Offset>[];

    for (double x = 0; x <= w + step; x += step) {
      final y = baseY +
          primaryAmp * math.sin((x / wavelength1) * 2 * math.pi + phase1) +
          secondaryAmp * math.cos((x / wavelength2) * 2 * math.pi + phase2);

      final pt = Offset(x, y);
      points.add(pt);

      if (x == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }

    // Pass 1: Diffuse Soft Ambient Glow
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFFFFFFFF).withOpacity(0.08),
          const Color(0xFFFFFFFF).withOpacity(0.16),
          const Color(0xFFFFFFFF).withOpacity(0.08),
          Colors.transparent,
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, size.height));
    canvas.drawPath(path, glowPaint);

    // Pass 2: Crisp Ultra-Clean White/Zinc Filament
    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFFA1A1AA).withOpacity(0.35),
          Colors.white.withOpacity(0.85),
          const Color(0xFFA1A1AA).withOpacity(0.35),
          Colors.transparent,
        ],
        stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, size.height));
    canvas.drawPath(path, corePaint);

    // Pass 3: Subtle Harmonic Crest Nodes (Sound Energy Beads)
    _drawCrestNodes(canvas, points);
  }

  void _drawAccentWaveRibbon({
    required Canvas canvas,
    required Size size,
    required double baseY,
    required double primaryAmp,
    required double secondaryAmp,
    required double wavelength1,
    required double wavelength2,
    required double phase1,
    required double phase2,
  }) {
    final w = size.width;
    final path = Path();

    const step = 8.0;
    for (double x = 0; x <= w + step; x += step) {
      final y = baseY +
          primaryAmp * math.sin((x / wavelength1) * 2 * math.pi + phase1) +
          secondaryAmp * math.cos((x / wavelength2) * 2 * math.pi + phase2);

      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final accentPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF71717A).withOpacity(0.2),
          const Color(0xFFE4E4E7).withOpacity(0.4),
          const Color(0xFF71717A).withOpacity(0.2),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, size.height));

    canvas.drawPath(path, accentPaint);
  }

  void _drawCrestNodes(Canvas canvas, List<Offset> points) {
    if (points.isEmpty) return;

    final nodePaint = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    final nodeHaloPaint = Paint()
      ..color = Colors.white.withOpacity(0.18)
      ..style = PaintingStyle.fill;

    // Pick 5 harmonic rhythm intervals across the points
    final interval = (points.length / 6).floor();
    for (int i = 1; i <= 5; i++) {
      final index = (i * interval).clamp(0, points.length - 1);
      final pt = points[index];

      // Outer delicate halo
      canvas.drawCircle(pt, 5.0, nodeHaloPaint);
      // Inner bead
      canvas.drawCircle(pt, 1.8, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant WaveBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.mouseFactor != mouseFactor ||
        oldDelegate.isInteractiveActive != isInteractiveActive;
  }
}
