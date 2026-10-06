import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/curated_playlists.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../../core/widgets/app_update_dialog.dart';
import '../../../../core/widgets/symphony_brand_logo.dart';
import '../../../metadata_search/presentation/views/search_view.dart';
import '../../../playlist_import/domain/entities/spotify_playlist.dart';
import '../../../settings/presentation/controllers/personalization_provider.dart';
import '../../../settings/presentation/widgets/personalization_dialog.dart';
import '../../data/services/symphony_audio_handler.dart';
import '../controllers/audio_player_providers.dart';
import '../controllers/offline_provider.dart';
import '../controllers/navigation_history_provider.dart';
import '../widgets/bottom_player_bar.dart';
import '../widgets/import_playlist_dialog.dart';
import '../widgets/nav_history_controls.dart';
import '../widgets/realtime_download_toast.dart';
import '../widgets/sidebar_nav.dart';
import '../widgets/spotify_track_row.dart';

class SymphonyPlayerScreen extends ConsumerStatefulWidget {
  final bool isWebDemoMode;
  const SymphonyPlayerScreen({super.key, this.isWebDemoMode = false});

  @override
  ConsumerState<SymphonyPlayerScreen> createState() => _SymphonyPlayerScreenState();
}

class _SymphonyPlayerScreenState extends ConsumerState<SymphonyPlayerScreen> {
  String _homeFilter = 'all'; // 'all' | 'music' | 'downloaded'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDefaultPlaylist());
  }

  Future<void> _initDefaultPlaylist() async {
    final active = ref.read(activePlaylistProvider);
    ref.read(navigationHistoryProvider.notifier).record('home', active);

    // Proactively pre-warm top starter tracks so pressing Play starts in < 300ms
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (!isTest) {
      try {
        final handler = ref.read(audioHandlerProvider);
        final topTracks = CuratedPlaylists.todaysTopHits.tracks.take(4).toList();
        handler.preloadTracks(topTracks, count: 4);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(activeNavTabProvider, (prev, next) {
      if (prev != next) {
        final p = ref.read(activePlaylistProvider);
        ref.read(navigationHistoryProvider.notifier).record(next, p);
      }
    });

    ref.listen<SpotifyPlaylist?>(activePlaylistProvider, (prev, next) {
      if (prev?.id != next?.id) {
        final tab = ref.read(activeNavTabProvider);
        ref.read(navigationHistoryProvider.notifier).record(tab, next);

        // Pre-warm top tracks of the selected playlist
        final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
        if (!isTest && next != null && next.tracks.isNotEmpty) {
          try {
            final handler = ref.read(audioHandlerProvider);
            handler.preloadTracks(next.tracks, count: 2);
          } catch (_) {}
        }
      }
    });

    final activePlaylist = ref.watch(activePlaylistProvider);
    final activeTab = ref.watch(activeNavTabProvider);
    final mediaItemAsync = ref.watch(currentMediaItemStreamProvider);
    final playbackStateAsync = ref.watch(playbackStateStreamProvider);

    final mediaItem = mediaItemAsync.asData?.value;
    final playbackState = playbackStateAsync.asData?.value;
    final isPlaying = playbackState?.playing ?? false;
    final isBuffering = playbackState?.processingState == AudioProcessingState.buffering ||
        playbackState?.processingState == AudioProcessingState.loading;

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 850;

    return Scaffold(
      backgroundColor: SymphonyTheme.obsidian,
      bottomNavigationBar: !isDesktop
          ? BottomNavigationBar(
              currentIndex: activeTab == 'home'
                  ? 0
                  : activeTab == 'search'
                      ? 1
                      : 2,
              onTap: (idx) {
                final tab = idx == 0
                    ? 'home'
                    : idx == 1
                        ? 'search'
                        : 'library';
                if (tab == 'home') {
                  ref.read(activePlaylistProvider.notifier).state = null;
                }
                ref.read(activeNavTabProvider.notifier).state = tab;
                ref.read(navigationHistoryProvider.notifier).record(tab, tab == 'home' ? null : ref.read(activePlaylistProvider));
              },
              backgroundColor: SymphonyTheme.obsidian,
              selectedItemColor: Colors.white,
              unselectedItemColor: SymphonyTheme.textSecondary,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(Icons.search_rounded), label: 'Search'),
                BottomNavigationBarItem(icon: Icon(Icons.library_music_rounded), label: 'Your Library'),
              ],
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppUpdateBanner(
              onDismiss: () => ref.read(appUpdateProvider.notifier).markUserNotified(),
            ),
            Expanded(
              child: Stack(
                children: [
                  Padding(
                    padding: isDesktop ? const EdgeInsets.fromLTRB(8, 8, 8, 0) : EdgeInsets.zero,
                    child: Row(
                      children: [
                        if (isDesktop) const SidebarNav(),
                        if (isDesktop) const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: isDesktop ? BorderRadius.circular(8) : BorderRadius.zero,
                            child: Container(
                              color: SymphonyTheme.panel,
                              child: _buildCurrentTabContent(activeTab, activePlaylist, mediaItem, isPlaying, isBuffering, isDesktop),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Real-time live download toast overlay
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 8,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: const RealtimeDownloadToast(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const BottomPlayerBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTabContent(
    String activeTab,
    SpotifyPlaylist? activePlaylist,
    MediaItem? mediaItem,
    bool isPlaying,
    bool isBuffering,
    bool isDesktop,
  ) {
    if (activeTab == 'search') {
      return const SearchView();
    }

    if (activeTab == 'library') {
      return _buildLibraryView(isDesktop);
    }

    // Default 'home' tab
    if (activePlaylist == null) {
      return _buildHomeDashboard(isDesktop, mediaItem, isPlaying, isBuffering);
    }

    return _buildPlaylistContent(activePlaylist, mediaItem, isPlaying, isBuffering, isDesktop);
  }

  Widget _buildPersonalizeButton(PersonalizationState personalization, SymphonyAccent accent) {
    return InkWell(
      onTap: () => showDialog(context: context, builder: (_) => const PersonalizationDialog()),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF282828),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF404040)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline_rounded, size: 16, color: accent.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                personalization.displayName,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportButton() {
    return ElevatedButton.icon(
      onPressed: () {
        showDialog(context: context, builder: (_) => const ImportPlaylistDialog());
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(500)),
      ),
      icon: const Icon(Icons.add, size: 16, color: Colors.black),
      label: const Text(
        'Import Playlist',
        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }

  Widget _buildLibraryView(bool isDesktop) {
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
                    _buildPersonalizeButton(personalization, accent),
                    const SizedBox(width: 12),
                    _buildImportButton(),
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
                    Expanded(child: _buildPersonalizeButton(personalization, accent)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildImportButton()),
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
                  return _SpotifyPlaylistCard(
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
    final isSelected = _homeFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _homeFilter = value),
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

  Widget _buildGenreCard(_GenreCardData card, List<SpotifyPlaylist> importedPlaylists) {
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

  Widget _buildImportBanner(SymphonyAccent accent, bool isMobile) {
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

  Widget _buildHomeDashboard(
    bool isDesktop,
    MediaItem? mediaItem,
    bool isPlaying,
    bool isBuffering,
  ) {
    final importedPlaylists = ref.watch(importedPlaylistsProvider);
    final personalization = ref.watch(personalizationProvider);
    final accent = ref.watch(accentThemeProvider);
    final offlineState = ref.watch(offlineProvider);
    final offlineNotifier = ref.read(offlineProvider.notifier);
    final handler = ref.read(audioHandlerProvider);

    var filteredPlaylists = importedPlaylists;
    if (_homeFilter == 'downloaded') {
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
                    _buildPersonalizeButton(personalization, accent),
                    const SizedBox(width: 12),
                    _buildImportButton(),
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
                    _buildPersonalizeButton(personalization, accent),
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

                    return _SpotifyQuickTile(
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
                    child: _SpotifyPlaylistCard(
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
                      if (ok && mounted) {
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
                        if (mounted) {
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
                  return _buildGenreCard(card, importedPlaylists);
                },
              );
            },
          ),

          const SizedBox(height: 36),

          // 7. Import Playlist Action Banner
          _buildImportBanner(accent, !isDesktop),

          SizedBox(height: isDesktop ? 40 : 120),
        ],
      ),
    );
  }

  Widget _buildPlaylistContent(
    SpotifyPlaylist playlist,
    MediaItem? mediaItem,
    bool isPlaying,
    bool isBuffering,
    bool isDesktop,
  ) {
    final handler = ref.read(audioHandlerProvider);
    final offlineState = ref.watch(offlineProvider);
    final offlineNotifier = ref.read(offlineProvider.notifier);
    final accent = ref.watch(accentThemeProvider);

    final isPlaylistActive = playlist.tracks.any((t) => t.title == mediaItem?.title && t.artist == mediaItem?.artist);
    final isThisPlaying = isPlaylistActive && isPlaying;
    final isPlaylistDownloaded = offlineState.isPlaylistDownloaded(playlist);
    final isPlaylistDownloading = offlineState.isPlaylistDownloading(playlist.id);

    return CustomScrollView(
      slivers: [
        // Top Bar & Hero Header
        SliverToBoxAdapter(
          child: _buildHeroHeader(
            playlist,
            accent,
            isThisPlaying,
            isPlaylistActive,
            isPlaylistDownloaded,
            isPlaylistDownloading,
            isDesktop,
            handler,
            offlineNotifier,
          ),
        ),

        // Track Table Header (Desktop Only)
        if (isDesktop)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 32,
                    child: Text(
                      '#',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: SymphonyTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const SizedBox(width: 40),
                  const SizedBox(width: 14),
                  const Expanded(
                    flex: 4,
                    child: Text(
                      'Title',
                      style: TextStyle(color: SymphonyTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    flex: 3,
                    child: Text(
                      'Album',
                      style: TextStyle(color: SymphonyTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 48),
                  const SizedBox(
                    width: 44,
                    child: Icon(Icons.access_time_outlined, size: 16, color: SymphonyTheme.textSecondary),
                  ),
                  const SizedBox(width: 32),
                ],
              ),
            ),
          ),

        if (isDesktop)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.0),
              child: Divider(color: SymphonyTheme.divider, height: 1),
            ),
          ),

        // Track List Rows
        SliverPadding(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 24 : 8,
            vertical: 8,
          ),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, index) {
                final track = playlist.tracks[index];
                final isCurrent = mediaItem?.title == track.title && mediaItem?.artist == track.artist;
                final isDownloaded = offlineState.isTrackDownloaded(track);
                final isDownloading = offlineState.isTrackDownloading(track.id);

                return SpotifyTrackRow(
                  index: index,
                  track: track,
                  isPlaying: isPlaying && !isBuffering,
                  isBuffering: isCurrent && isBuffering,
                  isCurrent: isCurrent,
                  isDownloaded: isDownloaded,
                  isDownloading: isDownloading,
                  onDownload: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.showSnackBar(
                      SnackBar(
                        backgroundColor: SymphonyTheme.card,
                        content: Text('Downloading "${track.title}" for offline playback...'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                    final ok = await offlineNotifier.downloadTrack(track);
                    if (ok && mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          backgroundColor: SymphonyTheme.card,
                          content: Text('Saved "${track.title}" offline!'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  onTap: () async {
                    try {
                      if (isCurrent) {
                        if (isPlaying) {
                          await handler.pause();
                        } else {
                          await handler.play();
                        }
                      } else {
                        await handler.playQueue(playlist.tracks, startIndex: index);
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: SymphonyTheme.card,
                            content: Text('Playback error: $e', style: const TextStyle(color: Colors.redAccent)),
                          ),
                        );
                      }
                    }
                  },
                );
              },
              childCount: playlist.tracks.length,
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: SizedBox(height: isDesktop ? 40 : 110),
        ),
      ],
    );
  }

  Widget _buildHeroHeader(
    SpotifyPlaylist playlist,
    SymphonyAccent accent,
    bool isThisPlaying,
    bool isPlaylistActive,
    bool isPlaylistDownloaded,
    bool isPlaylistDownloading,
    bool isDesktop,
    SymphonyAudioHandler handler,
    OfflineManagerNotifier offlineNotifier,
  ) {
    if (!isDesktop) {
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
                          errorBuilder: (context, error, stackTrace) => _buildFallbackCover(),
                        )
                      : _buildFallbackCover(),
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

    // Desktop Hero Layout
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
                          errorBuilder: (context, error, stackTrace) => _buildFallbackCover(),
                        )
                      : _buildFallbackCover(),
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
                        if (mounted) {
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

  Widget _buildFallbackCover() {
    return Container(
      color: SymphonyTheme.card,
      child: const Icon(Icons.music_note, color: SymphonyTheme.textMuted, size: 48),
    );
  }
}

class _SpotifyPlaylistCard extends StatefulWidget {
  final SpotifyPlaylist playlist;
  final SymphonyAccent accent;
  final bool isDownloaded;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback? onDownload;
  final VoidCallback? onUninstall;
  final VoidCallback? onDelete;

  const _SpotifyPlaylistCard({
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
  State<_SpotifyPlaylistCard> createState() => _SpotifyPlaylistCardState();
}

class _SpotifyPlaylistCardState extends State<_SpotifyPlaylistCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final playlist = widget.playlist;
    final isMobile = MediaQuery.of(context).size.width < 700;
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
                              errorBuilder: (_, _, _) => Container(
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

class _SpotifyQuickTile extends StatefulWidget {
  final SpotifyPlaylist playlist;
  final SymphonyAccent accent;
  final bool isPlaying;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  const _SpotifyQuickTile({
    required this.playlist,
    required this.accent,
    required this.isPlaying,
    required this.isCurrent,
    required this.onTap,
    required this.onPlay,
  });

  @override
  State<_SpotifyQuickTile> createState() => _SpotifyQuickTileState();
}

class _SpotifyQuickTileState extends State<_SpotifyQuickTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
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


