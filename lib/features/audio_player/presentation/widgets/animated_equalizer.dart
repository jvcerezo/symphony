import 'package:flutter/material.dart';
import '../../../../core/theme/symphony_theme.dart';

class AnimatedEqualizer extends StatefulWidget {
  final bool isPlaying;
  final double height;
  final Color? color;

  const AnimatedEqualizer({
    super.key,
    required this.isPlaying,
    this.height = 16.0,
    this.color,
  });

  @override
  State<AnimatedEqualizer> createState() => _AnimatedEqualizerState();
}

class _AnimatedEqualizerState extends State<AnimatedEqualizer> with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  static const _durations = [450, 650, 520, 700];

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(4, (i) {
      return AnimationController(
        vsync: this,
        duration: Duration(milliseconds: _durations[i]),
      );
    });

    _animations = _controllers.map((controller) {
      return Tween<double>(begin: 0.2, end: 1.0).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
    }).toList();

    if (widget.isPlaying) {
      _startAnimating();
    }
  }

  void _startAnimating() {
    for (final controller in _controllers) {
      controller.repeat(reverse: true);
    }
  }

  void _stopAnimating() {
    for (final controller in _controllers) {
      controller.animateTo(0.2, duration: const Duration(milliseconds: 250));
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _startAnimating();
      } else {
        _stopAnimating();
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barColor = widget.color ?? SymphonyTheme.primaryLight;

    // Painted straight from the animations: each frame repaints these few
    // pixels only, with no rebuild or layout.
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(18, widget.height),
        painter: _BarsPainter(_animations, barColor),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<Animation<double>> bars;
  final Color color;

  _BarsPainter(this.bars, this.color) : super(repaint: Listenable.merge(bars));

  static const _barWidth = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final gap = (size.width - _barWidth * bars.length) / (bars.length - 1);
    for (var i = 0; i < bars.length; i++) {
      final h = size.height * bars[i].value;
      final left = i * (_barWidth + gap);
      canvas.drawRRect(
        RRect.fromLTRBR(left, size.height - h, left + _barWidth, size.height, const Radius.circular(2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.color != color || old.bars != bars;
}
