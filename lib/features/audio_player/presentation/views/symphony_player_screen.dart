import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../metadata_search/presentation/views/search_view.dart';
import '../../../playlist_import/domain/entities/spotify_playlist.dart';
import '../controllers/audio_player_providers.dart';
import '../widgets/bottom_player_bar.dart';
import '../widgets/import_playlist_dialog.dart';
import '../widgets/sidebar_nav.dart';
import '../widgets/spotify_track_row.dart';

class SymphonyPlayerScreen extends ConsumerStatefulWidget {
  const SymphonyPlayerScreen({super.key});

  @override
  ConsumerState<SymphonyPlayerScreen> createState() => _SymphonyPlayerScreenState();
}

class _SymphonyPlayerScreenState extends ConsumerState<SymphonyPlayerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDefaultPlaylist());
  }

  Future<void> _initDefaultPlaylist() async {
    final active = ref.read(activePlaylistProvider);
    if (active != null) return;

    try {
      final importer = ref.read(universalPlaylistImporterProvider);
      final playlist = await importer.importPlaylist('37i9dQZF1DXcBWIGoYBM5M');
      if (mounted) {
        ref.read(importedPlaylistsProvider.notifier).addPlaylist(playlist);
        ref.read(activePlaylistProvider.notifier).state = playlist;
      }
    } catch (_) {
      // Gracefully handled by scraper fallback
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePlaylist = ref.watch(activePlaylistProvider);
    final activeTab = ref.watch(activeNavTabProvider);
    final mediaItemAsync = ref.watch(currentMediaItemStreamProvider);
    final playbackStateAsync = ref.watch(playbackStateStreamProvider);

    final mediaItem = mediaItemAsync.asData?.value;
    final playbackState = playbackStateAsync.asData?.value;
    final isPlaying = playbackState?.playing ?? false;

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
                ref.read(activeNavTabProvider.notifier).state = tab;
              },
              backgroundColor: SymphonyTheme.obsidian,
              selectedItemColor: SymphonyTheme.primaryLight,
              unselectedItemColor: SymphonyTheme.textSecondary,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
                BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
                BottomNavigationBarItem(icon: Icon(Icons.library_music), label: 'Your Library'),
              ],
            )
          : null,
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                if (isDesktop) const SidebarNav(),
                Expanded(
                  child: Container(
                    color: SymphonyTheme.midnight,
                    child: _buildCurrentTabContent(activeTab, activePlaylist, mediaItem, isPlaying, isDesktop),
                  ),
                ),
              ],
            ),
          ),
          const BottomPlayerBar(),
        ],
      ),
    );
  }

  Widget _buildCurrentTabContent(
    String activeTab,
    SpotifyPlaylist? activePlaylist,
    MediaItem? mediaItem,
    bool isPlaying,
    bool isDesktop,
  ) {
    if (activeTab == 'search') {
      return const SearchView();
    }

    if (activeTab == 'library') {
      return _buildLibraryView();
    }

    // Default 'home' tab
    if (activePlaylist == null) {
      return _buildLoadingState();
    }

    return _buildPlaylistContent(activePlaylist, mediaItem, isPlaying, isDesktop);
  }

  Widget _buildLibraryView() {
    final importedPlaylists = ref.watch(importedPlaylistsProvider);

    return Padding(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Your Library',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  showDialog(context: context, builder: (_) => const ImportPlaylistDialog());
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: SymphonyTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Import Playlist'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (importedPlaylists.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 80.0),
                child: Text('No playlists imported yet', style: TextStyle(color: SymphonyTheme.textMuted)),
              ),
            )
          else
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisExtent: 260,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: importedPlaylists.length,
                itemBuilder: (context, index) {
                  final playlist = importedPlaylists[index];
                  return InkWell(
                    onTap: () {
                      ref.read(activePlaylistProvider.notifier).state = playlist;
                      ref.read(activeNavTabProvider.notifier).state = 'home';
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: SymphonyTheme.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: SymphonyTheme.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: playlist.coverUrl != null
                                ? Image.network(
                                    playlist.coverUrl!,
                                    width: double.infinity,
                                    height: 150,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.high,
                                    errorBuilder: (context, error, stackTrace) => _buildFallbackCover(),
                                  )
                                : _buildFallbackCover(),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            playlist.title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${playlist.trackCount} songs • By ${playlist.ownerName ?? "Spotify"}',
                            style: const TextStyle(fontSize: 12, color: SymphonyTheme.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SymphonyTheme.brandGradient,
            ),
            child: const Icon(Icons.graphic_eq, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 18),
          const Text(
            'Loading Symphony Player...',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Text(
            'Instant zero-login streaming experience',
            style: TextStyle(fontSize: 13, color: SymphonyTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistContent(
    SpotifyPlaylist playlist,
    MediaItem? mediaItem,
    bool isPlaying,
    bool isDesktop,
  ) {
    final handler = ref.read(audioHandlerProvider);

    final isPlaylistActive = playlist.tracks.any((t) => t.title == mediaItem?.title && t.artist == mediaItem?.artist);
    final isThisPlaying = isPlaylistActive && isPlaying;

    return CustomScrollView(
      slivers: [
        // Top Bar & Hero Header
        SliverToBoxAdapter(
          child: Container(
            decoration: const BoxDecoration(
              gradient: SymphonyTheme.heroGradient,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 32 : 16,
              vertical: isDesktop ? 32 : 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Navigation / Action header
                Row(
                  children: [
                    if (!isDesktop) ...[
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: SymphonyTheme.secondary),
                        tooltip: 'Import Playlist',
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => const ImportPlaylistDialog(),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'SYMPHONY',
                        style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 18),
                      ),
                      const Spacer(),
                    ],
                    if (isDesktop) ...[
                      IconButton(
                        icon: const Icon(Icons.add_link, color: SymphonyTheme.secondary),
                        tooltip: 'Import Playlist',
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => const ImportPlaylistDialog(),
                          );
                        },
                      ),
                      const Spacer(),
                    ],
                  ],
                ),
                const SizedBox(height: 24),

                // Hero Content
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: isDesktop ? 190 : 130,
                      height: isDesktop ? 190 : 130,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(140),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
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
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${playlist.source.toUpperCase()} PLAYLIST',
                            style: const TextStyle(
                              color: SymphonyTheme.primaryLight,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            playlist.title,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isDesktop ? 40 : 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(
                                playlist.ownerName ?? 'Spotify',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const Text(' • ', style: TextStyle(color: SymphonyTheme.textMuted)),
                              Text(
                                '${playlist.trackCount} songs',
                                style: const TextStyle(color: SymphonyTheme.textSecondary, fontSize: 13),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // Action Bar: Big Play Button
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SymphonyTheme.brandGradient,
                        boxShadow: isThisPlaying
                            ? [
                                BoxShadow(
                                  color: SymphonyTheme.primary.withAlpha(160),
                                  blurRadius: 18,
                                  spreadRadius: 2,
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: Colors.black.withAlpha(80),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                      ),
                      child: IconButton(
                        iconSize: 32,
                        tooltip: isThisPlaying ? 'Pause' : 'Play',
                        icon: Icon(
                          isThisPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
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
                    const SizedBox(width: 20),
                    IconButton(
                      iconSize: 28,
                      icon: const Icon(Icons.favorite_border, color: SymphonyTheme.textSecondary),
                      onPressed: () {},
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      iconSize: 24,
                      icon: const Icon(Icons.more_horiz, color: SymphonyTheme.textSecondary),
                      onPressed: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Track Table Header
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 32 : 16,
              vertical: 12,
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    '#',
                    style: TextStyle(color: SymphonyTheme.textMuted, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(width: 12),
                SizedBox(width: 44),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'TITLE',
                    style: TextStyle(color: SymphonyTheme.textMuted, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                  ),
                ),
                SizedBox(width: 48),
                Icon(Icons.access_time, size: 16, color: SymphonyTheme.textMuted),
              ],
            ),
          ),
        ),

        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
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

                return SpotifyTrackRow(
                  index: index,
                  track: track,
                  isPlaying: isPlaying,
                  isCurrent: isCurrent,
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

        const SliverToBoxAdapter(
          child: SizedBox(height: 40),
        ),
      ],
    );
  }

  Widget _buildFallbackCover() {
    return Container(
      color: SymphonyTheme.card,
      child: const Icon(Icons.music_note, color: SymphonyTheme.textMuted, size: 48),
    );
  }
}
