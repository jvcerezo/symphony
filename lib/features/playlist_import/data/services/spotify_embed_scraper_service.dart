import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../../audio_player/domain/entities/track.dart';
import '../../../metadata_search/data/services/artwork_resolver_service.dart';
import '../../domain/entities/spotify_playlist.dart';

class SpotifyEmbedScraperService {
  final http.Client _httpClient;
  final ArtworkResolverService _artworkResolver;

  static const List<String> _webCorsProxies = [
    'https://api.allorigins.win/raw?url=',
    'https://api.codetabs.com/v1/proxy?quest=',
  ];

  SpotifyEmbedScraperService({
    http.Client? httpClient,
    ArtworkResolverService? artworkResolver,
  })  : _httpClient = httpClient ?? http.Client(),
        _artworkResolver = artworkResolver ?? ArtworkResolverService(httpClient: httpClient);

  /// Extracts the Spotify playlist ID from varied link formats.
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
        return segments[idx + 1].split('?').first;
      }
    } catch (_) {
      // Regex fallback
    }

    final match = RegExp(r'playlist[/:]([a-zA-Z0-9]+)').firstMatch(trimmed);
    if (match != null) return match.group(1);

    if (RegExp(r'^[a-zA-Z0-9]{15,30}$').hasMatch(trimmed)) {
      return trimmed;
    }

    return null;
  }

  /// Scrapes public Spotify playlist metadata and tracks without OAuth credentials.
  /// Handles browser CORS transparently by querying the local backend server first.
  Future<SpotifyPlaylist> importPlaylist(String playlistUrlOrId, {String? instanceId}) async {
    final playlistId = extractPlaylistId(playlistUrlOrId);
    if (playlistId == null || playlistId.isEmpty) {
      throw const FormatException('Invalid Spotify playlist URL or ID provided.');
    }

    developer.log('Importing Spotify playlist: $playlistId', name: 'SpotifyScraper');

    // 1. Primary: Import via Symphony backend server (Zero CORS, 100% full playlist retrieval)
    final serverPlaylist = await _importViaServer(playlistId, instanceId: instanceId);
    if (serverPlaylist != null && serverPlaylist.tracks.isNotEmpty) {
      developer.log('Successfully imported playlist via server: "${serverPlaylist.title}" (${serverPlaylist.trackCount} tracks)', name: 'SpotifyScraper');
      return serverPlaylist;
    }

    // 2. Native socket fetch or Web proxy fallback
    final targetEmbedUrl = 'https://open.spotify.com/embed/playlist/$playlistId';
    String? htmlBody;

    if (!kIsWeb) {
      try {
        final response = await _httpClient.get(
          Uri.parse(targetEmbedUrl),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          htmlBody = response.body;
        }
      } catch (e) {
        developer.log('Native direct fetch failed, attempting web fallback', error: e, name: 'SpotifyScraper');
      }
    }

    if (htmlBody == null) {
      for (final proxy in _webCorsProxies) {
        try {
          final proxiedUri = Uri.parse('$proxy${Uri.encodeComponent(targetEmbedUrl)}');
          final response = await _httpClient.get(proxiedUri).timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 && response.body.contains('__NEXT_DATA__')) {
            htmlBody = response.body;
            break;
          }
        } catch (e) {
          developer.log('Proxy $proxy failed: $e', name: 'SpotifyScraper');
          continue;
        }
      }
    }

    // 3. If HTML was successfully extracted, parse __NEXT_DATA__
    if (htmlBody != null && htmlBody.contains('__NEXT_DATA__')) {
      final document = html_parser.parse(htmlBody);
      final scriptTag = document.getElementById('__NEXT_DATA__');

      if (scriptTag != null && scriptTag.text.trim().isNotEmpty) {
        final Map<String, dynamic> jsonData = jsonDecode(scriptTag.text) as Map<String, dynamic>;
        final entity = jsonData['props']?['pageProps']?['state']?['data']?['entity'];

        if (entity != null) {
          final title = entity['name'] as String? ?? 'Untitled Playlist';
          final description = entity['description'] as String?;
          final ownerName = entity['owner']?['name'] as String? ?? 'Spotify';

          String? coverUrl;
          final visualIdentity = entity['visualIdentity']?['image'] as List<dynamic>?;
          if (visualIdentity != null && visualIdentity.isNotEmpty) {
            final sortedImages = List<dynamic>.from(visualIdentity)
              ..sort((a, b) {
                final wA = (a is Map) ? (a['maxWidth'] as int? ?? 0) : 0;
                final wB = (b is Map) ? (b['maxWidth'] as int? ?? 0) : 0;
                return wB.compareTo(wA);
              });
            final best = sortedImages.first;
            if (best is Map) {
              coverUrl = best['url'] as String?;
            }
          }
          coverUrl ??= entity['coverArt']?['sources']?[0]?['url'] as String?;

          if (coverUrl != null) {
            coverUrl = coverUrl
                .replaceAll('00000001', '00000003')
                .replaceAll('00000002', '00000003');
          }

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
              ),
            );
          }

          if (tracks.isNotEmpty) {
            final enrichedTracks = await _artworkResolver.batchResolve(tracks, maxCount: 15);
            return SpotifyPlaylist(
              id: playlistId,
              title: title,
              description: description,
              coverUrl: coverUrl,
              ownerName: ownerName,
              source: 'Spotify',
              tracks: enrichedTracks,
            );
          }
        }
      }
    }

    // 4. If this is the default Today's Top Hits playlist and network is offline, provide curated fallback
    if (playlistId == '37i9dQZF1DXcBWIGoYBM5M') {
      return _buildCuratedFallback(playlistId);
    }

    // 5. For user playlists, DO NOT replace their playlist with 8 dummy tracks!
    throw FormatException(
      'Could not import Spotify playlist "$playlistId". If this is a private playlist, please set it to "Public" on Spotify and try again.',
    );
  }

  /// Calls the local Symphony server to scrape Spotify without browser CORS limits.
  Future<SpotifyPlaylist?> _importViaServer(String playlistId, {String? instanceId}) async {
    final candidateOrigins = <String>[];
    if (kIsWeb) {
      try {
        final origin = Uri.base.origin;
        if (origin.isNotEmpty && !origin.startsWith('null')) {
          candidateOrigins.add(origin);
        }
      } catch (_) {}
    } else {
      for (final host in [
        'https://symphony.jettimothycerezo.dev',
        'http://192.168.1.57:8080',
        'http://localhost:8080',
        'http://127.0.0.1:8080',
      ]) {
        if (!candidateOrigins.contains(host)) {
          candidateOrigins.add(host);
        }
      }
    }

    for (final origin in candidateOrigins) {
      try {
        final q = instanceId != null && instanceId.isNotEmpty
            ? 'id=$playlistId&instanceId=$instanceId'
            : 'id=$playlistId';
        final uri = Uri.parse('$origin/api/playlist/spotify?$q');
        final response = await _httpClient.get(uri).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final rawTracks = data['tracks'] as List<dynamic>? ?? [];
          final tracks = <Track>[];

          for (int i = 0; i < rawTracks.length; i++) {
            final t = rawTracks[i] as Map<String, dynamic>;
            final durMs = (t['durationMs'] as num?)?.toInt() ?? 0;
            tracks.add(
              Track(
                id: t['id'] as String? ?? 'sp_$i',
                title: t['title'] as String? ?? 'Unknown Title',
                artist: t['artist'] as String? ?? 'Unknown Artist',
                album: t['album'] as String? ?? data['title'] as String? ?? '',
                expectedDuration: durMs > 0 ? Duration(milliseconds: durMs) : null,
              ),
            );
          }

          if (tracks.isNotEmpty) {
            developer.log('Parsed ${tracks.length} tracks from server for playlist "$playlistId"', name: 'SpotifyScraper');
            final enriched = await _artworkResolver.batchResolve(tracks, maxCount: 15);
            return SpotifyPlaylist(
              id: playlistId,
              title: data['title'] as String? ?? 'Spotify Playlist',
              description: data['description'] as String?,
              coverUrl: data['coverUrl'] as String?,
              ownerName: data['ownerName'] as String? ?? 'Spotify',
              source: 'Spotify',
              tracks: enriched,
            );
          }
        }
      } catch (e) {
        developer.log('Server playlist import failed on $origin: $e', name: 'SpotifyScraper');
      }
    }
    return null;
  }

  SpotifyPlaylist _buildCuratedFallback(String playlistId) {
    developer.log('Providing curated fallback for playlist: $playlistId', name: 'SpotifyScraper');
    return SpotifyPlaylist(
      id: playlistId,
      title: "Today's Top Hits",
      description: 'The hottest tracks right now • Curated for Symphony',
      coverUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=1200&q=90',
      ownerName: 'Spotify',
      tracks: [
        Track(
          id: 'tth_01',
          title: 'Blinding Lights',
          artist: 'The Weeknd',
          album: 'After Hours',
          expectedDuration: const Duration(minutes: 3, seconds: 20),
          artworkUri: Uri.parse(
            'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/2b/b9/fe/2bb9fef5-d7f3-8345-25a9-db0e79fde4e4/20UMGIM11048.rgb.jpg/600x600bb.jpg',
          ),
        ),
        Track(
          id: 'tth_02',
          title: 'Starboy',
          artist: 'The Weeknd ft. Daft Punk',
          album: 'Starboy',
          expectedDuration: const Duration(minutes: 3, seconds: 50),
          artworkUri: Uri.parse(
            'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/5a/08/94/5a089454-e0e9-b541-6547-06399b109e9e/16UMGIM56476.rgb.jpg/600x600bb.jpg',
          ),
        ),
        Track(
          id: 'tth_03',
          title: 'Cruel Summer',
          artist: 'Taylor Swift',
          album: 'Lover',
          expectedDuration: const Duration(minutes: 2, seconds: 58),
          artworkUri: Uri.parse(
            'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/49/3d/ab/493dab54-f920-9043-6181-809930f36894/19UMGIM68357.rgb.jpg/600x600bb.jpg',
          ),
        ),
        Track(
          id: 'tth_04',
          title: 'As It Was',
          artist: 'Harry Styles',
          album: "Harry's House",
          expectedDuration: const Duration(minutes: 2, seconds: 47),
          artworkUri: Uri.parse(
            'https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/31/f0/24/31f02477-8025-a6fa-c146-5e58cfad1bc3/886449984711.jpg/600x600bb.jpg',
          ),
        ),
        Track(
          id: 'tth_05',
          title: 'Flowers',
          artist: 'Miley Cyrus',
          album: 'Endless Summer Vacation',
          expectedDuration: const Duration(minutes: 3, seconds: 20),
          artworkUri: Uri.parse(
            'https://is1-ssl.mzstatic.com/image/thumb/Music113/v4/2e/d0/09/2ed0092f-ef64-9665-27a3-aa04c8fca3cf/196589561726.jpg/600x600bb.jpg',
          ),
        ),
        Track(
          id: 'tth_06',
          title: 'Levitating',
          artist: 'Dua Lipa',
          album: 'Future Nostalgia',
          expectedDuration: const Duration(minutes: 3, seconds: 23),
          artworkUri: Uri.parse(
            'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/a4/09/a5/a409a5cb-2292-9337-b648-842cefc3f9e9/190295286101.jpg/600x600bb.jpg',
          ),
        ),
        Track(
          id: 'tth_07',
          title: 'Save Your Tears',
          artist: 'The Weeknd',
          album: 'After Hours',
          expectedDuration: const Duration(minutes: 3, seconds: 35),
          artworkUri: Uri.parse(
            'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/2b/b9/fe/2bb9fef5-d7f3-8345-25a9-db0e79fde4e4/20UMGIM11048.rgb.jpg/600x600bb.jpg',
          ),
        ),
        Track(
          id: 'tth_08',
          title: 'Shape of You',
          artist: 'Ed Sheeran',
          album: 'Divide',
          expectedDuration: const Duration(minutes: 3, seconds: 53),
          artworkUri: Uri.parse(
            'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/4a/c3/05/4ac30560-60b8-c309-faee-a10c2c31e9c5/190295851286.jpg/600x600bb.jpg',
          ),
        ),
      ],
    );
  }

  void dispose() {
    _httpClient.close();
    _artworkResolver.dispose();
  }
}
