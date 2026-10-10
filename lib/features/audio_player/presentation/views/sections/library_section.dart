import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/symphony_theme.dart';
import '../../../../settings/presentation/controllers/personalization_provider.dart';
import '../../controllers/audio_player_providers.dart';
import '../../controllers/offline_provider.dart';
import '../../widgets/nav_history_controls.dart';
import '../../widgets/spotify_playlist_card.dart';
import 'section_header_buttons.dart';

/// "Your Library" tab: imported playlists grid.
class LibrarySection extends ConsumerWidget {
  final bool isDesktop;

  const LibrarySection({super.key, required this.isDesktop});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importedPlaylists = ref.watch(importedPlaylistsProvider);
    final handler = ref.read(audioHandlerProvider);
    final personalization = ref.watch(personalizationProvider);
    final accent = ref.watch(accentThemeProvider);
    final offlineState = ref.watch(offlineProvider);
    final offlineNotifier = ref.read(offlineProvider.notifier);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 28.0 : 16.0, vertical: isDesktop ? 28.0 : 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const NavHistoryControls(),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              personalization.userName.isNotEmpty
                                  ? "${personalization.userName}'s Playlists"
                                  : 'Playlists',
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Your personal music collection • ${importedPlaylists.length} playlists',
                              style: const TextStyle(fontSize: 13, color: SymphonyTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    PersonalizeButton(personalization: personalization, accent: accent),
                    const SizedBox(width: 12),
                    const ImportPlaylistButton(),
                  ],
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const NavHistoryControls(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            personalization.userName.isNotEmpty
                                ? "${personalization.userName}'s Playlists"
                                : 'Playlists',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${importedPlaylists.length} playlists saved',
                            style: const TextStyle(fontSize: 12, color: SymphonyTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: PersonalizeButton(personalization: personalization, accent: accent)),
                    const SizedBox(width: 10),
                    Expanded(child: const ImportPlaylistButton()),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 20),
          if (importedPlaylists.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No playlists imported yet', style: TextStyle(color: SymphonyTheme.textMuted)),
              ),
            )
          else
            Expanded(
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: isDesktop ? 4 : 2,
                  crossAxisSpacing: isDesktop ? 16 : 12,
                  mainAxisSpacing: isDesktop ? 16 : 12,
                  childAspectRatio: isDesktop ? 0.78 : 0.75,
                ),
                itemCount: importedPlaylists.length,
                itemBuilder: (context, index) {
                  final playlist = importedPlaylists[index];
                  final isDownloaded = offlineState.isPlaylistDownloaded(playlist);
                  return SpotifyPlaylistCard(
                    playlist: playlist,
                    accent: accent,
                    isDownloaded: isDownloaded,
                    onTap: () {
                      ref.read(activePlaylistProvider.notifier).state = playlist;
                      ref.read(activeNavTabProvider.notifier).state = 'home';
                    },
                    onPlay: () {
                      ref.read(activePlaylistProvider.notifier).state = playlist;
                      handler.playQueue(playlist.tracks, startIndex: 0);
                    },
                    onDownload: () {
                      offlineNotifier.downloadPlaylist(playlist);
                    },
                    onUninstall: () async {
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
                    onDelete: () async {
                      await offlineNotifier.removeDownloadedPlaylist(playlist);
                      ref.read(importedPlaylistsProvider.notifier).removePlaylist(playlist.id);
                      if (ref.read(activePlaylistProvider)?.id == playlist.id) {
                        final remaining = ref.read(importedPlaylistsProvider);
                        ref.read(activePlaylistProvider.notifier).state = remaining.isNotEmpty ? remaining.first : null;
                      }
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
                  );
                },
              ),
            ),
          SizedBox(height: isDesktop ? 20 : 100),
        ],
      ),
    );
  }
}
