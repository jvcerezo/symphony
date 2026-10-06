import 'package:flutter/material.dart';
import '../theme/symphony_theme.dart';

/// Interactive & responsive brand logo for Symphony.
/// Supports asset loading with graceful vector painter fallback and dynamic accent glow.
class SymphonyBrandLogo extends StatelessWidget {
  final double size;
  final double? borderRadius;
  final Color? glowColor;
  final bool showGlow;
  final VoidCallback? onTap;

  const SymphonyBrandLogo({
    super.key,
    this.size = 36.0,
    this.borderRadius,
    this.glowColor,
    this.showGlow = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? (size * 0.26);
    final glow = glowColor ?? const Color(0xFF8B5CF6);

    Widget logoContent = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: glow.withOpacity(0.4),
                  blurRadius: size * 0.45,
                  spreadRadius: 1,
                  offset: const Offset(0, 2),
                ),
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(0.2),
                  blurRadius: size * 0.8,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          'assets/images/symphony_icon_192.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // Elegant Vector CustomPainter fallback if asset not yet bundled
            return CustomPaint(
              size: Size(size, size),
              painter: SymphonyVectorLogoPainter(accentColor: glow),
            );
          },
        ),
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: logoContent,
      );
    }

    return logoContent;
  }
}

/// Scalable CustomPainter rendering Symphony's signature harmonic 'S' soundwave glyph.
class SymphonyVectorLogoPainter extends CustomPainter {
  final Color accentColor;

  const SymphonyVectorLogoPainter({this.accentColor = const Color(0xFF8B5CF6)});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background squircle
    final bgPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0.0, -0.2),
        radius: 0.8,
        colors: [Color(0xFF1E1B2E), Color(0xFF09090D)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(w * 0.26),
    );
    canvas.drawRRect(rrect, bgPaint);

    // Border stroke
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.03
      ..color = const Color(0xFF2E2A45);
    canvas.drawRRect(rrect, borderPaint);

    // Glowing harmonic 'S' ribbon
    final ribbonPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFC084FC),
          accentColor,
          const Color(0xFF6366F1),
          const Color(0xFF06B6D4),
        ],
      ).createShader(Rect.fromLTWH(w * 0.2, h * 0.15, w * 0.6, h * 0.7));

    final path = Path();
    final sx = w / 512.0;
    final sy = h / 512.0;

    // Outer S loop scaled to canvas
    path.moveTo(334 * sx, 168 * sy);
    path.cubicTo(334 * sx, 130 * sy, 298 * sx, 104 * sy, 252 * sx, 104 * sy);
    path.cubicTo(196 * sx, 104 * sy, 162 * sx, 140 * sy, 162 * sx, 186 * sy);
    path.cubicTo(162 * sx, 252 * sy, 344 * sx, 246 * sy, 344 * sx, 326 * sy);
    path.cubicTo(344 * sx, 374 * sy, 304 * sx, 408 * sy, 250 * sx, 408 * sy);
    path.cubicTo(190 * sx, 408 * sy, 154 * sx, 366 * sy, 154 * sy, 324 * sy);
    path.cubicTo(154 * sx, 310 * sy, 166 * sx, 298 * sy, 180 * sx, 298 * sy);
    path.cubicTo(194 * sx, 298 * sy, 204 * sx, 308 * sy, 206 * sx, 322 * sy);
    path.cubicTo(210 * sx, 348 * sy, 226 * sx, 368 * sy, 250 * sx, 368 * sy);
    path.cubicTo(278 * sx, 368 * sy, 298 * sx, 348 * sy, 298 * sx, 326 * sy);
    path.cubicTo(298 * sx, 266 * sy, 116 * sx, 268 * sy, 116 * sx, 186 * sy);
    path.cubicTo(116 * sx, 120 * sy, 172 * sx, 64 * sy, 252 * sx, 64 * sy);
    path.cubicTo(322 * sx, 64 * sy, 378 * sx, 108 * sy, 378 * sx, 168 * sy);
    path.cubicTo(378 * sx, 182 * sy, 368 * sx, 192 * sy, 356 * sx, 192 * sy);
    path.cubicTo(344 * sx, 192 * sy, 334 * sx, 182 * sy, 334 * sx, 168 * sy);
    path.close();

    canvas.drawPath(path, ribbonPaint);
  }

  @override
  bool shouldRepaint(covariant SymphonyVectorLogoPainter oldDelegate) {
    return oldDelegate.accentColor != accentColor;
  }
}

/// Complete brand header with the logo, title, and interactive metadata.
class SymphonyBrandHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final SymphonyAccent accent;
  final VoidCallback? onTap;

  const SymphonyBrandHeader({
    super.key,
    this.title = 'SYMPHONY',
    this.subtitle,
    required this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
        child: Row(
          children: [
            SymphonyBrandLogo(
              size: 34,
              glowColor: accent.primary,
              showGlow: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        title.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: accent.primary.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: accent.primary.withOpacity(0.35),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          'PRO',
                          style: TextStyle(
                            color: accent.primaryLight,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color: accent.primaryLight.withOpacity(0.85),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
