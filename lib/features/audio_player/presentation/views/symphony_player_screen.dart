import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../metadata_search/presentation/views/search_view.dart';
import '../../../playlist_import/domain/entities/spotify_playlist.dart';
import '../../data/services/symphony_audio_handler.dart';
import '../controllers/audio_player_providers.dart';
import '../controllers/offline_provider.dart';
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
                ref.read(activeNavTabProvider.notifier).state = tab;
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
      body: Column(
        children: [
          Expanded(
            child: Padding(
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
    bool isBuffering,
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

    return _buildPlaylistContent(activePlaylist, mediaItem, isPlaying, isBuffering, isDesktop);
  }

  Widget _buildLibraryView() {
    final importedPlaylists = ref.watch(importedPlaylistsProvider);
    final handler = ref.read(audioHandlerProvider);

    return Padding(
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Playlists',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  showDialog(context: context, builder: (_) => const ImportPlaylistDialog());
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(500)),
                ),
                icon: const Icon(Icons.add, size: 18, color: Colors.black),
                label: const Text(
                  'Import Playlist',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (importedPlaylists.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No playlists imported yet', style: TextStyle(color: SymphonyTheme.textMuted)),
              ),
            )
          else
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisExtent: 280,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: importedPlaylists.length,
                itemBuilder: (context, index) {
                  final playlist = importedPlaylists[index];
                  final accent = ref.watch(accentThemeProvider);
                  return _SpotifyPlaylistCard(
                    playlist: playlist,
                    accent: accent,
                    onTap: () {
                      ref.read(activePlaylistProvider.notifier).state = playlist;
                      ref.read(activeNavTabProvider.notifier).state = 'home';
                    },
                    onPlay: () {
                      ref.read(activePlaylistProvider.notifier).state = playlist;
                      handler.playQueue(playlist.tracks, startIndex: 0);
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    final accent = ref.watch(accentThemeProvider);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.primary,
            ),
            child: const Icon(Icons.graphic_eq_rounded, color: Colors.black, size: 30),
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

        const SliverToBoxAdapter(
          child: SizedBox(height: 40),
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
                const Text(
                  'PLAYLIST',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
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
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x7F000000),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.chevron_left, color: Colors.white, size: 22),
                  onPressed: () {},
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x7F000000),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.chevron_right, color: Colors.white, size: 22),
                  onPressed: () {},
                ),
              ),
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
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.showSnackBar(
                    SnackBar(
                      backgroundColor: SymphonyTheme.card,
                      content: Row(
                        children: [
                          Icon(Icons.cloud_download, color: accent.primary, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Downloading "${playlist.title}" (${playlist.tracks.length} songs) for offline listening...',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      duration: const Duration(seconds: 4),
                    ),
                  );
                  await offlineNotifier.downloadPlaylist(playlist);
                },
              ),
              const SizedBox(width: 16),
              IconButton(
                iconSize: 30,
                tooltip: 'More options',
                icon: const Icon(Icons.more_horiz, color: SymphonyTheme.textSecondary),
                onPressed: () {},
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
  final VoidCallback onTap;
  final VoidCallback onPlay;

  const _SpotifyPlaylistCard({
    required this.playlist,
    required this.accent,
    required this.onTap,
    required this.onPlay,
  });

  @override
  State<_SpotifyPlaylistCard> createState() => _SpotifyPlaylistCardState();
}

class _SpotifyPlaylistCardState extends State<_SpotifyPlaylistCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final playlist = widget.playlist;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isHovered ? SymphonyTheme.cardHover : SymphonyTheme.card,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover with hover play button
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
                              errorBuilder: (_, __, ___) => Container(
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
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: AnimatedOpacity(
                      opacity: _isHovered ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: AnimatedSlide(
                        offset: _isHovered ? Offset.zero : const Offset(0, 0.25),
                        duration: const Duration(milliseconds: 200),
                        child: GestureDetector(
                          onTap: widget.onPlay,
                          child: Container(
                            width: 48,
                            height: 48,
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
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 30),
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

