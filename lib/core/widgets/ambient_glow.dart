import 'package:flutter/material.dart';
import '../theme/symphony_theme.dart';

/// A soft wash of [tint] over the black canvas, glowing from the bottom-left
/// and fading in from the top-right. Cross-fades when [tint] changes; plain
/// black when it is null.
class AmbientGlow extends StatelessWidget {
  final Color? tint;
  final double strength;

  const AmbientGlow({super.key, required this.tint, this.strength = 0.8});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: tint ?? SymphonyTheme.obsidian),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      builder: (context, color, _) {
        final c = color ?? SymphonyTheme.obsidian;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: SymphonyTheme.obsidian,
            gradient: RadialGradient(
              center: const Alignment(-0.9, 1.1),
              radius: 1.4,
              colors: [c.withValues(alpha: strength), SymphonyTheme.obsidian.withValues(alpha: 0)],
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(1.1, -1),
                radius: 1.2,
                colors: [c.withValues(alpha: strength * 0.45), SymphonyTheme.obsidian.withValues(alpha: 0)],
              ),
            ),
          ),
        );
      },
    );
  }
}
