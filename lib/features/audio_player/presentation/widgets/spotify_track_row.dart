import 'package:flutter/material.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../domain/entities/track.dart';
import 'animated_equalizer.dart';
import 'symphony_artwork.dart';

class SpotifyTrackRow extends StatefulWidget {
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
  State<SpotifyTrackRow> createState() => _SpotifyTrackRowState();
}

class _SpotifyTrackRowState extends State<SpotifyTrackRow> {
  bool _isHovered = false;
  bool _isLiked = false;

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final isCurrent = widget.isCurrent;
    final isBuffering = widget.isBuffering;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: SymphonyTheme.cardHover.withAlpha(150),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isCurrent ? SymphonyTheme.primaryDark.withAlpha(40) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              // Index, Loading Spinner, Animated Equalizer, or Play/Pause Icon
              SizedBox(
                width: 32,
                child: isCurrent && isBuffering
                    ? const Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: SymphonyTheme.primaryLight,
                          ),
                        ),
                      )
                    : isCurrent && widget.isPlaying && !_isHovered
                        ? const Center(child: AnimatedEqualizer(isPlaying: true, height: 14))
                        : (_isHovered || isCurrent
                            ? Icon(
                                isCurrent && widget.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: isCurrent ? SymphonyTheme.primaryLight : Colors.white,
                                size: 20,
                              )
                            : Text(
                                '${widget.index + 1}',
                                style: TextStyle(
                                  color: isCurrent ? SymphonyTheme.primaryLight : SymphonyTheme.textMuted,
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 14,
                                ),
                              )),
              ),
              const SizedBox(width: 12),
              // Artwork Thumbnail
              SymphonyArtwork(
                track: track,
                size: 44,
                borderRadius: 4,
              ),
              const SizedBox(width: 16),
              // Title & Artist
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: TextStyle(
                        color: isCurrent ? SymphonyTheme.primaryLight : SymphonyTheme.textPrimary,
                        fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 15,
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
              // Like Button
              IconButton(
                iconSize: 20,
                icon: Icon(
                  _isLiked ? Icons.favorite : Icons.favorite_border,
                  color: _isLiked ? SymphonyTheme.primaryLight : SymphonyTheme.textMuted,
                ),
                onPressed: () {
                  setState(() => _isLiked = !_isLiked);
                },
              ),
              const SizedBox(width: 6),
              // Offline Download Indicator / Button
              if (widget.isDownloading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: SymphonyTheme.secondary,
                  ),
                )
              else if (widget.isDownloaded)
                const Tooltip(
                  message: 'Saved offline (no internet needed)',
                  child: Icon(
                    Icons.check_circle,
                    size: 16,
                    color: SymphonyTheme.secondary,
                  ),
                )
              else if (_isHovered && widget.onDownload != null)
                IconButton(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  tooltip: 'Download track offline',
                  icon: const Icon(Icons.arrow_circle_down_outlined, color: SymphonyTheme.textSecondary),
                  onPressed: widget.onDownload,
                )
              else
                const SizedBox(width: 16),
              const SizedBox(width: 10),
              // Duration
              Text(
                _formatDuration(track.expectedDuration ?? Duration.zero),
                style: TextStyle(
                  color: isCurrent ? SymphonyTheme.primaryLight : SymphonyTheme.textMuted,
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
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
