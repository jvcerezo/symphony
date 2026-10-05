import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../audio_player/domain/entities/track.dart';
import '../../../audio_player/presentation/controllers/audio_player_providers.dart';
import '../../../audio_player/presentation/controllers/offline_provider.dart';
import '../../../audio_player/presentation/widgets/nav_history_controls.dart';
import '../../../audio_player/presentation/widgets/symphony_artwork.dart';
import '../../../audio_player/presentation/widgets/spotify_track_row.dart';

class SearchView extends ConsumerStatefulWidget {
  const SearchView({super.key});

  @override
  ConsumerState<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends ConsumerState<SearchView> {
  final _searchController = TextEditingController();

  static const _genres = [
    (title: 'Pop', color1: Color(0xFF8D67AB), color2: Color(0xFF8D67AB), icon: Icons.star),
    (title: 'Hip-Hop', color1: Color(0xFFBC5900), color2: Color(0xFFBC5900), icon: Icons.album),
    (title: 'Rock', color1: Color(0xFFE91429), color2: Color(0xFFE91429), icon: Icons.electric_bolt),
    (title: 'Lo-Fi Chill', color1: Color(0xFF503750), color2: Color(0xFF503750), icon: Icons.nightlife),
    (title: 'Synthwave', color1: Color(0xFF1E3264), color2: Color(0xFF1E3264), icon: Icons.graphic_eq),
    (title: 'Electronic', color1: Color(0xFFD84000), color2: Color(0xFFD84000), icon: Icons.headphones),
    (title: 'Acoustic', color1: Color(0xFF608108), color2: Color(0xFF608108), icon: Icons.music_note),
    (title: 'Gaming', color1: Color(0xFFE8115B), color2: Color(0xFFE8115B), icon: Icons.videogame_asset),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    ref.read(searchQueryProvider.notifier).state = val;
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final searchResultsAsync = ref.watch(searchResultsProvider);
    final mediaItemAsync = ref.watch(currentMediaItemStreamProvider);
    final playbackStateAsync = ref.watch(playbackStateStreamProvider);

    final mediaItem = mediaItemAsync.asData?.value;
    final playbackState = playbackStateAsync.asData?.value;
    final isPlaying = playbackState?.playing ?? false;
    final isBuffering = playbackState?.processingState == AudioProcessingState.buffering ||
        playbackState?.processingState == AudioProcessingState.loading;

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Search Header (Spotify Benchmark)
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 24,
            vertical: isMobile ? 10 : 16,
          ),
          color: SymphonyTheme.panel,
          child: Row(
            children: [
              if (!isMobile) ...[
                const NavHistoryControls(),
                const SizedBox(width: 12),
              ],
              if (query.isNotEmpty) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  tooltip: 'Back to Browse',
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: 'What do you want to play?',
                      hintStyle: const TextStyle(color: SymphonyTheme.textSecondary, fontSize: 14),
                      prefixIcon: const Icon(Icons.search, color: SymphonyTheme.textSecondary, size: 24),
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, color: SymphonyTheme.textSecondary),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF242424),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(500),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Main Content Area
        Expanded(
          child: query.isEmpty
              ? _buildGenreBrowser()
              : _buildSearchResults(searchResultsAsync, mediaItem, isPlaying, isBuffering),
        ),
      ],
    );
  }

  Widget _buildGenreBrowser() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Browse all',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisExtent: 110,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _genres.length,
            itemBuilder: (context, index) {
              final g = _genres[index];
              return InkWell(
                onTap: () {
                  _searchController.text = g.title;
                  _onSearchChanged(g.title);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: g.color1,
                  ),
                  child: Stack(
                    children: [
                      Text(
                        g.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Positioned(
                        right: -6,
                        bottom: -6,
                        child: Transform.rotate(
                          angle: 0.35,
                          child: Container(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(g.icon, size: 54, color: Colors.white.withOpacity(0.85)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(
    AsyncValue<List<Track>> resultsAsync,
    dynamic mediaItem,
    bool isPlaying,
    bool isBuffering,
  ) {
    final accent = ref.watch(accentThemeProvider);

    return resultsAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: accent.primary),
      ),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Search error: $e', style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                _searchController.clear();
                _onSearchChanged('');
              },
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back to Browse'),
              style: TextButton.styleFrom(foregroundColor: accent.primary),
            ),
          ],
        ),
      ),
      data: (tracks) {
        if (tracks.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No tracks found', style: TextStyle(color: SymphonyTheme.textMuted)),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back to Browse'),
                  style: TextButton.styleFrom(foregroundColor: accent.primary),
                ),
              ],
            ),
          );
        }

        final topTrack = tracks.first;
        final remainingTracks = tracks.length > 1 ? tracks.sublist(1) : <Track>[];
        final handler = ref.read(audioHandlerProvider);
        final offlineState = ref.watch(offlineProvider);
        final offlineNotifier = ref.read(offlineProvider.notifier);
        final isTopCurrent = mediaItem?.title == topTrack.title && mediaItem?.artist == topTrack.artist;

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          children: [
            // Top Result Card (Spotify benchmark)
            const Text(
              'Top result',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () {
                if (isTopCurrent) {
                  if (isPlaying) {
                    handler.pause();
                  } else {
                    handler.play();
                  }
                } else {
                  handler.playQueue(tracks, startIndex: 0);
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: SymphonyTheme.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.transparent),
                ),
                child: Row(
                  children: [
                    SymphonyArtwork(
                      track: topTrack,
                      size: 92,
                      borderRadius: 4,
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            topTrack.title,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: isTopCurrent ? accent.primary : Colors.white,
                              letterSpacing: -0.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF242424),
                                  borderRadius: BorderRadius.circular(500),
                                ),
                                child: const Text(
                                  'Song',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  topTrack.artist,
                                  style: const TextStyle(fontSize: 14, color: SymphonyTheme.textSecondary, fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.primary,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        (isTopCurrent && isPlaying) ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 30,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),

            // Songs List Header
            const Text(
              'Songs',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5),
            ),
            const SizedBox(height: 12),
            ...List.generate(remainingTracks.length, (idx) {
              final track = remainingTracks[idx];
              final isCurrent = mediaItem?.title == track.title && mediaItem?.artist == track.artist;
              final isDownloaded = offlineState.isTrackDownloaded(track);
              final isDownloading = offlineState.isTrackDownloading(track.id);

              return SpotifyTrackRow(
                index: idx + 1,
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
                onTap: () {
                  if (isCurrent) {
                    if (isPlaying) {
                      handler.pause();
                    } else {
                      handler.play();
                    }
                  } else {
                    handler.playQueue(tracks, startIndex: idx + 1);
                  }
                },
              );
            }),
            const SizedBox(height: 100),
          ],
        );
      },
    );
  }
}
