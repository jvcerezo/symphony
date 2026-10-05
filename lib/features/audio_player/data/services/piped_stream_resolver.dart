import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/resolved_audio_stream.dart';
import '../../domain/entities/track.dart';

class PipedStreamResolver {
  final http.Client _httpClient;

  static const List<String> _publicInstances = [
    'https://pipedapi.kavin.rocks',
    'https://api.piped.privacydev.net',
    'https://piped-api.lunar.icu',
  ];

  PipedStreamResolver({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Resolves an audio stream using public CORS-compliant Piped instances.
  /// Used primarily for Web environments and secondary fallback on Native.
  Future<ResolvedAudioStream> resolve(Track track) async {
    final query = Uri.encodeQueryComponent('${track.artist} - ${track.title} official audio');

    for (final instance in _publicInstances) {
      try {
        developer.log('Querying Piped instance: $instance', name: 'PipedStreamResolver');
        final searchUri = Uri.parse('$instance/search?q=$query&filter=all');
        final searchRes = await _httpClient.get(searchUri).timeout(const Duration(seconds: 8));

        if (searchRes.statusCode != 200) continue;

        final Map<String, dynamic> searchData = jsonDecode(searchRes.body) as Map<String, dynamic>;
        final items = (searchData['items'] as List<dynamic>?) ?? [];

        final candidates = items.where((item) {
          final url = item['url'] as String? ?? '';
          final duration = item['duration'] as int? ?? 0;
          return url.startsWith('/watch?v=') && duration > 30;
        }).take(5).toList();

        for (final candidate in candidates) {
          final rawUrl = candidate['url'] as String;
          final videoId = rawUrl.replaceFirst('/watch?v=', '');
          final durationSeconds = candidate['duration'] as int? ?? 0;

          // Check duration disparity if track duration is known
          if (track.expectedDuration != null && durationSeconds > 0) {
            final delta = (durationSeconds - track.expectedDuration!.inSeconds).abs();
            if (delta > 60) continue;
          }

          final streamUri = Uri.parse('$instance/streams/$videoId');
          final streamRes = await _httpClient.get(streamUri).timeout(const Duration(seconds: 8));
          if (streamRes.statusCode != 200) continue;

          final Map<String, dynamic> streamData = jsonDecode(streamRes.body) as Map<String, dynamic>;
          final audioStreams = (streamData['audioStreams'] as List<dynamic>?) ?? [];
          if (audioStreams.isEmpty) continue;

          // Select audio stream with highest bitrate
          audioStreams.sort((a, b) => (b['bitrate'] as num? ?? 0).compareTo(a['bitrate'] as num? ?? 0));
          final bestAudio = audioStreams.first as Map<String, dynamic>;

          final rawStreamUrl = bestAudio['url'] as String? ?? '';
          if (rawStreamUrl.isEmpty) continue;

          return ResolvedAudioStream(
            streamUri: Uri.parse(rawStreamUrl),
            duration: Duration(seconds: durationSeconds),
            bitrateKbps: ((bestAudio['bitrate'] as num? ?? 128000) / 1000).round(),
            format: (bestAudio['format'] as String? ?? 'm4a').toLowerCase(),
            sourceVideoId: videoId,
          );
        }
      } catch (e, st) {
        developer.log(
          'Error with Piped instance $instance: $e',
          name: 'PipedStreamResolver',
          error: e,
          stackTrace: st,
        );
        continue;
      }
    }

    throw AudioStreamResolutionException(
      'All public CORS streaming instances failed for track: "${track.title}"',
    );
  }

  void dispose() {
    _httpClient.close();
  }
}
