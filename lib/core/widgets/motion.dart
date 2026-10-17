import 'dart:async';

import 'package:flutter/material.dart';

/// Fades and slides [child] up into place, later for higher [index] so a
/// list arrives one item after another. Only the first [maxStaggered] items
/// wait; the rest (and everything when the system asks for reduced motion)
/// appear at once.
class StaggeredEntrance extends StatefulWidget {
  final int index;
  final Widget child;
  final int maxStaggered;

  const StaggeredEntrance({super.key, required this.index, required this.child, this.maxStaggered = 12});

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final Animation<double> _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  Timer? _delay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _controller.isCompleted || _delay != null) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) == true || widget.index >= widget.maxStaggered) {
      _controller.value = 1;
      return;
    }
    _delay = Timer(Duration(milliseconds: 35 * widget.index), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(_curve),
        child: widget.child,
      ),
    );
  }
}

/// A play icon that morphs into pause (and back) instead of swapping.
class PlayPauseIcon extends StatefulWidget {
  final bool isPlaying;
  final double size;
  final Color color;

  const PlayPauseIcon({super.key, required this.isPlaying, this.size = 24, this.color = Colors.black});

  @override
  State<PlayPauseIcon> createState() => _PlayPauseIconState();
}

class _PlayPauseIconState extends State<PlayPauseIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.isPlaying ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant PlayPauseIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      widget.isPlaying ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedIcon(
      icon: AnimatedIcons.play_pause,
      progress: CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      size: widget.size,
      color: widget.color,
      semanticLabel: widget.isPlaying ? 'Pause' : 'Play',
    );
  }
}

/// Lifts [child] with a soft shadow under the mouse and presses it in
/// slightly when touched. It only listens, so taps still reach the child.
class PressLift extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  final double lift;

  const PressLift({super.key, required this.child, this.borderRadius = 8, this.lift = 4});

  @override
  State<PressLift> createState() => _PressLiftState();
}

class _PressLiftState extends State<PressLift> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(0, _hovered && !_pressed ? -widget.lift : 0, 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(_hovered ? 140 : 0),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
