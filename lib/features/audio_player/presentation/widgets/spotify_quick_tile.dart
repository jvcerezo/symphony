import 'package:flutter/material.dart';
import '../../../../core/layout/breakpoints.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../playlist_import/domain/entities/spotify_playlist.dart';

/// Compact quick-access playlist tile used on the Home dashboard.
class SpotifyQuickTile extends StatefulWidget {
  final SpotifyPlaylist playlist;
  final SymphonyAccent accent;
  final bool isPlaying;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  const SpotifyQuickTile({
    super.key,
    required this.playlist,
    required this.accent,
    required this.isPlaying,
    required this.isCurrent,
    required this.onTap,
    required this.onPlay,
  });

  @override
  State<SpotifyQuickTile> createState() => _SpotifyQuickTileState();
}

class _SpotifyQuickTileState extends State<SpotifyQuickTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isMobile = Breakpoints.isMobile(context);
    final showPlay = _isHovered || widget.isCurrent || isMobile;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _isHovered ? Colors.white.withOpacity(0.18) : Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  bottomLeft: Radius.circular(6),
                ),
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: widget.playlist.coverUrl != null
                      ? Image.network(
                          widget.playlist.coverUrl!,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFF282828),
                            child: const Icon(Icons.music_note, color: Colors.white54, size: 28),
                          ),
                        )
                      : Container(
                          color: const Color(0xFF282828),
                          child: const Icon(Icons.music_note, color: Colors.white54, size: 28),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.playlist.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Floating / persistent Play button
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: showPlay ? 1.0 : 0.0,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10.0),
                  child: GestureDetector(
                    onTap: widget.onPlay,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: widget.accent.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        (widget.isCurrent && widget.isPlaying) ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
