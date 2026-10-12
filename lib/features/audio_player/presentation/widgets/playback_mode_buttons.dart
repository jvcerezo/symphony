import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/hover_widgets.dart';
import '../controllers/audio_player_providers.dart';

/// Toggles shuffle. Lit in the accent color while on.
class ShuffleButton extends ConsumerWidget {
  final double iconSize;
  final BoxConstraints constraints;

  const ShuffleButton({
    super.key,
    this.iconSize = 18,
    this.constraints = const BoxConstraints(minWidth: 32, minHeight: 32),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackStateStreamProvider).asData?.value;
    final accent = ref.watch(accentThemeProvider);
    final on = (state?.shuffleMode ?? AudioServiceShuffleMode.none) != AudioServiceShuffleMode.none;

    return HoverIconButton(
      iconSize: iconSize,
      constraints: constraints,
      tooltip: on ? 'Turn off shuffle' : 'Shuffle',
      isSelected: on,
      activeColor: accent.primary,
      icon: Icons.shuffle_rounded,
      onPressed: () => ref
          .read(audioHandlerProvider)
          .setShuffleMode(on ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all),
    );
  }
}

/// Cycles repeat: off → whole queue → this song → off.
class RepeatButton extends ConsumerWidget {
  final double iconSize;
  final BoxConstraints constraints;

  const RepeatButton({
    super.key,
    this.iconSize = 18,
    this.constraints = const BoxConstraints(minWidth: 32, minHeight: 32),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playbackStateStreamProvider).asData?.value;
    final accent = ref.watch(accentThemeProvider);
    final mode = state?.repeatMode ?? AudioServiceRepeatMode.none;

    final (next, tooltip) = switch (mode) {
      AudioServiceRepeatMode.none => (AudioServiceRepeatMode.all, 'Repeat'),
      AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => (AudioServiceRepeatMode.one, 'Repeat this song'),
      AudioServiceRepeatMode.one => (AudioServiceRepeatMode.none, 'Turn off repeat'),
    };
    final on = mode != AudioServiceRepeatMode.none;

    return HoverIconButton(
      iconSize: iconSize,
      constraints: constraints,
      tooltip: tooltip,
      isSelected: on,
      activeColor: accent.primary,
      icon: mode == AudioServiceRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
      onPressed: () => ref.read(audioHandlerProvider).setRepeatMode(next),
    );
  }
}
