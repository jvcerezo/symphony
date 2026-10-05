import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../domain/entities/track.dart';
import '../controllers/audio_player_providers.dart';
import 'animated_equalizer.dart';
import 'symphony_artwork.dart';

class SpotifyTrackRow extends ConsumerStatefulWidget {
  final int index;
  final Track track;
  final bool isPlaying;
  final bool isCurrent;
  final bool isBuffering;
  final bool isDownloaded;
  final bool isDownloading;
  final VoidCallback? onDownload;
  final VoidCallback onTap;

  const SpotifyTrackRow({
    super.key,
    required this.index,
    required this.track,
    required this.isPlaying,
    required this.isCurrent,
    this.isBuffering = false,
    this.isDownloaded = false,
    this.isDownloading = false,
    this.onDownload,
    required this.onTap,
  });

  @override
  ConsumerState<SpotifyTrackRow> createState() => _SpotifyTrackRowState();
}

class _SpotifyTrackRowState extends ConsumerState<SpotifyTrackRow> {
  bool _isHovered = false;
  bool _isLiked = false;

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(accentThemeProvider);
    final track = widget.track;
    final isCurrent = widget.isCurrent;
    final isBuffering = widget.isBuffering;
    final screenWidth = MediaQuery.of(context).size.width;
    final showAlbum = screenWidth >= 800;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(4),
        hoverColor: Colors.transparent,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isCurrent
                ? (isBuffering ? SymphonyTheme.cardHover.withOpacity(0.4) : Colors.white.withOpacity(0.08))
                : (_isHovered ? SymphonyTheme.cardHover.withOpacity(0.7) : Colors.transparent),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              // Index, Loading Spinner, Animated Equalizer, or Play/Pause Icon
              SizedBox(
                width: 32,
                child: isCurrent && isBuffering
                    ? Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accent.primary,
                          ),
                        ),
                      )
                    : isCurrent && widget.isPlaying && !_isHovered
                        ? Center(child: AnimatedEqualizer(isPlaying: true, height: 14, color: accent.primary))
                        : (_isHovered || isCurrent
                            ? Icon(
                                isCurrent && widget.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: isCurrent ? accent.primary : Colors.white,
                                size: 20,
                              )
                            : Text(
                                '${widget.index + 1}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isCurrent ? accent.primary : SymphonyTheme.textSecondary,
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 14,
                                ),
                              )),
              ),
              const SizedBox(width: 12),

              // Artwork Thumbnail (40x40)
              SymphonyArtwork(
                track: track,
                size: 40,
                borderRadius: 4,
              ),
              const SizedBox(width: 14),

              // Title & Artist
              Expanded(
                flex: 4,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: TextStyle(
                        color: isCurrent ? accent.primary : Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      track.artist,
                      style: const TextStyle(
                        color: SymphonyTheme.textSecondary,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Album Column (Visible on Desktop)
              if (showAlbum) ...[
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: Text(
                    (track.album != null && track.album!.isNotEmpty) ? track.album! : track.title,
                    style: const TextStyle(
                      color: SymphonyTheme.textSecondary,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],

              // Like / Heart Button (Only appears on hover or if liked)
              Opacity(
                opacity: (_isLiked || _isHovered) ? 1.0 : 0.0,
                child: IconButton(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: _isLiked ? 'Remove from Your Library' : 'Save to Your Library',
                  icon: Icon(
                    _isLiked ? Icons.favorite : Icons.favorite_border,
                    color: _isLiked ? accent.primary : SymphonyTheme.textSecondary,
                  ),
                  onPressed: () {
                    setState(() => _isLiked = !_isLiked);
                  },
                ),
              ),

              const SizedBox(width: 8),

              // Offline Download Indicator / Button
              if (widget.isDownloading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent.primary,
                  ),
                )
              else if (widget.isDownloaded)
                Tooltip(
                  message: 'Saved offline (no internet needed)',
                  child: Icon(
                    Icons.check_circle,
                    size: 16,
                    color: accent.primary,
                  ),
                )
              else if (_isHovered && widget.onDownload != null)
                IconButton(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: 'Download track offline',
                  icon: const Icon(Icons.arrow_circle_down_outlined, color: SymphonyTheme.textSecondary),
                  onPressed: widget.onDownload,
                )
              else
                const SizedBox(width: 16),

              const SizedBox(width: 16),

              // Track Duration
              SizedBox(
                width: 44,
                child: Text(
                  _formatDuration(track.expectedDuration ?? Duration.zero),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: isCurrent ? accent.primary : SymphonyTheme.textSecondary,
                    fontSize: 13,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // More options button (visible on hover)
              Opacity(
                opacity: _isHovered ? 1.0 : 0.0,
                child: IconButton(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  icon: const Icon(Icons.more_horiz, color: SymphonyTheme.textSecondary),
                  onPressed: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds == 0) return '--:--';
    final minutes = d.inMinutes.remainder(60).toString();
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
