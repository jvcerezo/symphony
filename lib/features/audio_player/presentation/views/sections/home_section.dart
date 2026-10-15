import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/symphony_theme.dart';
import '../../../../../core/widgets/hover_widgets.dart';
import '../../../../browse/data/genre_catalog.dart';
import '../../../../browse/presentation/genre_providers.dart';
import '../../../../jam/presentation/jam_panel.dart';
import '../../../../../core/widgets/symphony_brand_logo.dart';
import '../../../../settings/presentation/controllers/personalization_provider.dart';
import '../../controllers/audio_player_providers.dart';
import '../../controllers/navigation_history_provider.dart';
import '../../controllers/offline_provider.dart';
import '../../widgets/import_playlist_dialog.dart';
import '../../widgets/nav_history_controls.dart';
import '../../widgets/spotify_playlist_card.dart';
import '../../widgets/spotify_quick_tile.dart';
import 'section_header_buttons.dart';

/// Home dashboard: greeting, filter chips, quick tiles, featured playlists,
/// popular tracks, genre grid and the import banner.
///
/// The selected filter is owned by the caller so it survives tab switches.
class HomeSection extends ConsumerWidget {
  final bool isDesktop;
  final MediaItem? mediaItem;
  final bool isPlaying;
  final bool isBuffering;

  /// 'all' | 'music' | 'downloaded'
  final String homeFilter;
  final ValueChanged<String> onHomeFilterChanged;

  const HomeSection({
    super.key,
    required this.isDesktop,
    required this.mediaItem,
    required this.isPlaying,
    required this.isBuffering,
    required this.homeFilter,
    required this.onHomeFilterChanged,
  });

  String _getTimeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildHomeFilterChip(String label, String value, SymphonyAccent accent) {
    final isSelected = homeFilter == value;
    return HoverBuilder(
      onTap: () => onHomeFilterChanged(value),
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : (hovered ? SymphonyTheme.cardActive : SymphonyTheme.divider),
          borderRadius: BorderRadius.circular(500),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildGenreCard(WidgetRef ref, Genre card) {
    return HoverBuilder(
      onTap: () => ref.read(activeGenreProvider.notifier).state = card,
      builder: (context, hovered) => AnimatedScale(
        scale: hovered ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: card.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: hovered ? 0.4 : 0.2),
              blurRadius: hovered ? 14 : 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(
                card.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            Positioned(
              right: -8,
              bottom: -6,
              child: Transform.rotate(
                angle: 0.35,
                child: Icon(
                  card.icon,
                  color: Colors.white.withOpacity(0.75),
                  size: 52,
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildImportBanner(BuildContext context, SymphonyAccent accent, bool isMobile) {
    if (isMobile) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accent.primary.withValues(alpha: 0.25), const Color(0xFF1E1E1E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.primary.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accent.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_to_photos_rounded, color: Colors.black, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Import Your Own Playlists',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Paste any public Spotify or Apple Music link to save it directly to this device for offline playback.',
              style: TextStyle(color: SymphonyTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const ImportPlaylistDialog()),
                icon: const Icon(Icons.download_rounded, size: 16, color: Colors.black),
                label: const Text('Import Playlist', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(500)),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent.primary.withValues(alpha: 0.25), const Color(0xFF1E1E1E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add_to_photos_rounded, color: Colors.black, size: 24),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Have your own favorite playlists?',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 2),
                Text(
                  'Import public Spotify or Apple Music links to save them to your private offline storage.',
                  style: TextStyle(color: SymphonyTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: () => showDialog(context: context, builder: (_) => const ImportPlaylistDialog()),
            icon: const Icon(Icons.download_rounded, size: 16, color: Colors.black),
            label: const Text('Import Playlist', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(500)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importedPlaylists = ref.watch(importedPlaylistsProvider);
    final personalization = ref.watch(personalizationProvider);
    final accent = ref.watch(accentThemeProvider);
    final offlineState = ref.watch(offlineProvider);
    final offlineNotifier = ref.read(offlineProvider.notifier);
    final handler = ref.read(audioHandlerProvider);

    var filteredPlaylists = importedPlaylists;
    if (homeFilter == 'downloaded') {
      filteredPlaylists = filteredPlaylists.where((p) => offlineState.isPlaylistDownloaded(p)).toList();
    }

    final quickTiles = filteredPlaylists.take(6).toList();
    final featuredPlaylists = filteredPlaylists;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 32 : 16,
        vertical: isDesktop ? 24 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top Bar / Navigation Header
          if (isDesktop)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (Navigator.of(context).canPop())
                      Padding(
                        padding: const EdgeInsets.only(right: 12.0),
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded, size: 14, color: Colors.white70),
                          label: const Text('Showcase & Downloads', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF3F3F46)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                      ),
                    const NavHistoryControls(),
                  ],
                ),
                Flexible(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      const JamButton(),
                      PersonalizeButton(personalization: personalization, accent: accent),
                      const ImportPlaylistButton(),
                    ],
                  ),
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (Navigator.of(context).canPop())
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                            onPressed: () => Navigator.of(context).pop(),
                            tooltip: 'Back to Showcase',
                          ),
                        ),
                      const SymphonyBrandLogo(size: 32),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          personalization.displayTitle.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    const JamButton(compact: true),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: PersonalizeButton(personalization: personalization, accent: accent),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => const ImportPlaylistDialog(),
                      ),
                      icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 24),
                      tooltip: 'Import Playlist',
                    ),
                  ],
                ),
              ],
            ),

