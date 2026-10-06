import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Architectural soundwave audio visualizer background for Symphony.
/// 
/// Authentically models audio waveforms:
/// - Mirrored audio waveform envelope & vertical spectrum equalizer ribs.
/// - High-precision oscilloscope carrier traces (L & R stereo channels + treble transients).
/// - 0 dB datum audio reference axis with measurement ticks.
/// - Frequency peak energy nodes with drop guidelines.
/// - 100% mathematically flawless infinite loop (strictly integer harmonic multipliers).
/// - Smooth interactive mouse modulation (modulates audio gain/amplitude).
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
    // 8-second cycle for a natural, rhythmic acoustic audio respiration
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
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
                  _smoothedPointer.dx + (target.dx - _smoothedPointer.dx) * 0.06,
                  _smoothedPointer.dy + (target.dy - _smoothedPointer.dy) * 0.06,
                );

                return CustomPaint(
                  size: Size.infinite,
                  painter: SoundwaveBackgroundPainter(
                    progress: _controller.value,
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

/// Scalable CustomPainter rendering authentic oscilloscope sound waves and spectrum fields.
class SoundwaveBackgroundPainter extends CustomPainter {
  /// Progress normalized in [0.0, 1.0]
  final double progress;
  final Offset mouseFactor;
  final bool isInteractiveActive;

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

    // 1. Deep Obsidian Studio Canvas
    final baseBgPaint = Paint()..color = const Color(0xFF0A0A0A);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), baseBgPaint);

    // 2. Sound Pressure Radial Glow (Centered behind hero acoustic epicenter)
    _drawSoundPressureGlow(canvas, size);

    // Timeline angle T = 2 * pi * progress.
    // Every time term in every wave equation is strictly (k * T) where k is an INTEGER.
    // This guarantees mathematical C-infinity seamless looping at progress = 0.0 and 1.0.
    final t = progress * 2.0 * math.pi;

    // Responsive primary soundwave datum baseline (around 38% - 44% of viewport height)
    final primaryY = math.min(math.max(h * 0.40, 260.0), 420.0);

    // Interactive mouse modulation on audio amplitude gain
    final mouseGain = isInteractiveActive
        ? 1.0 + (0.5 - (mouseFactor.dy - 0.5).abs()) * 0.4
        : 1.0;
    final mousePitchShift = isInteractiveActive ? (mouseFactor.dy - 0.5) * 28.0 : 0.0;

    final centerY = primaryY + mousePitchShift;

    // 3. Central 0 dB Datum Reference Line & Acoustic Axis Ticks
    _drawAudioReferenceAxis(canvas, size, centerY);

    // 4. Vertical Audio Equalizer / Waveform Spectrum Field (Soundwave Bars)
    _drawSpectrumWaveBars(canvas, size, centerY, t, mouseGain);

    // 5. Mirrored Soundwave Envelope Fill (Stereo DAW Profile)
    _drawMirroredEnvelopeFill(canvas, size, centerY, t, mouseGain);

    // 6. High-Precision Oscilloscope Audio Ribbon Traces
    _drawOscilloscopeTraces(canvas, size, centerY, t, mouseGain);

    // 7. Secondary Ambient Sub-Bass Wave (Lower Page Depth)
    final secondaryY = math.max(h * 0.78, centerY + 280.0);
    if (secondaryY < h + 100) {
      _drawSubBassWave(canvas, size, secondaryY, t);
    }
  }

  void _drawSoundPressureGlow(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final glowCenterX = w * (0.5 + (mouseFactor.dx - 0.5) * 0.12);
    final glowCenterY = math.min(h * 0.35, 340.0);
    final glowRadius = math.max(w * 0.55, 420.0);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.0,
        colors: [
          const Color(0xFFFFFFFF).withOpacity(0.04),
          const Color(0xFF27272A).withOpacity(0.02),
          const Color(0xFF141416).withOpacity(0.01),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 0.7, 1.0],
      ).createShader(
        Rect.fromCircle(
          center: Offset(glowCenterX, glowCenterY),
          radius: glowRadius,
        ),
      );

    canvas.drawCircle(Offset(glowCenterX, glowCenterY), glowRadius, glowPaint);
  }

  void _drawAudioReferenceAxis(Canvas canvas, Size size, double centerY) {
    final w = size.width;

    // Continuous 0 dB datum hairline with soft horizontal vignette
    final axisPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF27272A).withOpacity(0.25),
          const Color(0xFF71717A).withOpacity(0.4),
          const Color(0xFF27272A).withOpacity(0.25),
          Colors.transparent,
        ],
        stops: const [0.0, 0.15, 0.5, 0.85, 1.0],
      ).createShader(Rect.fromLTWH(0, centerY, w, 1));

    canvas.drawLine(Offset(0, centerY), Offset(w, centerY), axisPaint);

    // Audio frequency division tick marks along datum axis
    final tickPaint = Paint()
      ..color = const Color(0xFF3F3F46).withOpacity(0.25)
      ..strokeWidth = 1.0;

    const divisions = 16;
    for (int i = 1; i < divisions; i++) {
      final x = w * (i / divisions);
      canvas.drawLine(Offset(x, centerY - 4), Offset(x, centerY + 4), tickPaint);
    }
  }

  /// Evaluates the audio wave amplitude at horizontal normalized coordinate u in [0.0, 1.0].
  /// Every time term is strictly an integer multiplier of t (t = 2 * pi * progress).
  double _calculateAudioAmplitude(double u, double t, double mouseGain) {
    // Spatial acoustic envelope: tapers smoothly at left and right viewport edges
    final edgeWindow = math.sin(u * math.pi); // 0 at edges, 1 at center
    final envelope = edgeWindow * (0.65 + 0.35 * math.sin(2.0 * math.pi * 2.0 * u - 1.0 * t));

    // Acoustic harmonics:
    // Fundamental (2 cycles, speed 1)
    final h1 = math.sin(2.0 * math.pi * 2.0 * u + 1.0 * t);
    // Mid harmonic (5 cycles, speed -2)
    final h2 = 0.50 * math.sin(2.0 * math.pi * 5.0 * u - 2.0 * t + 1.2);
    // Treble acoustic transient (12 cycles, speed 3)
    final h3 = 0.28 * math.sin(2.0 * math.pi * 12.0 * u + 3.0 * t + 2.4);
    // Acoustic micro-flutter (24 cycles, speed -4)
    final h4 = 0.12 * math.sin(2.0 * math.pi * 24.0 * u - 4.0 * t + 0.8);

    final rawSignal = h1 + h2 + h3 + h4;
    return rawSignal * envelope * mouseGain;
  }

  void _drawSpectrumWaveBars(
    Canvas canvas,
    Size size,
    double centerY,
    double t,
    double mouseGain,
  ) {
    final w = size.width;
    const barSpacing = 7.0;
    const barWidth = 2.0;
    final barCount = (w / barSpacing).floor();

    final barPaint = Paint()
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final maxBarHeight = math.min(size.height * 0.18, 95.0);

    for (int i = 0; i <= barCount; i++) {
      final x = i * barSpacing;
      final u = (x / w).clamp(0.0, 1.0);

      final signal = _calculateAudioAmplitude(u, t, mouseGain);
      final rawHeight = (signal.abs() * maxBarHeight).clamp(2.0, maxBarHeight);

      // Gradient color: peak is crisp light zinc, baseline fades to dark
      final alpha = (0.05 + 0.22 * (rawHeight / maxBarHeight)).clamp(0.0, 1.0);
      barPaint.color = Colors.white.withOpacity(alpha);

      // Draw vertical audio bar symmetrically across datum axis
      final top = centerY - rawHeight;
      final bottom = centerY + rawHeight;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(x - barWidth / 2, top, x + barWidth / 2, bottom),
        const Radius.circular(1.0),
      );
      canvas.drawRRect(rect, barPaint);
    }
  }

  void _drawMirroredEnvelopeFill(
    Canvas canvas,
    Size size,
    double centerY,
    double t,
    double mouseGain,
  ) {
    final w = size.width;
    final maxAmp = math.min(size.height * 0.20, 105.0);

    final topPath = Path();
    final bottomPath = Path();

    topPath.moveTo(0, centerY);
    bottomPath.moveTo(0, centerY);

    const step = 6.0;
    for (double x = 0; x <= w + step; x += step) {
      final u = (x / w).clamp(0.0, 1.0);
      final signal = _calculateAudioAmplitude(u, t, mouseGain);
      final amp = signal.abs() * maxAmp;

      topPath.lineTo(x, centerY - amp);
      bottomPath.lineTo(x, centerY + amp);
    }

    topPath.lineTo(w, centerY);
    bottomPath.lineTo(w, centerY);

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF27272A).withOpacity(0.08),
          Colors.transparent,
          const Color(0xFF27272A).withOpacity(0.08),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, centerY - maxAmp, w, maxAmp * 2));

    canvas.drawPath(topPath, fillPaint);
    canvas.drawPath(bottomPath, fillPaint);
  }

  void _drawOscilloscopeTraces(
    Canvas canvas,
    Size size,
    double centerY,
    double t,
    double mouseGain,
  ) {
    final w = size.width;
    final maxAmp = math.min(size.height * 0.19, 100.0);

    final mainPath = Path();
    final stereoPath = Path();
    final transientPath = Path();

    const step = 4.0;
    final crestPoints = <Offset>[];

    for (double x = 0; x <= w + step; x += step) {
      final u = (x / w).clamp(0.0, 1.0);
      final edgeWindow = math.sin(u * math.pi);

      // --- TRACE 1: Main Audio Carrier Wave (Lead Left Channel) ---
      final sig1 = _calculateAudioAmplitude(u, t, mouseGain);
      final y1 = centerY - (sig1 * maxAmp);

      // --- TRACE 2: Stereo Phase-Shifted Track (Right Channel) ---
      // Strictly integer time multipliers (t * -1, t * 2, t * -3)
      final sig2 = edgeWindow *
          (math.sin(2.0 * math.pi * 3.0 * u - 1.0 * t + 0.9) +
              0.45 * math.sin(2.0 * math.pi * 7.0 * u + 2.0 * t + 1.8) +
              0.20 * math.sin(2.0 * math.pi * 16.0 * u - 3.0 * t));
      final y2 = centerY + (sig2 * maxAmp * 0.75 * mouseGain);

      // --- TRACE 3: Treble Acoustic Flutter (High frequency vibration) ---
      // Strictly integer time multipliers (t * 2, t * -4)
      final sig3 = edgeWindow *
          (0.6 * math.sin(2.0 * math.pi * 6.0 * u + 2.0 * t) +
              0.4 * math.sin(2.0 * math.pi * 18.0 * u - 4.0 * t + 1.5));
      final y3 = centerY - (sig3 * maxAmp * 0.5 * mouseGain);

      if (x == 0) {
        mainPath.moveTo(x, y1);
        stereoPath.moveTo(x, y2);
        transientPath.moveTo(x, y3);
      } else {
        mainPath.lineTo(x, y1);
        stereoPath.lineTo(x, y2);
        transientPath.lineTo(x, y3);
      }

      // Collect sample points for acoustic crest peak nodes
      if (x % (w / 7).floor() < step && u > 0.1 && u < 0.9) {
        crestPoints.add(Offset(x, y1));
      }
    }

    // 1. Trace 1 Glow pass (Soft Phosphor Bloom)
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.8
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFFFFFFFF).withOpacity(0.08),
          const Color(0xFFFFFFFF).withOpacity(0.20),
          const Color(0xFFFFFFFF).withOpacity(0.08),
          Colors.transparent,
        ],
        stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, size.height));
    canvas.drawPath(mainPath, glowPaint);

    // 2. Trace 1 Sharp Core Filament (Solid White Oscilloscope Wire)
    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFFA1A1AA).withOpacity(0.4),
          Colors.white.withOpacity(0.95),
          const Color(0xFFA1A1AA).withOpacity(0.4),
          Colors.transparent,
        ],
        stops: const [0.0, 0.15, 0.5, 0.85, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, size.height));
    canvas.drawPath(mainPath, corePaint);

    // 3. Trace 2 Stereo Track (Subtle Slate Wire)
    final stereoPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF71717A).withOpacity(0.15),
          const Color(0xFFA1A1AA).withOpacity(0.45),
          const Color(0xFF71717A).withOpacity(0.15),
          Colors.transparent,
        ],
        stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, size.height));
    canvas.drawPath(stereoPath, stereoPaint);

    // 4. Trace 3 Treble Jitter Wire
    final transientPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF52525B).withOpacity(0.2),
          const Color(0xFFE4E4E7).withOpacity(0.35),
          const Color(0xFF52525B).withOpacity(0.2),
          Colors.transparent,
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, size.height));
    canvas.drawPath(transientPath, transientPaint);

    // 5. Acoustic Crest Peak Nodes & Vertical Measurement Drop-Lines
    _drawCrestNodes(canvas, crestPoints, centerY);
  }

  void _drawCrestNodes(Canvas canvas, List<Offset> points, double centerY) {
    if (points.isEmpty) return;

    final dropLinePaint = Paint()
      ..color = const Color(0xFF71717A).withOpacity(0.25)
      ..strokeWidth = 1.0;

    final haloPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    final coreNodePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (final pt in points) {
      // Hairline drop-line to 0 dB datum axis
      canvas.drawLine(pt, Offset(pt.dx, centerY), dropLinePaint);

      // Glowing peak bead
      canvas.drawCircle(pt, 4.5, haloPaint);
      canvas.drawCircle(pt, 1.6, coreNodePaint);
    }
  }

  void _drawSubBassWave(Canvas canvas, Size size, double subY, double t) {
    final w = size.width;
    final path = Path();
    const amp = 26.0;

    const step = 8.0;
    for (double x = 0; x <= w + step; x += step) {
      final u = (x / w).clamp(0.0, 1.0);
      final edge = math.sin(u * math.pi);

      // Low frequency sub-bass harmonic (strictly integer 1 and -2 multipliers)
      final wave = edge *
          (math.sin(2.0 * math.pi * 1.5 * u + 1.0 * t) +
              0.5 * math.sin(2.0 * math.pi * 3.0 * u - 2.0 * t + 1.0));
      final y = subY + (wave * amp);

      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final subPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF27272A).withOpacity(0.2),
          const Color(0xFF71717A).withOpacity(0.35),
          const Color(0xFF27272A).withOpacity(0.2),
          Colors.transparent,
        ],
        stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
      ).createShader(Rect.fromLTWH(0, subY - amp, w, amp * 2));

    canvas.drawPath(path, subPaint);
  }

  @override
  bool shouldRepaint(covariant SoundwaveBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.mouseFactor != mouseFactor ||
        oldDelegate.isInteractiveActive != isInteractiveActive;
  }
}
