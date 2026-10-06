import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/symphony_theme.dart';

/// Minimalist, architectural brand logo for Symphony.
/// High contrast, pure geometry, zero neon glow, matching the developer portfolio design language.
/// Supports smooth harmonic soundwave animation during loading and playback.
class SymphonyBrandLogo extends StatefulWidget {
  final double size;
  final double? borderRadius;
  final VoidCallback? onTap;
  final bool animated;

  const SymphonyBrandLogo({
    super.key,
    this.size = 36.0,
    this.borderRadius,
    this.onTap,
    this.animated = true,
  });

  @override
  State<SymphonyBrandLogo> createState() => _SymphonyBrandLogoState();
}

class _SymphonyBrandLogoState extends State<SymphonyBrandLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.animated) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant SymphonyBrandLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated != oldWidget.animated) {
      if (widget.animated) {
        _controller.repeat();
      } else {
        _controller.stop();
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? (widget.size * 0.24);

    Widget logoContent = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: const Color(0xFF26262A),
          width: 1.0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: widget.animated
            ? AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return CustomPaint(
                    size: Size(widget.size, widget.size),
                    painter: SymphonyMinimalistPainter(progress: _controller.value),
                  );
                },
              )
            : CustomPaint(
                size: Size(widget.size, widget.size),
                painter: const SymphonyMinimalistPainter(progress: 0.0),
              ),
      ),
    );

    if (widget.onTap != null) {
      return InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(radius),
        child: logoContent,
      );
    }

    return logoContent;
  }
}

/// Scalable CustomPainter rendering the minimalist 5-bar architectural soundwave.
class SymphonyMinimalistPainter extends CustomPainter {
  final double progress;

  const SymphonyMinimalistPainter({this.progress = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Solid obsidian background
    final bgPaint = Paint()..color = const Color(0xFF0A0A0A);
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(w * 0.24),
    );
    canvas.drawRRect(rrect, bgPaint);

    // Border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xFF26262A);
    canvas.drawRRect(rrect, borderPaint);

    // Pure white soundwave bars
    final barPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;

    final barW = w * (34.0 / 512.0);
    final gap = w * (26.0 / 512.0);
    final totalW = (5 * barW) + (4 * gap);
    final startX = (w - totalW) / 2.0;
    final heights = [
      h * (96.0 / 512.0),
      h * (180.0 / 512.0),
      h * (276.0 / 512.0),
      h * (180.0 / 512.0),
      h * (96.0 / 512.0),
    ];

    for (int i = 0; i < 5; i++) {
      double scale = 1.0;
      if (progress > 0.0) {
        // Continuous harmonic wave oscillation across bars
        final phase = (i / 5.0) * 2.0 * math.pi;
        final wave = (math.sin(progress * 2.0 * math.pi - phase) + 1.0) / 2.0;
        scale = 0.32 + (0.68 * wave);
      }
      final barH = heights[i] * scale;
      final x = startX + (i * (barW + gap));
      final y = (h - barH) / 2.0;
      final barRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barW, barH),
        Radius.circular(barW / 2.0),
      );
      canvas.drawRRect(barRRect, barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant SymphonyMinimalistPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Clean, typography-first minimalist header.
class SymphonyBrandHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final SymphonyAccent? accent;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SymphonyBrandHeader({
    super.key,
    this.title = 'SYMPHONY',
    this.subtitle,
    this.accent,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
        child: Row(
          children: [
            const SymphonyBrandLogo(size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.0,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFA1A1AA),
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
