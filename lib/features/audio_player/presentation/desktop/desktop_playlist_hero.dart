import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../playlist_import/domain/entities/spotify_playlist.dart';
import '../../../settings/presentation/widgets/personalization_dialog.dart';
import '../../data/services/symphony_audio_handler.dart';
import '../controllers/audio_player_providers.dart';
import '../controllers/offline_provider.dart';
import '../widgets/import_playlist_dialog.dart';
import '../widgets/nav_history_controls.dart';
import '../widgets/playlist_fallback_cover.dart';

/// Desktop playlist header: large cover, title block, and action row with
/// the "more options" menu.
class DesktopPlaylistHero extends ConsumerWidget {
  final SpotifyPlaylist playlist;
  final SymphonyAccent accent;
  final bool isThisPlaying;
  final bool isPlaylistActive;
  final bool isPlaylistDownloaded;
  final bool isPlaylistDownloading;
  final SymphonyAudioHandler handler;
  final OfflineManagerNotifier offlineNotifier;

  const DesktopPlaylistHero({
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
          colors: [const Color(0xFF5038A0), SymphonyTheme.panel],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const NavHistoryControls(),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const ImportPlaylistDialog(),
                  );
                },
                icon: const Icon(Icons.add, size: 16, color: Colors.black),
                label: const Text(
                  'Import Playlist',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(500)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.55),
                      blurRadius: 36,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
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
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PLAYLIST',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      playlist.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.2,
                        height: 1.05,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    if (playlist.description != null && playlist.description!.isNotEmpty) ...[
                      Text(
                        playlist.description!,
                        style: const TextStyle(color: SymphonyTheme.textSecondary, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.primary,
                          ),
                          child: const Icon(Icons.music_note, size: 14, color: Colors.black),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          playlist.ownerName ?? 'Symphony',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const Text(' • ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        Text(
                          '${playlist.trackCount} songs',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              AnimatedScale(
                scale: isThisPlaying ? 1.04 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.primary,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: IconButton(
                    iconSize: 32,
                    tooltip: isThisPlaying ? 'Pause' : 'Play',
                    icon: Icon(
                      isThisPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.black,
                    ),
                    onPressed: () async {
                      try {
                        if (isThisPlaying) {
                          await handler.pause();
                        } else if (isPlaylistActive) {
                          await handler.play();
                        } else {
                          await handler.playQueue(playlist.tracks, startIndex: 0);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: SymphonyTheme.card,
                              content: Text('Playback error: $e', style: const TextStyle(color: Colors.redAccent)),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 24),
              IconButton(
                iconSize: 32,
                tooltip: 'Save to Your Library',
                icon: const Icon(Icons.favorite_border, color: SymphonyTheme.textSecondary),
                onPressed: () {},
              ),
              const SizedBox(width: 16),
              IconButton(
                iconSize: 32,
                tooltip: isPlaylistDownloaded
                    ? 'Playlist saved for offline playback'
                    : isPlaylistDownloading
                        ? 'Downloading playlist...'
                        : 'Download playlist for offline listening',
                icon: isPlaylistDownloading
                    ? SizedBox(
                        width: 24,
                        height: 24,
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
              const SizedBox(width: 16),
              PopupMenuButton<String>(
                iconSize: 30,
                tooltip: 'More options',
                icon: const Icon(Icons.more_horiz, color: SymphonyTheme.textSecondary),
                color: const Color(0xFF242424),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                onSelected: (val) async {
                  if (val == 'download') {
                    offlineNotifier.downloadPlaylist(playlist);
                  } else if (val == 'play') {
                    handler.playQueue(playlist.tracks, startIndex: 0);
                  } else if (val == 'uninstall_download') {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF242424),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        title: const Text('Uninstall Offline Download?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        content: Text(
                          'This will remove all downloaded audio files for "${playlist.title}" from your device to free up storage space. The playlist will remain in your library for online streaming.',
                          style: const TextStyle(color: SymphonyTheme.textSecondary),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              final freed = await offlineNotifier.removeDownloadedPlaylist(playlist);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: const Color(0xFF282828),
                                    content: Text('Uninstalled offline songs for "${playlist.title}" (${freed ?? "freed cache"})'),
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            },
                            child: const Text('Uninstall', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  } else if (val == 'delete_playlist') {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF242424),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        title: const Text('Delete Playlist?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        content: Text(
                          'Are you sure you want to remove "${playlist.title}" from your library? Any downloaded audio files will also be cleanly uninstalled.',
                          style: const TextStyle(color: SymphonyTheme.textSecondary),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await offlineNotifier.removeDownloadedPlaylist(playlist);
                              ref.read(importedPlaylistsProvider.notifier).removePlaylist(playlist.id);
                              final remaining = ref.read(importedPlaylistsProvider);
                              ref.read(activePlaylistProvider.notifier).state = remaining.isNotEmpty ? remaining.first : null;
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: const Color(0xFF282828),
                                    content: Text('Removed "${playlist.title}" from library'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  } else if (val == 'personalize') {
                    showDialog(context: context, builder: (_) => const PersonalizationDialog());
                  } else if (val == 'import') {
                    showDialog(context: context, builder: (_) => const ImportPlaylistDialog());
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'download',
                    child: Row(
                      children: [
                        Icon(
                          isPlaylistDownloaded ? Icons.check_circle_rounded : Icons.download_rounded,
                          color: isPlaylistDownloaded ? accent.primary : Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isPlaylistDownloaded ? 'Downloaded (Redownload)' : 'Download Playlist Offline',
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'play',
                    child: Row(
                      children: const [
                        Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 12),
                        Text('Play from Beginning', style: TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                  if (isPlaylistDownloaded)
                    PopupMenuItem(
                      value: 'uninstall_download',
                      child: Row(
                        children: const [
                          Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 20),
                          SizedBox(width: 12),
                          Text('Uninstall Offline Download', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'delete_playlist',
                    child: Row(
                      children: const [
                        Icon(Icons.delete_outline_rounded, color: SymphonyTheme.textSecondary, size: 20),
                        SizedBox(width: 12),
                        Text('Delete Playlist from Library', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'personalize',
                    child: Row(
                      children: const [
                        Icon(Icons.person_outline_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 12),
                        Text('Personalize App & Name', style: TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'import',
                    child: Row(
                      children: const [
                        Icon(Icons.add_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 12),
                        Text('Import Another Playlist', style: TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
