import 'dart:convert';
import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final Map<String, Map<String, dynamic>> _cache = {};
final _yt = YoutubeExplode();

Future<void> main() async {
  final port = 8080;
  final webDir = Directory('build/web');

  if (!await webDir.exists()) {
    print('Error: build/web directory not found');
    return;
  }

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('Symphony Full-Track Server running on http://localhost:$port');

  await for (final request in server) {
    _handleRequest(request, webDir);
  }
}

Future<void> _handleRequest(HttpRequest request, Directory webDir) async {
  request.response.headers.add('Access-Control-Allow-Origin', '*');
  request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  request.response.headers.add('Access-Control-Allow-Headers', '*');

  if (request.method == 'OPTIONS') {
    request.response.statusCode = HttpStatus.ok;
    await request.response.close();
    return;
  }

  final uri = request.uri;

  // Full-track YouTube Audio Resolver API Endpoint
  if (uri.path == '/api/resolve') {
    final directVideoId = uri.queryParameters['videoId'];
    final query = uri.queryParameters['q'] ??
        '${uri.queryParameters['artist'] ?? ''} - ${uri.queryParameters['title'] ?? ''} official audio';
    final cleanQuery = query.trim();
    final expectedDurationMs = int.tryParse(uri.queryParameters['durationMs'] ?? '');

    final cacheKey = directVideoId != null ? 'vid_$directVideoId' : cleanQuery;

    if (cacheKey.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'Missing query parameter q or videoId'}));
      await request.response.close();
      return;
    }

    if (_cache.containsKey(cacheKey)) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(_cache[cacheKey]));
      await request.response.close();
      return;
    }

    try {
      if (directVideoId != null && directVideoId.isNotEmpty) {
        final manifest = await _yt.videos.streamsClient.getManifest(VideoId(directVideoId));
        final audioStreams = manifest.audioOnly;
        if (audioStreams.isNotEmpty) {
          final bestAudio = audioStreams.withHighestBitrate();
          final data = {
            'streamUrl': bestAudio.url.toString(),
            'durationMs': expectedDurationMs ?? 200000,
            'bitrate': bestAudio.bitrate.kiloBitsPerSecond.round(),
            'format': bestAudio.container.name,
            'videoId': directVideoId,
            'title': 'YouTube Direct Audio',
          };
          if (_cache.length > 300) _cache.clear();
          _cache[cacheKey] = data;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(data));
          await request.response.close();
          return;
        }
      }

      final searchResults = await _yt.search.search(cleanQuery);
      if (searchResults.isNotEmpty) {
        final candidates = searchResults
            .where((v) => !v.isLive)
            .take(6)
            .toList();

        for (final candidate in candidates) {
          if (expectedDurationMs != null && candidate.duration != null) {
            final delta = (candidate.duration!.inMilliseconds - expectedDurationMs).abs();
            // If length delta is greater than 70s, skip (e.g. 10hr loop or short snippet)
            if (delta > 70000 && candidates.length > 1) continue;
          }

          try {
            final manifest = await _yt.videos.streamsClient.getManifest(candidate.id);
            final audioStreams = manifest.audioOnly;

            if (audioStreams.isNotEmpty) {
              final bestAudio = audioStreams.withHighestBitrate();
              final data = {
                'streamUrl': bestAudio.url.toString(),
                'durationMs': candidate.duration?.inMilliseconds ?? expectedDurationMs ?? 200000,
                'bitrate': bestAudio.bitrate.kiloBitsPerSecond.round(),
                'format': bestAudio.container.name,
                'videoId': candidate.id.value,
                'title': candidate.title,
              };
              if (_cache.length > 300) _cache.clear();
              _cache[cacheKey] = data;
              print('Resolved full-song master stream: "${candidate.title}" [${candidate.duration}] -> ${candidate.id.value}');
              request.response.headers.contentType = ContentType.json;
              request.response.write(jsonEncode(data));
              await request.response.close();
              return;
            }
          } catch (e) {
            print('Candidate ${candidate.id.value} stream manifest failed: $e');
            continue;
          }
        }
      }

      request.response.statusCode = HttpStatus.notFound;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'No audio stream found'}));
      await request.response.close();
    } catch (e) {
      print('Resolve endpoint error: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': e.toString()}));
      await request.response.close();
    }
    return;
  }

  // Static files from build/web
  String filePath = uri.path;
  if (filePath == '/' || filePath.isEmpty) {
    filePath = '/index.html';
  }

  final file = File('${webDir.path}$filePath');
  if (await file.exists()) {
    final mime = _getContentType(filePath);
    if (mime != null) {
      request.response.headers.contentType = mime;
    }
    await file.openRead().pipe(request.response);
  } else {
    // SPA fallback to index.html
    final indexFile = File('${webDir.path}/index.html');
    if (await indexFile.exists()) {
      request.response.headers.contentType = ContentType.html;
      await indexFile.openRead().pipe(request.response);
    } else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }
}

ContentType? _getContentType(String path) {
  if (path.endsWith('.html')) return ContentType.html;
  if (path.endsWith('.js')) return ContentType('application', 'javascript', charset: 'utf-8');
  if (path.endsWith('.css')) return ContentType('text', 'css', charset: 'utf-8');
  if (path.endsWith('.json')) return ContentType.json;
  if (path.endsWith('.png')) return ContentType('image', 'png');
  if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return ContentType('image', 'jpeg');
  if (path.endsWith('.svg')) return ContentType('image', 'svg+xml');
  if (path.endsWith('.wasm')) return ContentType('application', 'wasm');
  if (path.endsWith('.webp')) return ContentType('image', 'webp');
  return null;
}
