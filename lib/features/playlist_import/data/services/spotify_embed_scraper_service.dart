import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../../../audio_player/domain/entities/track.dart';
import '../../../metadata_search/data/services/artwork_resolver_service.dart';
import '../../domain/entities/playlist_summary.dart';
import '../../domain/entities/spotify_playlist.dart';
import '../../../../core/config/server_config.dart';

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
    final htmlBody = await _fetchEmbedHtml(playlistId);

    // 3. If HTML was successfully extracted, parse __NEXT_DATA__
    if (htmlBody != null && htmlBody.contains('__NEXT_DATA__')) {
      final jsonData = await compute(_nextData, htmlBody);

      if (jsonData is Map<String, dynamic>) {
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

    // 4. Never substitute placeholder tracks for a playlist we couldn't read.
    throw FormatException(
      'Could not import Spotify playlist "$playlistId". If this is a private playlist, please set it to "Public" on Spotify and try again.',
    );
  }

  /// The playlist's embed page (direct on native, CORS proxies on web).
  Future<String?> _fetchEmbedHtml(String playlistId) async {
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
    return htmlBody;
  }

  /// The page's __NEXT_DATA__, decoded; null when it has none. Run on a
  /// background isolate: the page is large to parse.
  static Object? _nextData(String html) {
    final text = html_parser.parse(html).getElementById('__NEXT_DATA__')?.text;
    if (text == null || text.trim().isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  /// Name, owner and cover of a Spotify playlist, without loading its
  /// songs: for browse cards. Null when the playlist can't be read.
  Future<PlaylistSummary?> fetchSummary(String playlistId) async {
    final html = await _fetchEmbedHtml(playlistId);
    if (html == null || !html.contains('__NEXT_DATA__')) return null;
    try {
      final entity = (await compute(_nextData, html) as Map<String, dynamic>)['props']?['pageProps']?['state']?['data']?['entity'];
      if (entity is! Map) return null;
      final images = entity['coverArt']?['sources'];
      String? cover;
      if (images is List && images.isNotEmpty) {
        final sorted = images.whereType<Map>().toList()
          ..sort((a, b) => ((b['width'] as num?) ?? 0).compareTo((a['width'] as num?) ?? 0));
        // 00000002 is a small cover; 00000003 the large one.
        cover = (sorted.isEmpty ? null : sorted.first['url'] as String?)?.replaceAll('00000002', '00000003');
      }
      final tracks = entity['trackList'];
      return PlaylistSummary(
        source: PlaylistSource.spotify,
        id: playlistId,
        title: entity['name'] as String? ?? 'Spotify Playlist',
        subtitle: entity['subtitle'] as String? ?? 'Spotify',
        coverUrl: cover,
        link: 'https://open.spotify.com/playlist/$playlistId',
        trackCount: tracks is List ? tracks.length : null,
      );
    } catch (e) {
      developer.log('Spotify summary parse failed for $playlistId: $e', name: 'SpotifyScraper');
      return null;
    }
  }

  /// Calls the local Symphony server to scrape Spotify without browser CORS limits.
  Future<SpotifyPlaylist?> _importViaServer(String playlistId, {String? instanceId}) async {
    final candidateOrigins = ServerConfig.candidateOrigins();

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

  void dispose() {
    _httpClient.close();
    _artworkResolver.dispose();
  }
}
