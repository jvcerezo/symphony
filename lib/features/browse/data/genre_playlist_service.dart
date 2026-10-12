import 'dart:developer' as developer;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../playlist_import/data/services/apple_music_web_service.dart';
import '../../playlist_import/data/services/spotify_embed_scraper_service.dart';
import '../../playlist_import/domain/entities/playlist_summary.dart';
import 'genre_catalog.dart';

typedef PlaylistSearch = Future<List<PlaylistSummary>> Function(String query, int limit);

/// Finds current playlists for a [Genre] on Spotify, Apple Music and
/// YouTube, one source at a time so a slow source doesn't hold up the rest.
class GenrePlaylistService {
  final SpotifyEmbedScraperService _spotify;
  final PlaylistSearch _appleSearch;
  final PlaylistSearch _youtubeSearch;

  GenrePlaylistService({
    required SpotifyEmbedScraperService spotify,
    AppleMusicWebService? appleMusic,
    PlaylistSearch? appleSearch,
    PlaylistSearch? youtubeSearch,
  })  : _spotify = spotify,
        _appleSearch = appleSearch ??
            ((q, limit) => (appleMusic ?? AppleMusicWebService()).searchPlaylists(q, limit: limit)),
        _youtubeSearch = youtubeSearch ?? searchYouTubePlaylists;

  static const perSource = 6;

  Future<List<PlaylistSummary>> playlistsFor(Genre genre, PlaylistSource source) async {
    switch (source) {
      case PlaylistSource.spotify:
        final found = await Future.wait(genre.spotifyPlaylistIds.map(_spotify.fetchSummary));
        return found.whereType<PlaylistSummary>().toList();
      case PlaylistSource.appleMusic:
        return _appleSearch(genre.query, perSource);
      case PlaylistSource.youtube:
        return _youtubeSearch('${genre.query} playlist', perSource);
    }
  }

  /// YouTube playlist search, official YouTube Music playlists first
  /// (their ids start with RDCLAK).
  static Future<List<PlaylistSummary>> searchYouTubePlaylists(String query, int limit) async {
    final yt = YoutubeExplode();
    try {
      final results = await yt.search.searchContent(query, filter: TypeFilters.playlist);
      final found = <PlaylistSummary>[];
      for (final r in results) {
        if (r is! SearchPlaylist || r.videoCount == 0) continue;
        final id = r.id.value;
        found.add(PlaylistSummary(
          source: PlaylistSource.youtube,
          id: id,
          title: r.title,
          subtitle: id.startsWith('RDCLAK') ? 'YouTube Music' : 'YouTube',
          coverUrl: r.thumbnails.isEmpty ? null : r.thumbnails.last.url.toString(),
          link: 'https://www.youtube.com/playlist?list=$id',
          trackCount: r.videoCount,
        ));
      }
      found.sort((a, b) => (b.id.startsWith('RDCLAK') ? 1 : 0) - (a.id.startsWith('RDCLAK') ? 1 : 0));
      return found.take(limit).toList();
    } catch (e) {
      developer.log('YouTube playlist search failed: $e', name: 'Browse');
      rethrow;
    } finally {
      yt.close();
    }
  }
}
