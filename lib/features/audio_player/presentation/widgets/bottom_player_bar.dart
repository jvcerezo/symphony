import 'dart:ui';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../controllers/audio_player_providers.dart';

class BottomPlayerBar extends ConsumerStatefulWidget {
  const BottomPlayerBar({super.key});

  @override
  ConsumerState<BottomPlayerBar> createState() => _BottomPlayerBarState();
}

class _BottomPlayerBarState extends ConsumerState<BottomPlayerBar> {
  double _volume = 1.0;
  bool _isMuted = false;
  bool _isLiked = false;

  @override
  Widget build(BuildContext context) {
    final mediaItemAsync = ref.watch(currentMediaItemStreamProvider);
    final playbackStateAsync = ref.watch(playbackStateStreamProvider);

    final mediaItem = mediaItemAsync.asData?.value;
    final playbackState = playbackStateAsync.asData?.value;
    final isPlaying = playbackState?.playing ?? false;
    final isBuffering = playbackState?.processingState == AudioProcessingState.buffering ||
        playbackState?.processingState == AudioProcessingState.loading;

    if (mediaItem == null) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: isMobile ? 76 : 90,
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 8),
          decoration: BoxDecoration(
            color: SymphonyTheme.midnight.withAlpha(235),
            border: const Border(
              top: BorderSide(color: SymphonyTheme.divider, width: 1),
            ),
          ),
          child: isMobile
              ? _buildMobileLayout(mediaItem, isPlaying, isBuffering)
              : _buildDesktopLayout(mediaItem, isPlaying, isBuffering),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(MediaItem mediaItem, bool isPlaying, bool isBuffering) {
    final handler = ref.read(audioHandlerProvider);

    return Row(
      children: [
        // Left Column: Artwork + Metadata
        Expanded(
          flex: 3,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: mediaItem.artUri != null
                    ? Image.network(
                        mediaItem.artUri.toString(),
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _buildFallbackArt(),
                      )
                    : _buildFallbackArt(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mediaItem.title,
                      style: const TextStyle(
                        color: SymphonyTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      mediaItem.artist ?? '',
                      style: const TextStyle(
                        color: SymphonyTheme.textSecondary,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                iconSize: 20,
                icon: Icon(
                  _isLiked ? Icons.favorite : Icons.favorite_border,
                  color: _isLiked ? SymphonyTheme.primaryLight : SymphonyTheme.textMuted,
                ),
                onPressed: () => setState(() => _isLiked = !_isLiked),
              ),
            ],
          ),
        ),

        // Center Column: Player Controls + Scrubber
        Expanded(
          flex: 6,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Control Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 20,
                    icon: const Icon(Icons.shuffle, color: SymphonyTheme.textMuted),
                    onPressed: () {},
                  ),
                  IconButton(
                    iconSize: 24,
                    icon: const Icon(Icons.skip_previous, color: Colors.white),
                    onPressed: () => handler.skipToPrevious(),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SymphonyTheme.brandGradient,
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 22,
                      icon: isBuffering
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                            ),
                      onPressed: () {
                        if (isPlaying) {
                          handler.pause();
                        } else {
                          handler.play();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    iconSize: 24,
                    icon: const Icon(Icons.skip_next, color: Colors.white),
                    onPressed: () => handler.skipToNext(),
                  ),
                  IconButton(
                    iconSize: 20,
                    icon: const Icon(Icons.repeat, color: SymphonyTheme.textMuted),
                    onPressed: () {},
                  ),
                ],
              ),

              // Scrubber Line
              StreamBuilder<Duration>(
                stream: AudioService.position,
                builder: (context, snapshot) {
                  final position = snapshot.data ?? Duration.zero;
                  final total = mediaItem.duration ?? Duration.zero;
                  final totalMs = total.inMilliseconds.toDouble();
                  final posMs =
                      position.inMilliseconds.toDouble().clamp(0.0, totalMs > 0 ? totalMs : 1.0);

                  return Row(
                    children: [
                      Text(
                        _formatDuration(position),
                        style: const TextStyle(fontSize: 11, color: SymphonyTheme.textMuted),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3.0,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.0),
                          ),
                          child: Slider(
                            value: posMs,
                            max: totalMs > 0 ? totalMs : 1.0,
                            activeColor: SymphonyTheme.primaryLight,
                            inactiveColor: SymphonyTheme.divider,
                            onChanged: (val) {
                              handler.seek(Duration(milliseconds: val.round()));
                            },
                          ),
                        ),
                      ),
                      Text(
                        _formatDuration(total),
                        style: const TextStyle(fontSize: 11, color: SymphonyTheme.textMuted),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),

        // Right Column: Quality Badge + Volume Controls
        Expanded(
          flex: 3,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: SymphonyTheme.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SymphonyTheme.divider),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt, size: 13, color: SymphonyTheme.secondary),
                    SizedBox(width: 3),
                    Text(
                      'HD STREAM',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: SymphonyTheme.secondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                iconSize: 20,
                icon: Icon(
                  _isMuted || _volume == 0 ? Icons.volume_off : Icons.volume_up,
                  color: SymphonyTheme.textSecondary,
                ),
                onPressed: () {
                  setState(() {
                    _isMuted = !_isMuted;
                    handler.setVolume(_isMuted ? 0.0 : _volume);
                  });
                },
              ),
              SizedBox(
                width: 90,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3.0,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.0),
                  ),
                  child: Slider(
                    value: _isMuted ? 0.0 : _volume,
                    min: 0.0,
                    max: 1.0,
                    activeColor: Colors.white,
                    inactiveColor: SymphonyTheme.divider,
                    onChanged: (val) {
                      setState(() {
                        _volume = val;
                        _isMuted = false;
                      });
                      handler.setVolume(val);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(MediaItem mediaItem, bool isPlaying, bool isBuffering) {
    final handler = ref.read(audioHandlerProvider);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: mediaItem.artUri != null
                  ? Image.network(
                      mediaItem.artUri.toString(),
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _buildFallbackArt(),
                    )
                  : _buildFallbackArt(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    mediaItem.title,
                    style: const TextStyle(
                      color: SymphonyTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    mediaItem.artist ?? '',
                    style: const TextStyle(color: SymphonyTheme.textSecondary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              iconSize: 28,
              icon: const Icon(Icons.skip_previous, color: Colors.white),
              onPressed: () => handler.skipToPrevious(),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SymphonyTheme.brandGradient,
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 22,
                icon: isBuffering
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                onPressed: () {
                  if (isPlaying) {
                    handler.pause();
                  } else {
                    handler.play();
                  }
                },
              ),
            ),
            IconButton(
              iconSize: 28,
              icon: const Icon(Icons.skip_next, color: Colors.white),
              onPressed: () => handler.skipToNext(),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Mini Scrubber Line
        StreamBuilder<Duration>(
          stream: AudioService.position,
          builder: (context, snapshot) {
            final position = snapshot.data ?? Duration.zero;
            final total = mediaItem.duration ?? Duration.zero;
            final progress = total.inMilliseconds > 0
                ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
                : 0.0;

            return LinearProgressIndicator(
              value: progress,
              backgroundColor: SymphonyTheme.divider,
              valueColor: const AlwaysStoppedAnimation<Color>(SymphonyTheme.primaryLight),
              minHeight: 2,
            );
          },
        ),
      ],
    );
  }

  Widget _buildFallbackArt() {
    return Container(
      width: 56,
      height: 56,
      color: SymphonyTheme.card,
      child: const Icon(Icons.music_note, color: SymphonyTheme.textMuted),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString();
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
