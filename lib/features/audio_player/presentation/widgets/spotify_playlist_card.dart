import 'package:flutter/material.dart';
import '../../../../core/layout/breakpoints.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../playlist_import/domain/entities/spotify_playlist.dart';

/// Playlist cover card with hover play button and a choices menu.
class SpotifyPlaylistCard extends StatefulWidget {
  final SpotifyPlaylist playlist;
  final SymphonyAccent accent;
  final bool isDownloaded;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback? onDownload;
  final VoidCallback? onUninstall;
  final VoidCallback? onDelete;

  const SpotifyPlaylistCard({
    super.key,
    required this.playlist,
    required this.accent,
    this.isDownloaded = false,
    required this.onTap,
    required this.onPlay,
    this.onDownload,
    this.onUninstall,
    this.onDelete,
  });

  @override
  State<SpotifyPlaylistCard> createState() => _SpotifyPlaylistCardState();
}

class _SpotifyPlaylistCardState extends State<SpotifyPlaylistCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final playlist = widget.playlist;
    final isMobile = Breakpoints.isMobile(context);
    final showPlay = _isHovered || isMobile;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.all(isMobile ? 10 : 14),
          decoration: BoxDecoration(
            color: _isHovered ? SymphonyTheme.cardHover : SymphonyTheme.card,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover with hover play button & 3-dots choices
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: playlist.coverUrl != null
                          ? Image.network(
                              playlist.coverUrl!,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.high,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: const Color(0xFF282828),
                                child: const Icon(Icons.music_note, color: SymphonyTheme.textMuted, size: 40),
                              ),
                            )
                          : Container(
                              color: const Color(0xFF282828),
                              child: const Icon(Icons.music_note, color: SymphonyTheme.textMuted, size: 40),
                            ),
                    ),
                  ),
                  // 3-dots choice button on the card
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        shape: BoxShape.circle,
                      ),
                      child: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                        color: const Color(0xFF242424),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        tooltip: 'Playlist choices',
                        onSelected: (val) {
                          if (val == 'download') {
                            widget.onDownload?.call();
                          } else if (val == 'play') {
                            widget.onPlay();
                          } else if (val == 'uninstall') {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: const Color(0xFF242424),
                                title: const Text('Uninstall Download?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                content: Text(
                                  'Remove downloaded offline audio files for "${widget.playlist.title}"? Tracks shared with other offline playlists will be kept.',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      widget.onUninstall?.call();
                                    },
                                    child: const Text('Uninstall', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );
                          } else if (val == 'delete') {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: const Color(0xFF242424),
                                title: const Text('Delete Playlist?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                content: Text(
                                  'Are you sure you want to remove "${widget.playlist.title}" from your library?',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      widget.onDelete?.call();
                                    },
                                    child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );
                          }
                        },
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: 'download',
                            child: Row(
                              children: [
                                Icon(
                                  widget.isDownloaded ? Icons.check_circle_rounded : Icons.download_rounded,
                                  color: widget.isDownloaded ? widget.accent.primary : Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  widget.isDownloaded ? 'Downloaded (Redownload)' : 'Download for Offline',
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'play',
                            child: Row(
                              children: const [
                                Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                                SizedBox(width: 10),
                                Text('Play Playlist', style: TextStyle(color: Colors.white, fontSize: 13)),
                              ],
                            ),
                          ),
                          if (widget.isDownloaded)
                            PopupMenuItem(
                              value: 'uninstall',
                              child: Row(
                                children: const [
                                  Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 18),
                                  SizedBox(width: 10),
                                  Text('Uninstall Offline Download', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                                ],
                              ),
                            ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: const [
                                Icon(Icons.delete_outline_rounded, color: SymphonyTheme.textSecondary, size: 18),
                                SizedBox(width: 10),
                                Text('Delete from Library', style: TextStyle(color: Colors.white70, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: AnimatedOpacity(
                      opacity: showPlay ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: AnimatedSlide(
                        offset: showPlay ? Offset.zero : const Offset(0, 0.25),
                        duration: const Duration(milliseconds: 200),
                        child: GestureDetector(
                          onTap: widget.onPlay,
                          child: Container(
                            width: isMobile ? 38 : 48,
                            height: isMobile ? 38 : 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: widget.accent.primary,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.4),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(Icons.play_arrow_rounded, color: Colors.black, size: isMobile ? 22 : 30),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                playlist.title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                playlist.description != null && playlist.description!.isNotEmpty
                    ? playlist.description!
                    : 'By ${playlist.ownerName ?? "Symphony"} • ${playlist.trackCount} songs',
                style: const TextStyle(fontSize: 13, color: SymphonyTheme.textSecondary, height: 1.2),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
