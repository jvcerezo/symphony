import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../../audio_player/domain/entities/track.dart';

class SearchService {
  final http.Client _httpClient;

  SearchService({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  /// Searches tracks across iTunes public API (unauthenticated, CORS-compliant, high-res art).
  Future<List<Track>> searchTracks(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final uri = Uri.parse(
      'https://itunes.apple.com/search?term=${Uri.encodeComponent(cleanQuery)}&media=music&entity=song&limit=25',
    );

    try {
      developer.log('Searching tracks for: "$cleanQuery"', name: 'SearchService');
      final response = await _httpClient.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        return [];
      }

      final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (data['results'] as List<dynamic>?) ?? [];

      return results.map((item) {
        final title = item['trackName'] as String? ?? 'Unknown Title';
        final artist = item['artistName'] as String? ?? 'Unknown Artist';
        final album = item['collectionName'] as String? ?? '';
        final durationMs = item['trackTimeMillis'] as int? ?? 0;
        final rawArt = item['artworkUrl100'] as String?;
        // Request ultra high resolution master artwork
        final highResArt = rawArt?.replaceAll(RegExp(r'\d+x\d+bb'), '1000x1000bb');
        final previewUrl = item['previewUrl'] as String?;

        return Track(
          id: 'itunes_${item['trackId'] ?? title}',
          title: title,
          artist: artist,
          album: album,
          expectedDuration: durationMs > 0 ? Duration(milliseconds: durationMs) : null,
          artworkUri: highResArt != null ? Uri.tryParse(highResArt) : null,
          streamUri: previewUrl != null ? Uri.tryParse(previewUrl) : null,
        );
      }).toList();
    } catch (e, st) {
      developer.log('Search error', error: e, stackTrace: st, name: 'SearchService');
      return [];
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
