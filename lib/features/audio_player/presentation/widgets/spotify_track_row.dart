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

  void _showMobileTrackOptions(BuildContext context, SymphonyAccent accent) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SymphonyArtwork(track: widget.track, size: 52),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.track.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.track.artist,
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
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF333333)),
                ListTile(
                  leading: Icon(
                    _isLiked ? Icons.favorite : Icons.favorite_border,
                    color: _isLiked ? accent.primary : Colors.white,
                  ),
                  title: Text(
                    _isLiked ? 'Liked in Your Library' : 'Like this song',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    setState(() => _isLiked = !_isLiked);
                    Navigator.pop(ctx);
                  },
                ),
                if (widget.onDownload != null)
                  ListTile(
                    leading: Icon(
                      widget.isDownloaded ? Icons.check_circle : Icons.download_rounded,
                      color: widget.isDownloaded ? accent.primary : Colors.white,
                    ),
                    title: Text(
                      widget.isDownloaded ? 'Downloaded for offline' : 'Download song offline',
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.onDownload?.call();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(accentThemeProvider);
    final track = widget.track;
    final isCurrent = widget.isCurrent;
    final isBuffering = widget.isBuffering;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    if (isMobile) {
      return _buildMobileRow(accent, track, isCurrent, isBuffering);
    }

    return _buildDesktopRow(accent, track, isCurrent, isBuffering, screenWidth);
  }

  Widget _buildMobileRow(SymphonyAccent accent, Track track, bool isCurrent, bool isBuffering) {
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isCurrent ? Colors.white.withOpacity(0.06) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            // 1. High-Resolution Artwork (48x48) with live equalizer overlay if active
            Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SymphonyArtwork(
                    track: track,
                    size: 48,
                    borderRadius: 4,
                  ),
                ),
                if (isCurrent && isBuffering)
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent.primary,
                        ),
                      ),
                    ),
                  )
                else if (isCurrent && widget.isPlaying)
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: AnimatedEqualizer(
                        isPlaying: true,
                        height: 18,
                        color: accent.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),

            // 2. Song Title & Artist (Spans 100% of remaining width)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: TextStyle(
                      color: isCurrent ? accent.primary : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (widget.isDownloaded) ...[
                        Icon(Icons.check_circle, size: 12, color: accent.primary),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          track.artist,
                          style: const TextStyle(
                            color: SymphonyTheme.textSecondary,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // 3. Status indicator & More Options
            if (widget.isDownloading)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: accent.primary),
                ),
              ),

            IconButton(
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(Icons.more_vert, color: SymphonyTheme.textSecondary),
              onPressed: () => _showMobileTrackOptions(context, accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopRow(SymphonyAccent accent, Track track, bool isCurrent, bool isBuffering, double screenWidth) {
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

              // Like / Heart Button
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