          SizedBox(height: isDesktop ? 24 : 16),

          // 2. Greeting & Filter Chips
          Text(
            personalization.userName.isNotEmpty
                ? '${_getTimeGreeting()}, ${personalization.userName}'
                : _getTimeGreeting(),
            style: TextStyle(
              fontSize: isDesktop ? 30 : 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),

          // Filter Chips
          Row(
            children: [
              _buildHomeFilterChip('All', 'all', accent),
              const SizedBox(width: 8),
              _buildHomeFilterChip('Music', 'music', accent),
              const SizedBox(width: 8),
              _buildHomeFilterChip('Downloaded', 'downloaded', accent),
            ],
          ),

          const SizedBox(height: 20),

          // 3. Iconic 6 Quick-Access Spotify Tiles
          if (quickTiles.isNotEmpty) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final cols = constraints.maxWidth >= 900 ? 3 : 2;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    mainAxisExtent: 58,
                  ),
                  itemCount: quickTiles.length,
                  itemBuilder: (context, index) {
                    final playlist = quickTiles[index];
                    final isPlaylistActive = playlist.tracks.any(
                      (t) => t.title == mediaItem?.title && t.artist == mediaItem?.artist,
                    );
                    final isThisPlaying = isPlaylistActive && isPlaying;

                    return SpotifyQuickTile(
                      playlist: playlist,
                      accent: accent,
                      isPlaying: isThisPlaying,
                      isCurrent: isPlaylistActive,
                      onTap: () {
                        ref.read(activePlaylistProvider.notifier).state = playlist;
                        ref.read(navigationHistoryProvider.notifier).record('home', playlist);
                      },
                      onPlay: () async {
                        if (isThisPlaying) {
                          await handler.pause();
                        } else if (isPlaylistActive) {
                          await handler.play();
                        } else {
                          await handler.playQueue(playlist.tracks, startIndex: 0);
                        }
                      },
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 36),
          ],

          // 4. Featured Playlists Shelf
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Your Playlists',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.4),
              ),
              Text(
                '${featuredPlaylists.length} playlists',
                style: const TextStyle(fontSize: 13, color: SymphonyTheme.textSecondary, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Everything you imported, ready to play or save offline',
            style: TextStyle(fontSize: 13, color: SymphonyTheme.textSecondary),
          ),
          const SizedBox(height: 16),

          if (featuredPlaylists.isEmpty)
            _EmptyPlaylistsCard(
              downloadedOnly: homeFilter == 'downloaded' && importedPlaylists.isNotEmpty,
            )
          else
            SizedBox(
              height: 275,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: featuredPlaylists.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final playlist = featuredPlaylists[index];
                  final isDownloaded = offlineState.isPlaylistDownloaded(playlist);

                  return SizedBox(
                    width: 185,
                    child: SpotifyPlaylistCard(
                      playlist: playlist,
                      accent: accent,
                      isDownloaded: isDownloaded,
                      onTap: () {
                        ref.read(activePlaylistProvider.notifier).state = playlist;
                        ref.read(navigationHistoryProvider.notifier).record('home', playlist);
                      },
                      onPlay: () {
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
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 36),

          // 6. Browse Genres & Moods
          const Text(
            'Browse Genres & Moods',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.4),
          ),
          const SizedBox(height: 4),
          const Text(
            'Current playlists from Spotify, Apple Music and YouTube',
            style: TextStyle(fontSize: 13, color: SymphonyTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth >= 900
                  ? 4
                  : constraints.maxWidth >= 600
                      ? 3
                      : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  mainAxisExtent: 96,
                ),
                itemCount: GenreCatalog.all.length,
                itemBuilder: (context, index) {
                  final card = GenreCatalog.all[index];
                  return _buildGenreCard(ref, card);
                },
              );
            },
          ),

          const SizedBox(height: 36),

          // 7. Import Playlist Action Banner
          _buildImportBanner(context, accent, !isDesktop),

          SizedBox(height: isDesktop ? 40 : 120),
        ],
      ),
    );
  }
}

/// Shown in place of the playlist shelf when there is nothing to list.
class _EmptyPlaylistsCard extends StatelessWidget {
  /// True when playlists exist but none are downloaded yet.
  final bool downloadedOnly;

  const _EmptyPlaylistsCard({required this.downloadedOnly});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: SymphonyTheme.card,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(
            downloadedOnly ? Icons.download_for_offline_outlined : Icons.library_music_outlined,
            color: SymphonyTheme.textSecondary,
            size: 36,
          ),
          const SizedBox(height: 12),
          Text(
            downloadedOnly ? 'Nothing downloaded yet' : 'Your library is empty',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            downloadedOnly
                ? 'Open a playlist and tap download to keep it on this device.'
                : 'Import a playlist from Spotify, YouTube or Apple Music, or search for a song to start listening.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: SymphonyTheme.textSecondary, fontSize: 13),
          ),
          if (!downloadedOnly) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => showDialog(context: context, builder: (_) => const ImportPlaylistDialog()),
              icon: const Icon(Icons.add_rounded, size: 18, color: Colors.black),
              label: const Text('Import a playlist', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(500)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
