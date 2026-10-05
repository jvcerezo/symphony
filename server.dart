import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html_parser;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final Directory _cacheDir = Directory('.symphony_cache');
final File _playlistsFile = File('.symphony_cache/playlists.json');
final Map<String, Map<String, dynamic>> _resolveCache = {};
final Map<String, String> _remoteUrlCache = {};
final _yt = YoutubeExplode();
final _httpClient = HttpClient();

Future<void> main() async {
  final port = 8080;
  final webDir = Directory('build/web');

  if (!await webDir.exists()) {
    print('Error: build/web directory not found');
    return;
  }

  if (!await _cacheDir.exists()) {
    await _cacheDir.create(recursive: true);
  }

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('Symphony Full-Track Offline Server running on http://localhost:$port');

  await for (final request in server) {
    _handleRequest(request, webDir);
  }
}

Future<void> _handleRequest(HttpRequest request, Directory webDir) async {
  request.response.headers.add('Access-Control-Allow-Origin', '*');
  request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, HEAD');
  request.response.headers.add('Access-Control-Allow-Headers', '*');
  request.response.headers.add('Access-Control-Expose-Headers', 'Content-Range, Accept-Ranges, Content-Length');

  if (request.method == 'OPTIONS') {
    request.response.statusCode = HttpStatus.ok;
    await request.response.close();
    return;
  }

  final uri = request.uri;

  // 1. Offline & Online Audio Stream Endpoint: /api/stream?videoId=...
  if (uri.path == '/api/stream') {
    final videoId = uri.queryParameters['videoId'];
    if (videoId == null || videoId.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write('Missing videoId parameter');
      await request.response.close();
      return;
    }

    await _streamAudioBytes(request, videoId);
    return;
  }

  // 2. Full-track YouTube Audio Resolver API Endpoint: /api/resolve
  if (uri.path == '/api/resolve') {
    await _handleResolve(request);
    return;
  }

  // 3. Spotify Playlist Importer Endpoint: /api/playlist/spotify?id=...
  if (uri.path == '/api/playlist/spotify') {
    await _handleSpotifyPlaylist(request);
    return;
  }

  // 4. Saved Playlists Persistence Endpoint: /api/playlists
  if (uri.path == '/api/playlists') {
    await _handlePlaylists(request);
    return;
  }

  // 5. Static files from build/web with SPA routing
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

Future<void> _handleResolve(HttpRequest request) async {
  final uri = request.uri;
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

  if (_resolveCache.containsKey(cacheKey)) {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(_resolveCache[cacheKey]));
    await request.response.close();
    return;
  }

  try {
    String? resolvedVideoId = directVideoId;
    int durationMs = expectedDurationMs ?? 200000;
    String videoTitle = 'Audio Track';

    if (resolvedVideoId == null || resolvedVideoId.isEmpty) {
      final searchResults = await _yt.search.search(cleanQuery);
      if (searchResults.isNotEmpty) {
        final candidates = searchResults.where((v) => !v.isLive).take(5).toList();
        var best = candidates.first;

        for (final c in candidates) {
          if (expectedDurationMs != null && c.duration != null) {
            final delta = (c.duration!.inMilliseconds - expectedDurationMs).abs();
            if (delta < 45000) {
              best = c;
              break;
            }
          }
        }

        resolvedVideoId = best.id.value;
        durationMs = best.duration?.inMilliseconds ?? expectedDurationMs ?? 200000;
        videoTitle = best.title;
      }
    }

    if (resolvedVideoId != null) {
      final streamProxyUrl = '/api/stream?videoId=$resolvedVideoId';
      final data = {
        'streamUrl': streamProxyUrl,
        'durationMs': durationMs,
        'bitrate': 160,
        'format': 'webm',
        'videoId': resolvedVideoId,
        'title': videoTitle,
      };

      if (_resolveCache.length > 300) _resolveCache.clear();
      _resolveCache[cacheKey] = data;
      print('Resolved: "$videoTitle" [${durationMs ~/ 1000}s] -> $streamProxyUrl');

      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(data));
      await request.response.close();
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'error': 'No matching video found'}));
    await request.response.close();
  } catch (e) {
    print('Resolve error: $e');
    request.response.statusCode = HttpStatus.internalServerError;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'error': e.toString()}));
    await request.response.close();
  }
}

