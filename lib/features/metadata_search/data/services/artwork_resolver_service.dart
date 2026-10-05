import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../../audio_player/domain/entities/track.dart';

class ArtworkResolverService {
  final http.Client _httpClient;
  final Map<String, Uri> _cache = {};
  final Map<String, Future<Uri?>> _inFlight = {};

  ArtworkResolverService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  /// Cleans track titles from extraneous metadata that damages iTunes search accuracy.
  static String cleanTrackTitle(String rawTitle) {
    var title = rawTitle;
    // Remove (feat. ...), [feat. ...], (with ...), etc.
    title = title.replaceAll(
      RegExp(r'\s*[\(\[](?:feat|ft|with)\.?\s+[^\)\]]+[\)\]]', caseSensitive: false),
      '',
    );
    // Remove " - Remastered.*", " - Radio Edit", " - Live", etc.
    title = title.replaceAll(
      RegExp(r'\s*-\s*(?:remastered|live|mono|stereo|radio edit|bonus track).*$', caseSensitive: false),
      '',
    );
    // Remove " - feat. ..."
    title = title.replaceAll(
      RegExp(r'\s*-\s*(?:feat|ft)\.?\s+.*$', caseSensitive: false),
      '',
    );
    return title.trim();
  }

  /// Resolves a high-res artwork URI for a [Track] using unauthenticated public APIs.
  Future<Uri?> resolveArtwork(Track track) {
    if (track.artworkUri != null) return Future.value(track.artworkUri);

    final cleanTitle = cleanTrackTitle(track.title);
    final key = '${track.artist.toLowerCase()}_${cleanTitle.toLowerCase()}';

    if (_cache.containsKey(key)) {
      return Future.value(_cache[key]);
    }

    if (_inFlight.containsKey(key)) {
      return _inFlight[key]!;
    }

    final future = _fetchArtwork(track.artist, cleanTitle, key);
    _inFlight[key] = future;
    return future;
  }

  Future<Uri?> _fetchArtwork(String artist, String title, String cacheKey) async {
    final query = '$artist $title'.trim();
    if (query.isEmpty) return null;

    try {
      final uri = Uri.parse(
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&media=music&entity=song&limit=1',
      );

      final response = await _httpClient.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = (data['results'] as List<dynamic>?) ?? [];

        if (results.isNotEmpty) {
          final rawArt = results[0]['artworkUrl100'] as String?;
          if (rawArt != null && rawArt.isNotEmpty) {
            final highRes = rawArt.replaceAll(RegExp(r'\d+x\d+bb'), '1000x1000bb');
            final resolvedUri = Uri.tryParse(highRes);
            if (resolvedUri != null) {
              _cache[cacheKey] = resolvedUri;
              return resolvedUri;
            }
          }
        }
      }
    } catch (e) {
      developer.log('Artwork resolution error for "$query": $e', name: 'ArtworkResolver');
    } finally {
      _inFlight.remove(cacheKey);
    }

    return null;
  }

  /// Concurrently resolves and attaches artwork URIs for a list of tracks.
  Future<List<Track>> batchResolve(List<Track> tracks, {int maxCount = 20}) async {
    if (tracks.isEmpty) return tracks;

    final targetCount = tracks.length < maxCount ? tracks.length : maxCount;
    final topTracks = tracks.sublist(0, targetCount);

    final resolvedTop = await Future.wait(
      topTracks.map((t) async {
        if (t.artworkUri != null) return t;
        try {
          final uri = await resolveArtwork(t);
          return uri != null ? t.copyWith(artworkUri: uri) : t;
        } catch (_) {
          return t;
        }
      }),
    );

    final result = List<Track>.from(tracks);
    for (int i = 0; i < resolvedTop.length; i++) {
      result[i] = resolvedTop[i];
    }
    return result;
  }

  void dispose() {
    _httpClient.close();
  }
}
