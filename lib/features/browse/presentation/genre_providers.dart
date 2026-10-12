import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../audio_player/presentation/controllers/audio_player_providers.dart';
import '../../playlist_import/domain/entities/playlist_summary.dart';
import '../../playlist_import/domain/entities/spotify_playlist.dart';
import '../data/genre_catalog.dart';
import '../data/genre_playlist_service.dart';

/// The genre being browsed on Home, or null for the regular Home page.
final activeGenreProvider = StateProvider<Genre?>((ref) => null);

final genrePlaylistServiceProvider = Provider<GenrePlaylistService>((ref) {
  return GenrePlaylistService(spotify: ref.watch(spotifyScraperProvider));
});

/// One source's playlists for one genre. Kept for the session, so going
/// back to a genre doesn't reload it; pull to retry via invalidate.
final genrePlaylistsProvider =
    FutureProvider.family<List<PlaylistSummary>, (Genre, PlaylistSource)>((ref, key) {
  return ref.watch(genrePlaylistServiceProvider).playlistsFor(key.$1, key.$2);
});

/// Loads a browsed playlist's songs (once per session).
final openedPlaylistProvider = FutureProvider.family<SpotifyPlaylist, PlaylistSummary>((ref, summary) {
  return ref.watch(universalPlaylistImporterProvider).importPlaylist(summary.link);
});
