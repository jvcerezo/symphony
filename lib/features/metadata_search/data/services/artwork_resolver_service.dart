import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../../audio_player/domain/entities/track.dart';

class ArtworkResolverService {
  final http.Client _httpClient;
  final Map<String, Uri> _cache = {};

  ArtworkResolverService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  /// Resolves a high-res artwork URI for a [Track] using unauthenticated public APIs.
  Future<Uri?> resolveArtwork(Track track) async {
    if (track.artworkUri != null) return track.artworkUri;

    final key = '${track.artist.toLowerCase()}_${track.title.toLowerCase()}';
    if (_cache.containsKey(key)) return _cache[key];

    final query = '${track.artist} ${track.title}'.trim();
    if (query.isEmpty) return null;

    try {
      final uri = Uri.parse(
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&media=music&entity=song&limit=1',
      );

      final response = await _httpClient.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = (data['results'] as List<dynamic>?) ?? [];

        if (results.isNotEmpty) {
          final rawArt = results[0]['artworkUrl100'] as String?;
          if (rawArt != null && rawArt.isNotEmpty) {
            final highRes = rawArt.replaceAll('100x100bb.jpg', '600x600bb.jpg');
            final resolvedUri = Uri.tryParse(highRes);
            if (resolvedUri != null) {
              _cache[key] = resolvedUri;
              return resolvedUri;
            }
          }
        }
      }
    } catch (e) {
      developer.log('Artwork resolution error for "$query": $e', name: 'ArtworkResolver');
    }

    return null;
  }

  void dispose() {
    _httpClient.close();
  }
}
