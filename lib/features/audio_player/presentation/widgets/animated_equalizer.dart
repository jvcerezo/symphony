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

    return SizedBox(
      height: widget.height,
      width: 18,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (i) {
          return AnimatedBuilder(
            animation: _animations[i],
            builder: (context, child) {
              return Container(
                width: 3,
                height: widget.height * _animations[i].value,
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
