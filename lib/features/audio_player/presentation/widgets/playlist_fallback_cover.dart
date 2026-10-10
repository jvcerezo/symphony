import 'package:flutter/material.dart';
import '../../../../core/theme/symphony_theme.dart';

/// Placeholder artwork shown when a playlist has no (or a broken) cover.
class PlaylistFallbackCover extends StatelessWidget {
  const PlaylistFallbackCover({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SymphonyTheme.card,
      child: const Icon(Icons.music_note, color: SymphonyTheme.textMuted, size: 48),
    );
  }
}
