import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/landing/presentation/widgets/wave_background.dart';
import 'symphony_brand_logo.dart';

/// The phone apps open on the landing page's sound waves, moving, with the
/// logo above, then fade into [child]. [child] is built underneath from
/// the start, so the app is ready when the waves fade. A tap skips ahead.
///
/// Only on Android and iOS (see [shows]); elsewhere it is just [child].
class StartupSplash extends StatefulWidget {
  final Widget child;

  /// How long the waves show before fading.
  final Duration hold;

  const StartupSplash({super.key, required this.child, this.hold = const Duration(milliseconds: 1800)});

  static bool get shows =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static const fade = Duration(milliseconds: 450);

  @override
  State<StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<StartupSplash> with SingleTickerProviderStateMixin {
  /// One loop of the waves; the painter's 0 and 1 look the same.
  late final AnimationController _waves = AnimationController(vsync: this, duration: const Duration(seconds: 7));

  Timer? _holdTimer;
  bool _fading = false;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _holdTimer = Timer(widget.hold, _dismiss);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect "remove animations": still waves.
    if (MediaQuery.disableAnimationsOf(context)) {
      _waves.stop();
    } else if (!_waves.isAnimating && !_gone) {
      _waves.repeat();
    }
  }

  void _dismiss() {
    _holdTimer?.cancel();
    if (!mounted || _fading) return;
    setState(() => _fading = true);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _waves.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_gone)
          AnimatedOpacity(
            opacity: _fading ? 0 : 1,
            duration: StartupSplash.fade,
            curve: Curves.easeOut,
            onEnd: () {
              if (!_fading) return;
              _waves.stop();
              setState(() => _gone = true);
            },
            child: IgnorePointer(
              ignoring: _fading,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismiss,
                child: _SplashBody(waves: _waves),
              ),
            ),
          ),
      ],
    );
  }
}

class _SplashBody extends StatelessWidget {
  final Animation<double> waves;

  const _SplashBody({required this.waves});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: SoundwaveBackgroundPainter.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: waves,
              builder: (context, _) => CustomPaint(
                painter: SoundwaveBackgroundPainter(
                  progress: waves.value,
                  mouseFactor: const Offset(0.5, 0.5),
                  isInteractiveActive: false,
                ),
              ),
            ),
          ),
          // Above the waves, which fill the lower part of a phone screen.
          Align(
            alignment: const Alignment(0, -0.22),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SymphonyBrandLogo(size: 76),
                  SizedBox(height: 18),
                  Text(
                    'SYMPHONY',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
