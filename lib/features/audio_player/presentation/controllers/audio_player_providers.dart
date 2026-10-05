import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../metadata_search/data/services/artwork_resolver_service.dart';
import '../../../metadata_search/data/services/search_service.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../playlist_import/data/services/spotify_embed_scraper_service.dart';
import '../../../playlist_import/data/services/universal_playlist_importer_service.dart';
import '../../../playlist_import/domain/entities/spotify_playlist.dart';
import '../../data/services/symphony_audio_handler.dart';
import '../../domain/entities/track.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// StateNotifier for managing imported Spotify playlists with offline persistence unique to each user/instance
class ImportedPlaylistsNotifier extends StateNotifier<List<SpotifyPlaylist>> {
  static const _localPlaylistsKey = 'symphony_user_playlists';

  ImportedPlaylistsNotifier() : super([]) {
    _loadFromLocalPrefs();
  }

  Future<void> _loadFromLocalPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_localPlaylistsKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final list = jsonDecode(jsonStr) as List<dynamic>;
        final playlists = list
            .whereType<Map<String, dynamic>>()
            .map((item) => SpotifyPlaylist.fromJson(item))
            .toList();
        state = playlists;
      }
    } catch (_) {}
  }

  Future<void> _saveToLocalPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listJson = state.map((p) => p.toJson()).toList();
      await prefs.setString(_localPlaylistsKey, jsonEncode(listJson));
    } catch (_) {}
  }

  void addPlaylist(SpotifyPlaylist playlist) {
    state = [
      playlist,
      ...state.where((p) => p.id != playlist.id),
    ];
    _saveToLocalPrefs();
  }

  void removePlaylist(String playlistId) {
    state = state.where((p) => p.id != playlistId).toList();
    _saveToLocalPrefs();
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
