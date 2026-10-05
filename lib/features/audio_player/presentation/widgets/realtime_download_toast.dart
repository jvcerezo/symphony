import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../controllers/audio_player_providers.dart';
import '../controllers/offline_provider.dart';

class RealtimeDownloadToast extends ConsumerWidget {
  const RealtimeDownloadToast({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offlineState = ref.watch(offlineProvider);
    final progress = offlineState.activeProgress;
    final accent = ref.watch(accentThemeProvider);

    if (progress == null) {
      return const SizedBox.shrink();
    }

    final isDone = progress.isCompleted;
    final isErr = progress.isError;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Material(
          elevation: 12,
          shadowColor: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
          color: const Color(0xFF222222),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDone
                    ? accent.primary.withOpacity(0.8)
                    : (isErr ? Colors.redAccent.withOpacity(0.8) : const Color(0xFF333333)),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isDone ? accent.primary : Colors.black).withOpacity(0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDone
                            ? accent.primary.withOpacity(0.2)
                            : (isErr ? Colors.redAccent.withOpacity(0.2) : Colors.white10),
                      ),
                      child: Center(
                        child: isDone
                            ? Icon(Icons.check_circle_rounded, color: accent.primary, size: 20)
                            : (isErr
                                ? const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20)
                                : SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      value: progress.percentage > 0 ? progress.percentage : null,
                                      color: accent.primary,
                                    ),
                                  )),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isDone
                                ? 'Download Complete!'
                                : (isErr ? 'Download Error' : 'Downloading "${progress.title}"'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isDone
                                ? 'All ${progress.total} songs saved for offline playback'
                                : (isErr
                                    ? (progress.errorMessage ?? 'Failed to download tracks')
                                    : '${progress.current} / ${progress.total} songs downloaded • ${progress.remaining} left'),
                            style: TextStyle(
                              color: isDone ? accent.primary : SymphonyTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: isDone ? FontWeight.w600 : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: SymphonyTheme.textMuted, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => ref.read(offlineProvider.notifier).dismissProgress(),
                    ),
                  ],
                ),
                if (!isDone && !isErr) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress.percentage,
                      minHeight: 4,
                      backgroundColor: const Color(0xFF333333),
                      valueColor: AlwaysStoppedAnimation<Color>(accent.primary),
                    ),
                  ),
                  if (progress.currentTrackTitle != null && progress.currentTrackTitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Saving: "${progress.currentTrackTitle}"',
                      style: const TextStyle(
                        color: SymphonyTheme.textMuted,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
