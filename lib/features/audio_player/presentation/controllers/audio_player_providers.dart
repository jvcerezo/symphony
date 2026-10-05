import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../metadata_search/data/services/artwork_resolver_service.dart';
import '../../../metadata_search/data/services/search_service.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../playlist_import/data/services/spotify_embed_scraper_service.dart';
import '../../../playlist_import/data/services/universal_playlist_importer_service.dart';
import '../../../playlist_import/domain/entities/spotify_playlist.dart';
import '../../data/services/symphony_audio_handler.dart';
import '../../domain/entities/track.dart';

/// Symphony Brand & User Accent Theme Provider (Defaults to signature Symphony Violet #8B5CF6)
final accentThemeProvider = StateProvider<SymphonyAccent>((ref) => SymphonyTheme.violet);

/// Global provider for the Symphony AudioHandler instance
final audioHandlerProvider = Provider<SymphonyAudioHandler>((ref) {
  throw UnimplementedError('audioHandlerProvider must be overridden with the initialized instance');
});

/// Stream provider for reactive playback state changes (playing, buffering, position)
final playbackStateStreamProvider = StreamProvider<PlaybackState>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.playbackState;
});

/// Stream provider for current active media item (title, artist, artwork)
final currentMediaItemStreamProvider = StreamProvider<MediaItem?>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.mediaItem;
});

/// Stream provider for current queue index
final currentQueueIndexStreamProvider = StreamProvider<int>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.currentIndexStream;
});

/// Stream provider for active queue tracks
final currentQueueListStreamProvider = StreamProvider<List<Track>>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.playlistQueueStream;
});

/// Provider for the shared high-resolution ArtworkResolverService instance
final artworkResolverProvider = Provider<ArtworkResolverService>((ref) {
  final service = ArtworkResolverService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for the unauthenticated Spotify Embed Scraper
final spotifyScraperProvider = Provider<SpotifyEmbedScraperService>((ref) {
  final resolver = ref.watch(artworkResolverProvider);
  final service = SpotifyEmbedScraperService(artworkResolver: resolver);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for multi-source playlist importing (Spotify, YouTube, Deezer, Apple Music, Smart Mix)
final universalPlaylistImporterProvider = Provider<UniversalPlaylistImporterService>((ref) {
  final resolver = ref.watch(artworkResolverProvider);
  final spotify = ref.watch(spotifyScraperProvider);
  final service = UniversalPlaylistImporterService(
    artworkResolver: resolver,
    spotifyScraper: spotify,
  );
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for unauthenticated iTunes / Deezer search
final searchServiceProvider = Provider<SearchService>((ref) {
  final service = SearchService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// StateNotifier for managing imported Spotify playlists with offline persistence
class ImportedPlaylistsNotifier extends StateNotifier<List<SpotifyPlaylist>> {
  final http.Client _client = http.Client();

  ImportedPlaylistsNotifier() : super([]) {
    _loadSavedPlaylists();
  }

  Future<void> _loadSavedPlaylists() async {
    final candidateHosts = <String>[];
    if (kIsWeb) {
      try {
        final origin = Uri.base.origin;
        if (origin.isNotEmpty && !origin.startsWith('null')) {
          candidateHosts.add(origin);
        }
      } catch (_) {}
    }
    for (final host in [
      'https://symphony.jettimothycerezo.dev',
      'http://192.168.1.57:8080',
      'http://localhost:8080',
    ]) {
      if (!candidateHosts.contains(host)) candidateHosts.add(host);
    }

    for (final origin in candidateHosts) {
      try {
        final response = await _client.get(Uri.parse('$origin/api/playlists')).timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>;
        final playlists = <SpotifyPlaylist>[];
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            final rawTracks = item['tracks'] as List<dynamic>? ?? [];
            final tracks = rawTracks.map((t) {
              final durMs = t['durationMs'] as int? ?? 0;
              return Track(
                id: t['id'] as String? ?? 'sp_0',
                title: t['title'] as String? ?? 'Unknown Title',
                artist: t['artist'] as String? ?? 'Unknown Artist',
                album: t['album'] as String? ?? '',
                expectedDuration: durMs > 0 ? Duration(milliseconds: durMs) : null,
              );
            }).toList();

            playlists.add(
              SpotifyPlaylist(
                id: item['id'] as String? ?? '',
                title: item['title'] as String? ?? 'Saved Playlist',
                description: item['description'] as String?,
                coverUrl: item['coverUrl'] as String?,
                ownerName: item['ownerName'] as String? ?? 'User',
                source: item['source'] as String? ?? 'Spotify',
                tracks: tracks,
              ),
            );
          }
        }
        if (playlists.isNotEmpty) {
          state = playlists;
          break;
        }
      }
    } catch (_) {}
  }
  }

  void addPlaylist(SpotifyPlaylist playlist) {
    state = [
      playlist,
      ...state.where((p) => p.id != playlist.id),
    ];
  }
}

final importedPlaylistsProvider =
    StateNotifierProvider<ImportedPlaylistsNotifier, List<SpotifyPlaylist>>((ref) {
  return ImportedPlaylistsNotifier();
});

/// StateProvider holding the currently viewed Spotify Playlist
final activePlaylistProvider = StateProvider<SpotifyPlaylist?>((ref) => null);

/// Active navigation tab: 'home' | 'search' | 'library'
final activeNavTabProvider = StateProvider<String>((ref) => 'home');

/// Active search query string
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Async provider for live search results
final searchResultsProvider = FutureProvider<List<Track>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) return [];

  final searchService = ref.watch(searchServiceProvider);
  return searchService.searchTracks(query);
});
