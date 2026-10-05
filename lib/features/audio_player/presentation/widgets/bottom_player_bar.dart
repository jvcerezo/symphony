import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../domain/entities/track.dart';
import '../controllers/audio_player_providers.dart';
import 'animated_equalizer.dart';
import 'symphony_artwork.dart';

class BottomPlayerBar extends ConsumerStatefulWidget {
  const BottomPlayerBar({super.key});

  @override
  ConsumerState<BottomPlayerBar> createState() => _BottomPlayerBarState();
}

class _BottomPlayerBarState extends ConsumerState<BottomPlayerBar> {
  double _volume = 1.0;
  bool _isMuted = false;
  bool _isLiked = false;
  bool _isShuffle = false;
  bool _isRepeat = false;
  bool _isScrubberHovered = false;
  bool _isVolumeHovered = false;

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
    final isMobile = screenWidth < 750;

    return Container(
      height: isMobile ? 74 : 76,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16),
      decoration: const BoxDecoration(
        color: SymphonyTheme.obsidian,
        border: Border(
          top: BorderSide(color: Color(0xFF282828), width: 1),
        ),
      ),
      child: isMobile
          ? _buildMobileLayout(mediaItem, isPlaying, isBuffering)
          : _buildDesktopLayout(mediaItem, isPlaying, isBuffering),
    );
  }

  Widget _buildDesktopLayout(MediaItem mediaItem, bool isPlaying, bool isBuffering) {
    final handler = ref.read(audioHandlerProvider);
    final accent = ref.watch(accentThemeProvider);

    return Row(
      children: [
        // Left Column (flex 3): Artwork + Title + Artist + Like
        Expanded(
          flex: 3,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SymphonyArtwork(
                  artworkUri: mediaItem.artUri,
                  track: Track(
                    id: mediaItem.id,
                    title: mediaItem.title,
                    artist: mediaItem.artist ?? '',
                    album: mediaItem.album,
                    artworkUri: mediaItem.artUri,
                  ),
                  size: 56,
                  borderRadius: 4,
                  hasGlow: false,
                ),
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
                        color: Colors.white,
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
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: _isLiked ? 'Remove from Your Library' : 'Save to Your Library',
                icon: Icon(
                  _isLiked ? Icons.favorite : Icons.favorite_border,
                  color: _isLiked ? accent.primary : SymphonyTheme.textSecondary,
                ),
                onPressed: () => setState(() => _isLiked = !_isLiked),
              ),
            ],
          ),
        ),

        // Center Column (flex 5): Controls + Scrubber
        Expanded(
          flex: 5,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Upper Control Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'Enable shuffle',
                    icon: Icon(
                      Icons.shuffle,
                      color: _isShuffle ? accent.primary : SymphonyTheme.textSecondary,
                    ),
                    onPressed: () => setState(() => _isShuffle = !_isShuffle),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    iconSize: 22,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'Previous',
                    icon: const Icon(Icons.skip_previous, color: SymphonyTheme.textSecondary),
                    hoverColor: Colors.transparent,
                    onPressed: () => handler.skipToPrevious(),
                  ),
                  const SizedBox(width: 8),
                  // Play/Pause Button (Spotify Benchmark: White circular button with black icon)
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      tooltip: isPlaying ? 'Pause' : 'Play',
                      icon: isBuffering
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                            )
                          : Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.black,
                            ),
                      onPressed: () async {
                        if (isPlaying) {
                          await handler.pause();
                        } else {
                          await handler.play();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    iconSize: 22,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'Next',
                    icon: const Icon(Icons.skip_next, color: SymphonyTheme.textSecondary),
                    hoverColor: Colors.transparent,
                    onPressed: () => handler.skipToNext(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    iconSize: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'Enable repeat',
                    icon: Icon(
                      Icons.repeat,
                      color: _isRepeat ? accent.primary : SymphonyTheme.textSecondary,
                    ),
                    onPressed: () => setState(() => _isRepeat = !_isRepeat),
                  ),
                ],
              ),

              const SizedBox(height: 2),

              // Scrubber Line (Interactive Spotify Style)
              MouseRegion(
                onEnter: (_) => setState(() => _isScrubberHovered = true),
                onExit: (_) => setState(() => _isScrubberHovered = false),
                child: StreamBuilder<Duration>(
                  stream: AudioService.position,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    final total = mediaItem.duration ?? Duration.zero;
                    final totalMs = total.inMilliseconds.toDouble();
                    final posMs =
                        position.inMilliseconds.toDouble().clamp(0.0, totalMs > 0 ? totalMs : 1.0);

                    return Row(
                      children: [
                        SizedBox(
                          width: 38,
                          child: Text(
                            _formatDuration(position),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 11, color: SymphonyTheme.textSecondary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4.0,
                              thumbShape: RoundSliderThumbShape(
                                enabledThumbRadius: _isScrubberHovered ? 6.0 : 0.0,
                              ),
                              overlayShape: RoundSliderOverlayShape(
                                overlayRadius: _isScrubberHovered ? 12.0 : 0.0,
                              ),
                              activeTrackColor: _isScrubberHovered
                                  ? accent.primary
                                  : Colors.white,
                              inactiveTrackColor: const Color(0xFF4D4D4D),
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              value: posMs,
                              max: totalMs > 0 ? totalMs : 1.0,
                              onChanged: (val) {
                                handler.seek(Duration(milliseconds: val.round()));
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 38,
                          child: Text(
                            _formatDuration(total),
                            style: const TextStyle(fontSize: 11, color: SymphonyTheme.textSecondary),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // Right Column (flex 3): Lyrics + Queue + Offline Badge + Volume + Fullscreen
        Expanded(
          flex: 3,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Lyrics',
                icon: const Icon(Icons.mic_none_outlined, color: SymphonyTheme.textSecondary),
                onPressed: () {},
              ),
              IconButton(
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Queue',
                icon: const Icon(Icons.queue_music_rounded, color: SymphonyTheme.textSecondary),
                onPressed: () {},
              ),
              const SizedBox(width: 6),
              IconButton(
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(
                  _isMuted || _volume == 0
                      ? Icons.volume_off_rounded
                      : (_volume < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                  color: SymphonyTheme.textSecondary,
                ),
                onPressed: () {
                  setState(() {
                    _isMuted = !_isMuted;
                    handler.setVolume(_isMuted ? 0.0 : _volume);
                  });
                },
              ),
              MouseRegion(
                onEnter: (_) => setState(() => _isVolumeHovered = true),
                onExit: (_) => setState(() => _isVolumeHovered = false),
                child: SizedBox(
                  width: 90,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4.0,
                      thumbShape: RoundSliderThumbShape(
                        enabledThumbRadius: _isVolumeHovered ? 5.0 : 0.0,
                      ),
                      overlayShape: RoundSliderOverlayShape(
                        overlayRadius: _isVolumeHovered ? 10.0 : 0.0,
                      ),
                      activeTrackColor: _isVolumeHovered
                          ? accent.primary
                          : Colors.white,
                      inactiveTrackColor: const Color(0xFF4D4D4D),
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: _isMuted ? 0.0 : _volume,
                      min: 0.0,
                      max: 1.0,
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
              ),
              const SizedBox(width: 4),
              IconButton(
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Full screen',
                icon: const Icon(Icons.fullscreen_rounded, color: SymphonyTheme.textSecondary),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(MediaItem mediaItem, bool isPlaying, bool isBuffering) {
    final handler = ref.read(audioHandlerProvider);
    final accent = ref.watch(accentThemeProvider);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SymphonyArtwork(
                artworkUri: mediaItem.artUri,
                track: Track(
                  id: mediaItem.id,
                  title: mediaItem.title,
                  artist: mediaItem.artist ?? '',
                  album: mediaItem.album,
                  artworkUri: mediaItem.artUri,
                ),
                size: 44,
                borderRadius: 4,
              ),
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
                      color: Colors.white,
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
              iconSize: 20,
              icon: Icon(
                _isLiked ? Icons.favorite : Icons.favorite_border,
                color: _isLiked ? accent.primary : SymphonyTheme.textSecondary,
              ),
              onPressed: () => setState(() => _isLiked = !_isLiked),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 22,
                icon: isBuffering
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                      )
                    : Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.black),
                onPressed: () async {
                  if (isPlaying) {
                    await handler.pause();
                  } else {
                    await handler.play();
                  }
                },
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              iconSize: 24,
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
              backgroundColor: const Color(0xFF4D4D4D),
              valueColor: AlwaysStoppedAnimation<Color>(accent.primary),
              minHeight: 2,
            );
          },
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString();
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
