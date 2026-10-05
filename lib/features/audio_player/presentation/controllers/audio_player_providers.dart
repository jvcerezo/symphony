import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../metadata_search/data/services/search_service.dart';
import '../../../playlist_import/data/services/spotify_embed_scraper_service.dart';
import '../../../playlist_import/domain/entities/spotify_playlist.dart';
import '../../data/services/symphony_audio_handler.dart';
import '../../domain/entities/track.dart';

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

/// Provider for the unauthenticated Spotify Embed Scraper
final spotifyScraperProvider = Provider<SpotifyEmbedScraperService>((ref) {
  final service = SpotifyEmbedScraperService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for unauthenticated iTunes / Deezer search
final searchServiceProvider = Provider<SearchService>((ref) {
  final service = SearchService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// StateNotifier for managing imported Spotify playlists
class ImportedPlaylistsNotifier extends StateNotifier<List<SpotifyPlaylist>> {
  ImportedPlaylistsNotifier() : super([]);

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
