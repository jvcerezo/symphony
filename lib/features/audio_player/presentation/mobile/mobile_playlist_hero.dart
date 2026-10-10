import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../playlist_import/domain/entities/spotify_playlist.dart';
import '../../data/services/symphony_audio_handler.dart';
import '../controllers/navigation_history_provider.dart';
import '../controllers/offline_provider.dart';
import '../widgets/import_playlist_dialog.dart';
import '../widgets/playlist_fallback_cover.dart';

/// Mobile playlist header: centered cover, title, and action row.
class MobilePlaylistHero extends ConsumerWidget {
  final SpotifyPlaylist playlist;
  final SymphonyAccent accent;
  final bool isThisPlaying;
  final bool isPlaylistActive;
  final bool isPlaylistDownloaded;
  final bool isPlaylistDownloading;
  final SymphonyAudioHandler handler;
  final OfflineManagerNotifier offlineNotifier;

  const MobilePlaylistHero({
    super.key,
    required this.playlist,
    required this.accent,
    required this.isThisPlaying,
    required this.isPlaylistActive,
    required this.isPlaylistDownloaded,
    required this.isPlaylistDownloading,
    required this.handler,
    required this.offlineNotifier,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFF4A347F), SymphonyTheme.panel],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (ref.watch(navigationHistoryProvider).canGoBack) ...[
                      GestureDetector(
                        onTap: () => ref.read(navigationHistoryProvider.notifier).goBack(ref),
                        child: const Padding(
                          padding: EdgeInsets.only(right: 8.0),
                          child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                    const Text(
                      'PLAYLIST',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => const ImportPlaylistDialog(),
                    );
                  },
                  icon: const Icon(Icons.add, size: 16, color: Colors.white),
                  label: const Text(
                    'Import',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(500)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.6),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: playlist.coverUrl != null
                      ? Image.network(
                          playlist.coverUrl!,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (context, error, stackTrace) => const PlaylistFallbackCover(),
                        )
                      : const PlaylistFallbackCover(),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              playlist.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              '${playlist.ownerName ?? "Symphony"} • ${playlist.trackCount} songs',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SymphonyTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                IconButton(
                  iconSize: 26,
                  icon: const Icon(Icons.favorite_border, color: SymphonyTheme.textSecondary),
                  onPressed: () {},
                ),
                const SizedBox(width: 8),
                IconButton(
                  iconSize: 26,
                  icon: isPlaylistDownloading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: accent.primary,
                          ),
                        )
                      : Icon(
                          isPlaylistDownloaded ? Icons.download_done_rounded : Icons.arrow_circle_down_outlined,
                          color: isPlaylistDownloaded ? accent.primary : SymphonyTheme.textSecondary,
                        ),
                  onPressed: () async {
                    if (isPlaylistDownloading) return;
                    await offlineNotifier.downloadPlaylist(playlist);
                  },
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    if (isThisPlaying) {
                      await handler.pause();
                    } else if (isPlaylistActive) {
                      await handler.play();
                    } else {
                      await handler.playQueue(playlist.tracks, startIndex: 0);
                    }
                  },
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.primary,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(
                      isThisPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.black,
                      size: 32,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
  }
}
