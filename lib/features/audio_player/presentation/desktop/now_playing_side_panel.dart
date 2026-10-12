import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../lyrics/presentation/lyrics_panel.dart';
import '../controllers/now_playing_panel_provider.dart';
import '../widgets/queue_panel.dart';

/// Right-hand panel on wide windows showing the queue or lyrics, opened
/// from the player bar.
class NowPlayingSidePanel extends ConsumerWidget {
  final NowPlayingPanel panel;

  const NowPlayingSidePanel({super.key, required this.panel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(nowPlayingPanelProvider.notifier);

    Widget tab(String label, NowPlayingPanel value) {
      final selected = panel == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => notifier.state = value,
          labelStyle: TextStyle(
            color: selected ? Colors.black : SymphonyTheme.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          selectedColor: SymphonyTheme.textPrimary,
          backgroundColor: SymphonyTheme.cardHover,
          side: BorderSide.none,
          shape: const StadiumBorder(),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 340,
        color: SymphonyTheme.panel,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
              child: Row(
                children: [
                  tab('Queue', NowPlayingPanel.queue),
                  tab('Lyrics', NowPlayingPanel.lyrics),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded, size: 20, color: SymphonyTheme.textSecondary),
                    onPressed: () => notifier.state = null,
                  ),
                ],
              ),
            ),
            Expanded(
              child: panel == NowPlayingPanel.queue ? const QueuePanel() : const LyricsPanel(),
            ),
          ],
        ),
      ),
    );
  }
}
