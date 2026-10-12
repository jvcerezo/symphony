import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/layout/breakpoints.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../domain/entities/track.dart';
import '../controllers/audio_player_providers.dart';
import 'symphony_artwork.dart';

/// The play queue: the current song, then what plays next. Tap a song to
/// jump to it, drag to reorder (long-press on phones), or remove it.
class QueuePanel extends ConsumerWidget {
  const QueuePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(currentQueueListStreamProvider).asData?.value ?? const <Track>[];
    final index = ref.watch(currentQueueIndexStreamProvider).asData?.value ?? -1;
    final handler = ref.read(audioHandlerProvider);
    final accent = ref.watch(accentThemeProvider);
    final isMobile = Breakpoints.isMobile(context);

    if (queue.isEmpty || index < 0 || index >= queue.length) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.queue_music_rounded, color: SymphonyTheme.textSecondary, size: 36),
              SizedBox(height: 12),
              Text(
                'Your queue is empty',
                style: TextStyle(color: SymphonyTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 6),
              Text(
                'Play a playlist, or use "Add to queue" on any song.',
                textAlign: TextAlign.center,
                style: TextStyle(color: SymphonyTheme.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final upNext = queue.sublist(index + 1);

    return CustomScrollView(
      slivers: [
        const _SectionTitle('Now playing'),
        SliverToBoxAdapter(
          child: _QueueRow(
            track: queue[index],
            highlight: accent.primary,
            onTap: null,
          ),
        ),
        _SectionTitle(upNext.isEmpty ? 'Nothing up next' : 'Next up · ${upNext.length}'),
        SliverReorderableList(
          itemCount: upNext.length,
          onReorder: (oldIndex, newIndex) {
            if (newIndex > oldIndex) newIndex -= 1;
            handler.moveInQueue(index + 1 + oldIndex, index + 1 + newIndex);
          },
          itemBuilder: (context, i) {
            final absolute = index + 1 + i;
            final row = _QueueRow(
              track: upNext[i],
              onTap: () => handler.skipToQueueItem(absolute),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Remove from queue',
                    icon: const Icon(Icons.close_rounded, size: 18, color: SymphonyTheme.textSecondary),
                    onPressed: () => handler.removeFromQueue(absolute),
                  ),
                  if (!isMobile)
                    ReorderableDragStartListener(
                      index: i,
                      child: const MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(Icons.drag_indicator_rounded, size: 18, color: SymphonyTheme.textMuted),
                        ),
                      ),
                    ),
                ],
              ),
            );
            // Identity keys: the same song can be queued twice.
            final key = ObjectKey(upNext[i]);
            return isMobile
                ? ReorderableDelayedDragStartListener(key: key, index: i, child: row)
                : KeyedSubtree(key: key, child: row);
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(
          text,
          style: const TextStyle(color: SymphonyTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final Track track;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Title color for the current song.
  final Color? highlight;

  const _QueueRow({required this.track, required this.onTap, this.trailing, this.highlight});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              SymphonyArtwork(track: track, artworkUri: track.artworkUri, size: 44, borderRadius: 4, hasGlow: false),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: highlight ?? SymphonyTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: SymphonyTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
