import 'dart:convert';
import 'dart:developer' as developer;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../../../core/errors/exceptions.dart';
import '../../../audio_player/domain/entities/track.dart';
import '../../domain/entities/spotify_playlist.dart';

class SpotifyEmbedScraperService {
  final http.Client _httpClient;

  SpotifyEmbedScraperService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Extracts the Spotify playlist ID from varied link formats:
  /// - https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=...
  /// - https://open.spotify.com/embed/playlist/37i9dQZF1DXcBWIGoYBM5M
  /// - spotify:playlist:37i9dQZF1DXcBWIGoYBM5M
  String? extractPlaylistId(String input) {
    final trimmed = input.trim();
    if (trimmed.startsWith('spotify:playlist:')) {
      return trimmed.replaceFirst('spotify:playlist:', '');
    }

    try {
      final uri = Uri.parse(trimmed);
      final segments = uri.pathSegments;
      final idx = segments.indexOf('playlist');
      if (idx != -1 && idx + 1 < segments.length) {
        return segments[idx + 1];
      }
    } catch (_) {
      // Regex fallback
    }

    final match = RegExp(r'playlist[/:]([a-zA-Z0-9]+)').firstMatch(trimmed);
    if (match != null) return match.group(1);

    // Support raw Spotify ID
    if (RegExp(r'^[a-zA-Z0-9]{15,30}$').hasMatch(trimmed)) {
      return trimmed;
    }

    return null;
  }

  /// Scrapes public Spotify playlist metadata and tracks without OAuth credentials.
  Future<SpotifyPlaylist> importPlaylist(String playlistUrlOrId) async {
    final playlistId = extractPlaylistId(playlistUrlOrId);
    if (playlistId == null || playlistId.isEmpty) {
      throw const FormatException('Invalid Spotify playlist URL or ID provided.');
    }

    final embedUrl = 'https://open.spotify.com/embed/playlist/$playlistId';
    developer.log('Scraping Spotify embed: $embedUrl', name: 'SpotifyScraper');

    try {
      final response = await _httpClient.get(
        Uri.parse(embedUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw AudioStreamResolutionException(
          'Failed to retrieve Spotify embed page (HTTP ${response.statusCode})',
        );
      }

      final document = html_parser.parse(response.body);
      final scriptTag = document.getElementById('__NEXT_DATA__');

      if (scriptTag == null || scriptTag.text.trim().isEmpty) {
        throw const AudioStreamResolutionException(
          'Could not locate __NEXT_DATA__ payload in Spotify embed response.',
        );
      }

      final Map<String, dynamic> jsonData = jsonDecode(scriptTag.text) as Map<String, dynamic>;
      final entity = jsonData['props']?['pageProps']?['state']?['data']?['entity'];

      if (entity == null) {
        throw const AudioStreamResolutionException(
          'Malformed Spotify payload: missing entity data.',
        );
      }

      final title = entity['name'] as String? ?? 'Untitled Playlist';
      final description = entity['description'] as String?;
      final ownerName = entity['owner']?['name'] as String? ?? 'Spotify';

      // Parse cover art URL
      String? coverUrl;
      final visualIdentity = entity['visualIdentity']?['image'] as List<dynamic>?;
      if (visualIdentity != null && visualIdentity.isNotEmpty) {
        coverUrl = visualIdentity[0]?['url'] as String?;
      }
      coverUrl ??= entity['coverArt']?['sources']?[0]?['url'] as String?;

      // Parse track list
      final rawTracks = (entity['trackList'] as List<dynamic>?) ?? [];
      final List<Track> tracks = [];

      for (int i = 0; i < rawTracks.length; i++) {
        final item = rawTracks[i] as Map<String, dynamic>;
        final trackTitle = item['title'] as String? ?? 'Unknown Title';
        final artist = item['subtitle'] as String? ?? 'Unknown Artist';
        final durationMs = item['duration'] as int? ?? 0;
        final trackUriStr = item['uri'] as String? ?? 'spotify:track:$i';

        tracks.add(
          Track(
            id: trackUriStr,
            title: trackTitle,
            artist: artist,
            album: title,
            expectedDuration: durationMs > 0 ? Duration(milliseconds: durationMs) : null,
            artworkUri: coverUrl != null ? Uri.tryParse(coverUrl) : null,
          ),
        );
      }

      developer.log(
        'Successfully scraped playlist "$title" with ${tracks.length} tracks',
        name: 'SpotifyScraper',
      );

      return SpotifyPlaylist(
        id: playlistId,
        title: title,
        description: description,
        coverUrl: coverUrl,
        ownerName: ownerName,
        tracks: tracks,
      );
    } catch (e, st) {
      developer.log('Spotify scraping error', error: e, stackTrace: st, name: 'SpotifyScraper');
      if (e is FormatException || e is AudioStreamResolutionException) rethrow;
      throw AudioStreamResolutionException('Failed to scrape Spotify playlist: $e');
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
