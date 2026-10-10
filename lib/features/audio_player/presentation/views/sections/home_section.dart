import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/curated_playlists.dart';
import '../../../../../core/theme/symphony_theme.dart';
import '../../../../../core/widgets/symphony_brand_logo.dart';
import '../../../../playlist_import/domain/entities/spotify_playlist.dart';
import '../../../../settings/presentation/controllers/personalization_provider.dart';
import '../../controllers/audio_player_providers.dart';
import '../../controllers/navigation_history_provider.dart';
import '../../controllers/offline_provider.dart';
import '../../widgets/import_playlist_dialog.dart';
import '../../widgets/nav_history_controls.dart';
import '../../widgets/spotify_playlist_card.dart';
import '../../widgets/spotify_quick_tile.dart';
import '../../widgets/spotify_track_row.dart';
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

  static const List<_GenreCardData> _genreCards = [
    _GenreCardData(
      title: 'Pop & Top Hits',
      gradientColors: [Color(0xFF8D137B), Color(0xFFE1306C)],
      icon: Icons.music_note_rounded,
      playlistId: '37i9dQZF1DXcBWIGoYBM5M',
    ),
    _GenreCardData(
      title: 'Chill & Lo-Fi',
      gradientColors: [Color(0xFF1E3264), Color(0xFF2E77D0)],
      icon: Icons.nightlife_rounded,
      playlistId: '37i9dQZF1DXdLEN7aqioXM',
    ),
    _GenreCardData(
      title: 'Rock Classics',
      gradientColors: [Color(0xFF8B0000), Color(0xFFE91E63)],
      icon: Icons.electric_bolt_rounded,
      playlistId: '37i9dQZF1DWXRqgorJj26U',
    ),
    _GenreCardData(
      title: 'Night Grooves',
      gradientColors: [Color(0xFF4A148C), Color(0xFF7B1FA2)],
      icon: Icons.dark_mode_rounded,
      playlistId: '37i9dQZF1DX6VdMW310YCv',
    ),
    _GenreCardData(
      title: 'Hip-Hop & Rap',
      gradientColors: [Color(0xFFBA5D00), Color(0xFFFF9800)],
      icon: Icons.album_rounded,
      searchQuery: 'Hip Hop',
    ),
    _GenreCardData(
      title: 'Focus & Study',
      gradientColors: [Color(0xFF0D7377), Color(0xFF14FFEC)],
      icon: Icons.headphones_rounded,
      playlistId: '37i9dQZF1DXdLEN7aqioXM',
    ),
    _GenreCardData(
      title: 'Workout & Energy',
      gradientColors: [Color(0xFFBF360C), Color(0xFFFF5722)],
      icon: Icons.fitness_center_rounded,
      searchQuery: 'Workout',
    ),
    _GenreCardData(
      title: 'Acoustic & Peace',
      gradientColors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
      icon: Icons.spa_rounded,
      searchQuery: 'Acoustic',
    ),
  ];

  String _getTimeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _buildHomeFilterChip(String label, String value, SymphonyAccent accent) {
    final isSelected = homeFilter == value;
    return GestureDetector(
      onTap: () => onHomeFilterChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : const Color(0xFF242424),
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

  Widget _buildGenreCard(WidgetRef ref, _GenreCardData card, List<SpotifyPlaylist> importedPlaylists) {
    return GestureDetector(
      onTap: () {
        if (card.playlistId != null) {
          final match = importedPlaylists.firstWhere(
            (p) => p.id == card.playlistId,
            orElse: () => CuratedPlaylists.all.firstWhere(
              (p) => p.id == card.playlistId,
              orElse: () => importedPlaylists.first,
            ),
          );
          ref.read(activePlaylistProvider.notifier).state = match;
          ref.read(navigationHistoryProvider.notifier).record('home', match);
        } else if (card.searchQuery != null) {
          ref.read(searchQueryProvider.notifier).state = card.searchQuery!;
          ref.read(activeNavTabProvider.notifier).state = 'search';
          ref.read(navigationHistoryProvider.notifier).record('search', null);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: card.gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
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
    final popularTracks = CuratedPlaylists.todaysTopHits.tracks.take(5).toList();

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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
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
                    Text(
                      personalization.displayTitle.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    PersonalizeButton(personalization: personalization, accent: accent),
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
                'Featured Playlists',
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
            'Handpicked collections ready for high-fidelity offline streaming',
            style: TextStyle(fontSize: 13, color: SymphonyTheme.textSecondary),
          ),
          const SizedBox(height: 16),

          if (featuredPlaylists.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF181818),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  'No downloaded playlists found yet. Tap download on any playlist to save offline.',
                  style: TextStyle(color: SymphonyTheme.textMuted, fontSize: 13),
                ),
              ),
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

          // 5. Popular Songs Right Now
          const Text(
            'Popular Right Now',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.4),
          ),
          const SizedBox(height: 4),
          const Text(
            'Jump straight into trending tracks',
            style: TextStyle(fontSize: 13, color: SymphonyTheme.textSecondary),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
            ),
            child: Column(
              children: [
                for (int i = 0; i < popularTracks.length; i++) ...[
                  SpotifyTrackRow(
                    index: i + 1,
                    track: popularTracks[i],
                    isPlaying: isPlaying && (mediaItem?.title == popularTracks[i].title && mediaItem?.artist == popularTracks[i].artist),
                    isCurrent: mediaItem?.title == popularTracks[i].title && mediaItem?.artist == popularTracks[i].artist,
                    isBuffering: isBuffering && (mediaItem?.title == popularTracks[i].title && mediaItem?.artist == popularTracks[i].artist),
                    isDownloaded: offlineState.isTrackDownloaded(popularTracks[i]),
                    isDownloading: offlineState.isTrackDownloading(popularTracks[i].id),
                    onDownload: () async {
                      final t = popularTracks[i];
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: SymphonyTheme.card,
                          content: Text('Downloading "${t.title}" for offline playback...'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                      final ok = await offlineNotifier.downloadTrack(t);
                      if (ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: SymphonyTheme.card,
                            content: Text('Saved "${t.title}" offline!'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    onTap: () async {
                      final t = popularTracks[i];
                      final isCurrent = mediaItem?.title == t.title && mediaItem?.artist == t.artist;
                      try {
                        if (isCurrent) {
                          if (isPlaying) {
                            await handler.pause();
                          } else {
                            await handler.play();
                          }
                        } else {
                          await handler.playQueue(popularTracks, startIndex: i);
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
                ],
              ],
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
            'Explore music tailored to your vibe',
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
                itemCount: _genreCards.length,
                itemBuilder: (context, index) {
                  final card = _genreCards[index];
                  return _buildGenreCard(ref, card, importedPlaylists);
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

class _GenreCardData {
  final String title;
  final List<Color> gradientColors;
  final IconData icon;
  final String? playlistId;
  final String? searchQuery;

  const _GenreCardData({
    required this.title,
    required this.gradientColors,
    required this.icon,
    this.playlistId,
    this.searchQuery,
  });
}
