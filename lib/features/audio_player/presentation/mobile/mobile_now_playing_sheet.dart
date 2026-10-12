import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../lyrics/presentation/lyrics_panel.dart';
import '../../domain/entities/track.dart';
import '../controllers/audio_player_providers.dart';
import '../widgets/playback_mode_buttons.dart';
import '../widgets/queue_panel.dart';
import '../widgets/symphony_artwork.dart';

/// Opens the full-screen Now Playing view (from the mini player).
Future<void> showMobileNowPlaying(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: SymphonyTheme.obsidian,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => const FractionallySizedBox(heightFactor: 1, child: MobileNowPlayingSheet()),
  );
}

/// Large artwork, scrubber and full controls, with Lyrics and Queue below.
/// Swipe down (or the chevron) to close.
class MobileNowPlayingSheet extends ConsumerWidget {
  const MobileNowPlayingSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaItem = ref.watch(currentMediaItemStreamProvider).asData?.value;
    final state = ref.watch(playbackStateStreamProvider).asData?.value;
    final handler = ref.read(audioHandlerProvider);

    if (mediaItem == null) {
      return const Center(
        child: Text('Nothing playing', style: TextStyle(color: SymphonyTheme.textSecondary)),
      );
    }

    final isPlaying = state?.playing ?? false;
    final isBuffering = state?.processingState == AudioProcessingState.buffering ||
        state?.processingState == AudioProcessingState.loading;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Close',
                iconSize: 30,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const Expanded(
                child: Text(
                  'Now playing',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const Spacer(),
          LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.maxWidth.clamp(0.0, MediaQuery.sizeOf(context).height * 0.42);
              return SymphonyArtwork(
                artworkUri: mediaItem.artUri,
                track: Track(
                  id: mediaItem.id,
                  title: mediaItem.title,
                  artist: mediaItem.artist ?? '',
                  album: mediaItem.album,
                  artworkUri: mediaItem.artUri,
                ),
                size: size,
                borderRadius: 10,
              );
            },
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mediaItem.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                ),
                const SizedBox(height: 4),
                Text(
                  mediaItem.artist ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: SymphonyTheme.textSecondary, fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<Duration>(
            stream: AudioService.position,
            builder: (context, snapshot) {
              final position = snapshot.data ?? Duration.zero;
              final total = mediaItem.duration ?? Duration.zero;
              final totalMs = total.inMilliseconds.toDouble();
              final posMs = position.inMilliseconds.toDouble().clamp(0.0, totalMs > 0 ? totalMs : 1.0);
              return Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: SymphonyTheme.cardActive,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: posMs,
                      max: totalMs > 0 ? totalMs : 1.0,
                      onChanged: (v) => handler.seek(Duration(milliseconds: v.round())),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_format(position), style: const TextStyle(color: SymphonyTheme.textSecondary, fontSize: 12)),
                        Text(_format(total), style: const TextStyle(color: SymphonyTheme.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const ShuffleButton(iconSize: 24, constraints: BoxConstraints(minWidth: 48, minHeight: 48)),
              IconButton(
                tooltip: 'Previous',
                iconSize: 36,
                icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                onPressed: handler.skipToPrevious,
              ),
              SizedBox(
                width: 68,
                height: 68,
                child: IconButton.filled(
                  tooltip: isPlaying ? 'Pause' : 'Play',
                  style: IconButton.styleFrom(backgroundColor: Colors.white),
                  iconSize: 36,
                  icon: isBuffering
                      ? const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
                        )
                      : Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.black),
                  onPressed: isPlaying ? handler.pause : handler.play,
                ),
              ),
              IconButton(
                tooltip: 'Next',
                iconSize: 36,
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                onPressed: handler.skipToNext,
              ),
              const RepeatButton(iconSize: 24, constraints: BoxConstraints(minWidth: 48, minHeight: 48)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SheetButton(
                  icon: Icons.mic_none_outlined,
                  label: 'Lyrics',
                  onPressed: () => _openPanel(context, 'Lyrics', const LyricsPanel(fontSize: 24)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SheetButton(
                  icon: Icons.queue_music_rounded,
                  label: 'Queue',
                  onPressed: () => _openPanel(context, 'Queue', const QueuePanel()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static void _openPanel(BuildContext context, String title, Widget child) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: SymphonyTheme.panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Builder(
                    builder: (ctx) => IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded, color: SymphonyTheme.textSecondary),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  static String _format(Duration d) {
    final minutes = d.inMinutes.toString();
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _SheetButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _SheetButton({required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: SymphonyTheme.cardActive),
        shape: const StadiumBorder(),
      ),
    );
  }
}
