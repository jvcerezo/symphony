import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/symphony_theme.dart';
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
    // Pre-populate with default Spotify curated playlist if empty
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDefaultPlaylist());
  }

  Future<void> _initDefaultPlaylist() async {
    final active = ref.read(activePlaylistProvider);
    if (active != null) return;

    try {
      final scraper = ref.read(spotifyScraperProvider);
      // Auto-load Today's Top Hits public playlist
      final playlist = await scraper.importPlaylist('37i9dQZF1DXcBWIGoYBM5M');
      if (mounted) {
        ref.read(importedPlaylistsProvider.notifier).addPlaylist(playlist);
        ref.read(activePlaylistProvider.notifier).state = playlist;
      }
    } catch (_) {
      // Offline or network error gracefully handled
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePlaylist = ref.watch(activePlaylistProvider);
    final mediaItemAsync = ref.watch(currentMediaItemStreamProvider);
    final playbackStateAsync = ref.watch(playbackStateStreamProvider);

    final mediaItem = mediaItemAsync.asData?.value;
    final playbackState = playbackStateAsync.asData?.value;
    final isPlaying = playbackState?.playing ?? false;

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 850;

    return Scaffold(
      backgroundColor: SymphonyTheme.obsidian,
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                if (isDesktop) const SidebarNav(),
                Expanded(
                  child: Container(
                    color: SymphonyTheme.midnight,
                    child: activePlaylist == null
                        ? _buildLoadingState()
                        : _buildPlaylistContent(activePlaylist, mediaItem, isPlaying, isDesktop),
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
            'Importing Spotify Showcase...',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Text(
            'Extracting tracks directly on-device with zero logins',
            style: TextStyle(fontSize: 13, color: SymphonyTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              showDialog(context: context, builder: (_) => const ImportPlaylistDialog());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: SymphonyTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.link, size: 18),
            label: const Text('Paste Spotify Link Manually'),
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
                        tooltip: 'Import Spotify Playlist',
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
                        tooltip: 'Import Spotify Link',
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
                    // Playlist Artwork with drop shadow
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
                                errorBuilder: (context, error, stackTrace) => _buildFallbackCover(),
                              )
                            : _buildFallbackCover(),
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Metadata
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PUBLIC PLAYLIST',
                            style: TextStyle(
                              color: SymphonyTheme.textPrimary,
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
                    Container(
                      width: 54,
                      height: 54,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SymphonyTheme.brandGradient,
                      ),
                      child: IconButton(
                        iconSize: 30,
                        icon: const Icon(Icons.play_arrow, color: Colors.white),
                        onPressed: () {
                          handler.playQueue(playlist.tracks, startIndex: 0);
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
              (context, index) {
                final track = playlist.tracks[index];
                final isCurrent = mediaItem?.title == track.title && mediaItem?.artist == track.artist;

                return SpotifyTrackRow(
                  index: index,
                  track: track,
                  isPlaying: isPlaying,
                  isCurrent: isCurrent,
                  onTap: () {
                    handler.playQueue(playlist.tracks, startIndex: index);
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