Future<void> _streamAudioBytes(HttpRequest request, String videoId) async {
  try {
    final cachedAudioFile = File('${_cacheDir.path}/audio_$videoId.webm');

    // 1. If audio is already cached locally, stream directly from disk (100% offline!)
    if (await cachedAudioFile.exists() && await cachedAudioFile.length() > 50000) {
      await _streamLocalFile(request, cachedAudioFile);
      return;
    }

    // 2. Resolve direct URL via yt-dlp -g
    String? remoteStreamUrl = _remoteUrlCache[videoId];
    if (remoteStreamUrl == null) {
      final result = await Process.run('python', [
        '-m',
        'yt_dlp',
        '-f',
        'ba',
        '-g',
        'https://www.youtube.com/watch?v=$videoId',
      ]);

      if (result.exitCode == 0) {
        final lines = (result.stdout as String).trim().split('\n');
        final candidateUrl = lines.last.trim();
        if (candidateUrl.startsWith('http')) {
          remoteStreamUrl = candidateUrl;
          _remoteUrlCache[videoId] = remoteStreamUrl;
        }
      }
    }

    if (remoteStreamUrl == null) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Audio stream extraction failed for $videoId');
      await request.response.close();
      return;
    }

    // 3. Connect to stream via Dart HttpClient
    final remoteUri = Uri.parse(remoteStreamUrl);
    final remoteReq = await _httpClient.getUrl(remoteUri);

    final clientRange = request.headers.value('range');
    if (clientRange != null) {
      remoteReq.headers.set('Range', clientRange);
    }
    remoteReq.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');

    final remoteRes = await remoteReq.close();
    request.response.statusCode = remoteRes.statusCode;

    if (remoteRes.headers.contentType != null) {
      request.response.headers.contentType = remoteRes.headers.contentType;
    } else {
      request.response.headers.set('Content-Type', 'audio/webm');
    }

    request.response.headers.set('Accept-Ranges', 'bytes');
    final contentRange = remoteRes.headers.value('content-range');
    if (contentRange != null) {
      request.response.headers.set('Content-Range', contentRange);
    }
    if (remoteRes.contentLength != -1) {
      request.response.contentLength = remoteRes.contentLength;
    }

    // Stream to client
    await remoteRes.pipe(request.response);

    // 4. Cache full track to disk in background if not already cached
    if (!await cachedAudioFile.exists()) {
      _cacheTrackInBackground(remoteStreamUrl, cachedAudioFile);
    }
  } catch (e) {
    try {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    } catch (_) {}
  }
}

Future<void> _cacheTrackInBackground(String streamUrl, File targetFile) async {
  try {
    final req = await _httpClient.getUrl(Uri.parse(streamUrl));
    req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
    final res = await req.close();
    if (res.statusCode == 200 || res.statusCode == 206) {
      final sink = targetFile.openWrite();
      await res.pipe(sink);
      print('Saved track to offline cache: ${targetFile.path} (${await targetFile.length()} bytes)');
    }
  } catch (e) {
    print('Background cache error: $e');
  }
}

Future<void> _streamLocalFile(HttpRequest request, File file) async {
  final totalSize = await file.length();
  final rangeHeader = request.headers.value('range');

  request.response.headers.add('Access-Control-Allow-Origin', '*');
  request.response.headers.add('Accept-Ranges', 'bytes');
  request.response.headers.add('Content-Type', 'audio/webm');

  if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
    final parts = rangeHeader.substring(6).split('-');
    final start = int.tryParse(parts[0]) ?? 0;
    final end = parts.length > 1 && parts[1].isNotEmpty
        ? int.tryParse(parts[1]) ?? (totalSize - 1)
        : totalSize - 1;
    final chunkLen = (end - start + 1).clamp(0, totalSize);

    request.response.statusCode = HttpStatus.partialContent;
    request.response.headers.set('Content-Range', 'bytes $start-$end/$totalSize');
    request.response.contentLength = chunkLen;
    await file.openRead(start, end + 1).pipe(request.response);
  } else {
    request.response.statusCode = HttpStatus.ok;
    request.response.contentLength = totalSize;
    await file.openRead().pipe(request.response);
  }
}

