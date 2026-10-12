import 'package:flutter/material.dart';
import '../theme/symphony_theme.dart';

/// Builds [builder] with whether the mouse is over it, shows the hand
/// cursor, and handles taps. Touch devices simply never report a hover.
class HoverBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;
  final MouseCursor cursor;

  const HoverBuilder({
    super.key,
    required this.builder,
    this.onTap,
    this.cursor = SystemMouseCursors.click,
  });

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : widget.cursor,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.builder(context, _hovered),
      ),
    );
  }
}

/// Grows its child slightly under the mouse, like Spotify's play buttons.
class HoverGrow extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  const HoverGrow({super.key, required this.child, this.onTap, this.scale = 1.06});

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      onTap: onTap,
      builder: (context, hovered) => AnimatedScale(
        scale: hovered ? scale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: child,
      ),
    );
  }
}

/// An icon button that brightens under the mouse: [color] at rest,
/// [hoverColor] on hover. An [activeColor] (e.g. shuffle on) stays put.
class HoverIconButton extends StatefulWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback? onPressed;
  final double iconSize;
  final BoxConstraints constraints;
  final Color color;
  final Color hoverColor;
  final Color? activeColor;
  final bool isSelected;

  const HoverIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.iconSize = 18,
    this.constraints = const BoxConstraints(minWidth: 32, minHeight: 32),
    this.color = SymphonyTheme.textSecondary,
    this.hoverColor = SymphonyTheme.textPrimary,
    this.activeColor,
    this.isSelected = false,
  });

  @override
  State<HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<HoverIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.isSelected && widget.activeColor != null;
    final color = active
        ? widget.activeColor!
        : (_hovered && widget.onPressed != null ? widget.hoverColor : widget.color);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: IconButton(
        iconSize: widget.iconSize,
        padding: EdgeInsets.zero,
        constraints: widget.constraints,
        tooltip: widget.tooltip,
        isSelected: widget.isSelected,
        hoverColor: Colors.transparent,
        icon: AnimatedScale(
          scale: _hovered && widget.onPressed != null ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: Icon(widget.icon, color: color),
        ),
        onPressed: widget.onPressed,
      ),
    );
  }
}
