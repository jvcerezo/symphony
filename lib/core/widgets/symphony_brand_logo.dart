import 'package:flutter/material.dart';
import '../theme/symphony_theme.dart';

/// Minimalist, architectural brand logo for Symphony.
/// High contrast, pure geometry, zero neon glow, matching the developer portfolio design language.
class SymphonyBrandLogo extends StatelessWidget {
  final double size;
  final double? borderRadius;
  final VoidCallback? onTap;

  const SymphonyBrandLogo({
    super.key,
    this.size = 36.0,
    this.borderRadius,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? (size * 0.24);

    Widget logoContent = Container(
      width: size,
      height: size,
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
        child: Image.asset(
          'assets/images/symphony_icon_192.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return CustomPaint(
              size: Size(size, size),
              painter: const SymphonyMinimalistPainter(),
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

/// Scalable CustomPainter rendering the minimalist 5-bar architectural soundwave.
class SymphonyMinimalistPainter extends CustomPainter {
  const SymphonyMinimalistPainter();

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
      final barH = heights[i];
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Clean, typography-first minimalist header.
class SymphonyBrandHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final SymphonyAccent? accent;
  final VoidCallback? onTap;

  const SymphonyBrandHeader({
    super.key,
    this.title = 'SYMPHONY',
    this.subtitle,
    this.accent,
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
          ],
        ),
      ),
    );
  }
}