Future<void> _handlePlaylists(HttpRequest request) async {
  request.response.headers.contentType = ContentType.json;

  if (request.method == 'GET') {
    if (await _playlistsFile.exists()) {
      final content = await _playlistsFile.readAsString();
      request.response.write(content);
    } else {
      request.response.write('[]');
    }
    await request.response.close();
    return;
  }

  if (request.method == 'POST') {
    try {
      final body = await utf8.decodeStream(request);
      final newPlaylist = jsonDecode(body) as Map<String, dynamic>;

      List<dynamic> existing = [];
      if (await _playlistsFile.exists()) {
        try {
          existing = jsonDecode(await _playlistsFile.readAsString()) as List<dynamic>;
        } catch (_) {}
      }

      existing.removeWhere((p) => p is Map && p['id'] == newPlaylist['id']);
      existing.insert(0, newPlaylist);

      await _playlistsFile.writeAsString(jsonEncode(existing));
      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode({'success': true, 'count': existing.length}));
    } catch (e) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(jsonEncode({'error': e.toString()}));
    }
    await request.response.close();
    return;
  }
}

Future<void> _handleSpotifyPlaylist(HttpRequest request) async {
  final id = request.uri.queryParameters['id'] ?? '';
  final playlistId = id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').trim();

  if (playlistId.isEmpty) {
    request.response.statusCode = HttpStatus.badRequest;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'error': 'Missing or invalid playlist id'}));
    await request.response.close();
    return;
  }

  try {
    final targetUrl = 'https://open.spotify.com/embed/playlist/$playlistId';
    print('Scraping Spotify playlist on server: $targetUrl');

    final embedReq = await _httpClient.getUrl(Uri.parse(targetUrl));
    embedReq.headers.set(
      'User-Agent',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    );
    embedReq.headers.set('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');

    final embedRes = await embedReq.close();
    if (embedRes.statusCode != 200) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'Spotify embed returned status ${embedRes.statusCode}'}));
      await request.response.close();
      return;
    }

    final htmlBody = await utf8.decodeStream(embedRes);
    if (!htmlBody.contains('__NEXT_DATA__')) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'Spotify playlist data not found or private'}));
      await request.response.close();
      return;
    }

    final doc = html_parser.parse(htmlBody);
    final script = doc.getElementById('__NEXT_DATA__');
    if (script == null || script.text.isEmpty) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'No __NEXT_DATA__ element'}));
      await request.response.close();
      return;
    }

    final jsonData = jsonDecode(script.text) as Map<String, dynamic>;
    final entity = jsonData['props']?['pageProps']?['state']?['data']?['entity'];

    if (entity == null) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': 'No playlist entity in data'}));
      await request.response.close();
      return;
    }

    final title = entity['name'] as String? ?? 'Imported Playlist';
    final description = entity['description'] as String?;
    final ownerName = entity['owner']?['name'] as String? ?? 'Spotify User';

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
      coverUrl = coverUrl.replaceAll('00000001', '00000003').replaceAll('00000002', '00000003');
    }

    final rawTracks = (entity['trackList'] as List<dynamic>?) ?? [];
    final List<Map<String, dynamic>> tracks = [];

    for (int i = 0; i < rawTracks.length; i++) {
      final item = rawTracks[i] as Map<String, dynamic>;
      final trackTitle = item['title'] as String? ?? 'Unknown Title';
      final artist = item['subtitle'] as String? ?? 'Unknown Artist';
      final durationMs = item['duration'] as int? ?? 0;
      final uriStr = item['uri'] as String? ?? 'spotify:track:$i';

      tracks.add({
        'id': uriStr,
        'title': trackTitle,
        'artist': artist,
        'album': title,
        'durationMs': durationMs,
        'artworkUri': null,
      });
    }

    print('Successfully parsed Spotify playlist "$title" ($playlistId) with ${tracks.length} tracks');

    final responsePayload = {
      'id': playlistId,
      'title': title,
      'description': description,
      'coverUrl': coverUrl,
      'ownerName': ownerName,
      'tracks': tracks,
    };

    // Automatically persist to offline storage
    try {
      List<dynamic> existing = [];
      if (await _playlistsFile.exists()) {
        try {
          existing = jsonDecode(await _playlistsFile.readAsString()) as List<dynamic>;
        } catch (_) {}
      }
      existing.removeWhere((p) => p is Map && p['id'] == playlistId);
      existing.insert(0, responsePayload);
      await _playlistsFile.writeAsString(jsonEncode(existing));
    } catch (_) {}

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(responsePayload));
    await request.response.close();
  } catch (e) {
    print('Spotify import error: $e');
    request.response.statusCode = HttpStatus.internalServerError;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'error': e.toString()}));
    await request.response.close();
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
