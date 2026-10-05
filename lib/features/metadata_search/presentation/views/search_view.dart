import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../audio_player/domain/entities/track.dart';
import '../../../audio_player/presentation/controllers/audio_player_providers.dart';
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
    (title: 'Pop', color1: Color(0xFF8B5CF6), color2: Color(0xFFEC4899), icon: Icons.star),
    (title: 'Hip-Hop', color1: Color(0xFFF97316), color2: Color(0xFFEF4444), icon: Icons.album),
    (title: 'Rock', color1: Color(0xFFDC2626), color2: Color(0xFF7F1D1D), icon: Icons.electric_bolt),
    (title: 'Lo-Fi Chill', color1: Color(0xFF0D9488), color2: Color(0xFF10B981), icon: Icons.nightlife),
    (title: 'Synthwave', color1: Color(0xFF6366F1), color2: Color(0xFFA855F7), icon: Icons.graphic_eq),
    (title: 'Electronic', color1: Color(0xFF06B6D4), color2: Color(0xFF3B82F6), icon: Icons.headphones),
    (title: 'Acoustic', color1: Color(0xFFD97706), color2: Color(0xFFB45309), icon: Icons.music_note),
    (title: 'Gaming', color1: Color(0xFFEC4899), color2: Color(0xFF8B5CF6), icon: Icons.videogame_asset),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Search Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          color: SymphonyTheme.obsidian,
          child: Row(
            children: [
              if (query.isNotEmpty) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  tooltip: 'Back to Explore Genres',
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'What do you want to play?',
                    hintStyle: const TextStyle(color: SymphonyTheme.textMuted),
                    prefixIcon: const Icon(Icons.search, color: SymphonyTheme.textSecondary, size: 22),
                    suffixIcon: query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, color: SymphonyTheme.textMuted),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: SymphonyTheme.card,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
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
            'Explore Genres',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisExtent: 120,
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
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      colors: [g.color1, g.color2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: g.color1.withAlpha(60),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
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
                        right: -4,
                        bottom: -4,
                        child: Transform.rotate(
                          angle: 0.3,
                          child: Icon(g.icon, size: 48, color: Colors.white.withAlpha(60)),
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
    return resultsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: SymphonyTheme.primaryLight),
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
              label: const Text('Back to Explore Genres'),
              style: TextButton.styleFrom(foregroundColor: SymphonyTheme.primaryLight),
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
                  label: const Text('Back to Explore Genres'),
                  style: TextButton.styleFrom(foregroundColor: SymphonyTheme.primaryLight),
                ),
              ],
            ),
          );
        }

        final topTrack = tracks.first;
        final remainingTracks = tracks.length > 1 ? tracks.sublist(1) : <Track>[];
        final handler = ref.read(audioHandlerProvider);

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          children: [
            // Back breadcrumb button
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  _searchController.clear();
                  _onSearchChanged('');
                },
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('Back to Explore Genres', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                  foregroundColor: SymphonyTheme.primaryLight,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Top Result Card
            const Text(
              'Top Result',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () {
                final isTopCurrent = mediaItem?.title == topTrack.title && mediaItem?.artist == topTrack.artist;
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
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: SymphonyTheme.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SymphonyTheme.divider),
                ),
                child: Row(
                  children: [
                    SymphonyArtwork(
                      track: topTrack,
                      size: 80,
                      borderRadius: 8,
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            topTrack.title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            topTrack.artist,
                            style: const TextStyle(fontSize: 14, color: SymphonyTheme.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: SymphonyTheme.surface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'SONG',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SymphonyTheme.brandGradient,
                      ),
                      child: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Songs List
            const Text(
              'Songs',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            ...List.generate(remainingTracks.length, (idx) {
              final track = remainingTracks[idx];
              final isCurrent = mediaItem?.title == track.title && mediaItem?.artist == track.artist;

              return SpotifyTrackRow(
                index: idx + 1,
                track: track,
                isPlaying: isPlaying && !isBuffering,
                isBuffering: isCurrent && isBuffering,
                isCurrent: isCurrent,
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
          ],
        );
      },
    );
  }
}
