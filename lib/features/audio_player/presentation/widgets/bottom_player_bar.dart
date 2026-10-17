import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/layout/breakpoints.dart';
import '../../../../core/services/windows_tray.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../../core/widgets/hover_widgets.dart';
import '../../../../core/widgets/motion.dart';
import '../../../jam/data/jam_transport.dart';
import '../../domain/entities/track.dart';
import '../controllers/audio_player_providers.dart';
import '../controllers/now_playing_panel_provider.dart';
import '../controllers/now_playing_tint_provider.dart';
import '../desktop/desktop_volume_provider.dart';
import '../mobile/mobile_now_playing_sheet.dart';
import 'playback_mode_buttons.dart';
import 'symphony_artwork.dart';

class BottomPlayerBar extends ConsumerStatefulWidget {
  const BottomPlayerBar({super.key});

  @override
  ConsumerState<BottomPlayerBar> createState() => _BottomPlayerBarState();
}

class _BottomPlayerBarState extends ConsumerState<BottomPlayerBar> {
  bool _isLiked = false;
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

    final isMobile = Breakpoints.isMobile(context);
    final tint = ref.watch(nowPlayingTintProvider).valueOrNull;

    // Glass tinted with the cover's color, which fades over on song change.
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: tint ?? (isMobile ? SymphonyTheme.glassMini : SymphonyTheme.glassBar)),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOut,
      builder: (context, color, child) => Container(
        height: isMobile ? 68 : 76,
        margin: isMobile ? const EdgeInsets.fromLTRB(8, 0, 8, 6) : EdgeInsets.zero,
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: isMobile ? 6 : 0),
        decoration: BoxDecoration(
          color: isMobile ? SymphonyTheme.glassMini : SymphonyTheme.glassBar,
          gradient: color == null
              ? null
              : LinearGradient(
                  colors: isMobile
                      ? [color.withValues(alpha: 0.85), SymphonyTheme.glassMini]
                      : [color.withValues(alpha: 0.4), SymphonyTheme.glassBar],
                  stops: isMobile ? const [0.0, 1.0] : const [0.0, 0.5],
                ),
          borderRadius: isMobile ? BorderRadius.circular(10) : BorderRadius.zero,
          border: isMobile
              ? Border.all(color: SymphonyTheme.glassEdge, width: 0.5)
              : const Border(top: BorderSide(color: SymphonyTheme.glassEdge, width: 1)),
          boxShadow: isMobile
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: child,
      ),
      child: isMobile
          ? _buildMobileLayout(mediaItem, isPlaying, isBuffering)
          : _buildDesktopLayout(mediaItem, isPlaying, isBuffering),
    );
  }

  Widget _buildDesktopLayout(MediaItem mediaItem, bool isPlaying, bool isBuffering) {
    final handler = ref.read(audioHandlerProvider);
    final accent = ref.watch(accentThemeProvider);
    final volume = ref.watch(volumeProvider);

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
              HoverIconButton(
                tooltip: _isLiked ? 'Remove from Your Library' : 'Save to Your Library',
                icon: _isLiked ? Icons.favorite : Icons.favorite_border,
                isSelected: _isLiked,
                activeColor: accent.primary,
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
                  const ShuffleButton(),
                  const SizedBox(width: 8),
                  HoverIconButton(
                    iconSize: 22,
                    tooltip: 'Previous',
                    icon: Icons.skip_previous,
                    onPressed: () => handler.skipToPrevious(),
                  ),
                  const SizedBox(width: 8),
                  // Play/Pause Button (Spotify Benchmark: White circular button with black icon)
                  HoverGrow(
                    child: Container(
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
                          : PlayPauseIcon(isPlaying: isPlaying, size: 20),
                      onPressed: () async {
                        if (isPlaying) {
                          await handler.pause();
                        } else {
                          await handler.play();
                        }
                      },
                    ),
                  ),
                  ),
                  const SizedBox(width: 8),
                  HoverIconButton(
                    iconSize: 22,
                    tooltip: 'Next',
                    icon: Icons.skip_next,
                    onPressed: () => handler.skipToNext(),
                  ),
                  const SizedBox(width: 8),
                  const RepeatButton(),
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

        // Right Column (flex 3): Lyrics + Queue + Jam + Volume + Fullscreen
        Expanded(
          flex: 3,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _panelToggle(NowPlayingPanel.lyrics, Icons.mic_none_outlined, 'Lyrics', accent),
              _panelToggle(NowPlayingPanel.queue, Icons.queue_music_rounded, 'Queue', accent),
              if (lanJamSupported) _panelToggle(NowPlayingPanel.jam, Icons.groups_rounded, 'Jam', accent),
              const SizedBox(width: 6),
              HoverIconButton(
                iconSize: 20,
                tooltip: volume.effective == 0 ? 'Unmute' : 'Mute',
                icon: volume.effective == 0
                    ? Icons.volume_off_rounded
                    : (volume.level < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                onPressed: () => ref.read(volumeProvider.notifier).toggleMute(),
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
                      value: volume.effective,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (val) => ref.read(volumeProvider.notifier).setLevel(val),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows)
                HoverIconButton(
                  tooltip: 'Full screen',
                  icon: Icons.fullscreen_rounded,
                  onPressed: toggleFullScreen,
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Opens or closes a side panel; lit while that panel is open.
  Widget _panelToggle(NowPlayingPanel panel, IconData icon, String label, SymphonyAccent accent) {
    final open = ref.watch(nowPlayingPanelProvider) == panel;
    return HoverIconButton(
      tooltip: open ? 'Hide $label' : label,
      isSelected: open,
      activeColor: accent.primary,
      icon: icon,
      onPressed: () => ref.read(nowPlayingPanelProvider.notifier).state = open ? null : panel,
    );
  }

  Widget _buildMobileLayout(MediaItem mediaItem, bool isPlaying, bool isBuffering) {
    final handler = ref.read(audioHandlerProvider);
    final accent = ref.watch(accentThemeProvider);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showMobileNowPlaying(context),
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < -250) showMobileNowPlaying(context);
      },
      child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            // Flies up into the Now Playing view when it opens.
            Hero(
              tag: nowPlayingArtworkHeroTag,
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
                      fontSize: 14,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mediaItem.artist ?? '',
                    style: const TextStyle(color: SymphonyTheme.textSecondary, fontSize: 12),
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
                    : PlayPauseIcon(isPlaying: isPlaying, size: 22),
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
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString();
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
