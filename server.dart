import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html_parser;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final Directory _cacheDir = Directory('.symphony_cache');
final File _playlistsFile = File('.symphony_cache/playlists.json');
final File _resolveIndexFile = File('.symphony_cache/resolve_index.json');
final Map<String, Map<String, dynamic>> _resolveCache = {};
final Map<String, String> _remoteUrlCache = {};
final _yt = YoutubeExplode();
final _httpClient = HttpClient();

String _normalizeKey(String s) {
  return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

Future<void> _loadResolveIndex() async {
  if (await _resolveIndexFile.exists()) {
    try {
      final content = await _resolveIndexFile.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        if (entry.value is Map<String, dynamic>) {
          _resolveCache[entry.key] = entry.value as Map<String, dynamic>;
        }
      }
      print('Loaded ${_resolveCache.length} track mappings from resolve index.');
    } catch (e) {
      print('Error reading resolve index: $e');
    }
  }
}

void _saveResolveEntry(String primaryKey, Map<String, dynamic> data, {String? artist, String? title, String? trackId}) {
  _resolveCache[primaryKey] = data;
  final vid = data['videoId'] as String?;
  if (vid != null) {
    _resolveCache['vid_$vid'] = data;
    _resolveCache[vid] = data;
  }
  if (trackId != null && trackId.isNotEmpty) {
    _resolveCache['track_$trackId'] = data;
    _resolveCache[trackId] = data;
  }
  if (artist != null && title != null && artist.isNotEmpty && title.isNotEmpty) {
    final norm = '${_normalizeKey(artist)} - ${_normalizeKey(title)}';
    _resolveCache[norm] = data;
    _resolveCache['${artist.toLowerCase()} - ${title.toLowerCase()}'] = data;
  }
  try {
    _resolveIndexFile.writeAsStringSync(jsonEncode(_resolveCache));
  } catch (e) {
    print('Error persisting resolve index: $e');
  }
}

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

  await _loadResolveIndex();

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

  // 5. Offline Status Endpoint: /api/offline/status?ids=id1,id2
  if (uri.path == '/api/offline/status') {
    await _handleOfflineStatus(request);
    return;
  }

  // 6. Explicit Track/Playlist Download Endpoint: /api/offline/download
  if (uri.path == '/api/offline/download') {
    await _handleExplicitDownload(request);
    return;
  }

  // 7. Static files from build/web with SPA routing
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
  final artist = uri.queryParameters['artist'] ?? '';
  final title = uri.queryParameters['title'] ?? '';
  final trackId = uri.queryParameters['id'] ?? uri.queryParameters['trackId'];
  final query = uri.queryParameters['q'] ??
      '${artist.isNotEmpty ? "$artist - " : ""}$title official audio';
  final cleanQuery = query.trim();
  final expectedDurationMs = int.tryParse(uri.queryParameters['durationMs'] ?? '');

  final cacheKey = directVideoId != null ? 'vid_$directVideoId' : cleanQuery;
  final normKey = (artist.isNotEmpty && title.isNotEmpty)
      ? '${_normalizeKey(artist)} - ${_normalizeKey(title)}'
      : _normalizeKey(cleanQuery);

  if (cacheKey.isEmpty && normKey.isEmpty) {
    request.response.statusCode = HttpStatus.badRequest;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'error': 'Missing query parameter q or videoId'}));
    await request.response.close();
    return;
  }

  // 1. Check in-memory / persistent resolve cache
  Map<String, dynamic>? cachedData = _resolveCache[cacheKey] ??
      _resolveCache[normKey] ??
      (trackId != null ? (_resolveCache['track_$trackId'] ?? _resolveCache[trackId]) : null);

  if (cachedData != null) {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(cachedData));
    await request.response.close();
    return;
  }

  try {
    String? resolvedVideoId = directVideoId;
    int durationMs = expectedDurationMs ?? 200000;
    String videoTitle = title.isNotEmpty ? '$artist - $title' : 'Audio Track';

    if (resolvedVideoId == null || resolvedVideoId.isEmpty) {
      try {
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
      } catch (searchError) {
        print('YouTube search error (offline?): $searchError');
        // Offline recovery: search for any entry in _resolveCache matching artist or title
        for (final entry in _resolveCache.values) {
          final eTitle = (entry['title'] as String? ?? '').toLowerCase();
          final eArtist = (entry['artist'] as String? ?? '').toLowerCase();
          final tLower = title.toLowerCase();
          final aLower = artist.toLowerCase();
          if ((tLower.isNotEmpty && eTitle.contains(tLower)) ||
              (aLower.isNotEmpty && eArtist.contains(aLower))) {
            final vid = entry['videoId'] as String?;
            if (vid != null) {
              final cachedFile = File('${_cacheDir.path}/audio_$vid.webm');
              if (cachedFile.existsSync() && cachedFile.lengthSync() > 50000) {
                resolvedVideoId = vid;
                durationMs = entry['durationMs'] as int? ?? 200000;
                videoTitle = entry['title'] as String? ?? videoTitle;
                break;
              }
            }
          }
        }
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
        'artist': artist,
        if (trackId != null) 'trackId': trackId,
      };

      _saveResolveEntry(cacheKey, data, artist: artist, title: title, trackId: trackId);
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

Future<void> _handleOfflineStatus(HttpRequest request) async {
  request.response.headers.contentType = ContentType.json;
  final idsParam = request.uri.queryParameters['ids'];

  if (idsParam == null || idsParam.isEmpty) {
    final cachedVideoIds = <String>[];
    if (await _cacheDir.exists()) {
      for (final entity in _cacheDir.listSync()) {
        if (entity is File &&
            entity.path.contains('audio_') &&
            entity.path.endsWith('.webm') &&
            entity.lengthSync() > 50000) {
          final base = entity.uri.pathSegments.last;
          final vid = base.replaceFirst('audio_', '').replaceFirst('.webm', '');
          cachedVideoIds.add(vid);
        }
      }
    }

    final cachedKeys = <String>[];
    for (final entry in _resolveCache.entries) {
      final vid = entry.value['videoId'] as String?;
      if (vid != null && cachedVideoIds.contains(vid)) {
        cachedKeys.add(entry.key);
      }
    }

    request.response.write(jsonEncode({
      'cachedVideoIds': cachedVideoIds,
      'cachedKeys': cachedKeys,
    }));
    await request.response.close();
    return;
  }

  final ids = idsParam.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  final statusMap = <String, bool>{};

  for (final id in ids) {
    bool isCached = false;
    final directFile = File('${_cacheDir.path}/audio_$id.webm');
    if (directFile.existsSync() && directFile.lengthSync() > 50000) {
      isCached = true;
    } else {
      final entry = _resolveCache[id] ??
          _resolveCache['track_$id'] ??
          _resolveCache['vid_$id'] ??
          _resolveCache[_normalizeKey(id)];
      if (entry != null) {
        final vid = entry['videoId'] as String?;
        if (vid != null) {
          final f = File('${_cacheDir.path}/audio_$vid.webm');
          if (f.existsSync() && f.lengthSync() > 50000) {
            isCached = true;
          }
        }
      }
    }
    statusMap[id] = isCached;
  }

  request.response.write(jsonEncode(statusMap));
  await request.response.close();
}

Future<void> _handleExplicitDownload(HttpRequest request) async {
  request.response.headers.contentType = ContentType.json;
  try {
    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;

    // 1. Single track download by videoId
    if (data.containsKey('videoId')) {
      final videoId = data['videoId'] as String;
      final file = File('${_cacheDir.path}/audio_$videoId.webm');

      if (await file.exists() && await file.length() > 50000) {
        request.response.write(jsonEncode({'success': true, 'videoId': videoId, 'alreadyCached': true}));
        await request.response.close();
        return;
      }

      final success = await _downloadTrackToDisk(videoId);
      request.response.write(jsonEncode({'success': success, 'videoId': videoId}));
      await request.response.close();
      return;
    }

    // 2. Single track download by track object
    if (data.containsKey('track')) {
      final track = data['track'] as Map<String, dynamic>;
      final videoId = await _resolveAndDownloadSingleTrack(track);
      request.response.write(jsonEncode({'success': videoId != null, 'videoId': videoId}));
      await request.response.close();
      return;
    }

    // 3. Playlist / batch tracks download
    if (data.containsKey('tracks')) {
      final tracks = data['tracks'] as List<dynamic>;
      _batchDownloadTracks(tracks);
      request.response.write(jsonEncode({
        'success': true,
        'message': 'Downloading ${tracks.length} tracks for offline playback in background',
        'count': tracks.length,
      }));
      await request.response.close();
      return;
    }

    request.response.statusCode = HttpStatus.badRequest;
    request.response.write(jsonEncode({'error': 'Missing videoId, track, or tracks array'}));
    await request.response.close();
  } catch (e) {
    request.response.statusCode = HttpStatus.internalServerError;
    request.response.write(jsonEncode({'error': e.toString()}));
    await request.response.close();
  }
}

Future<String?> _resolveAndDownloadSingleTrack(Map<String, dynamic> track) async {
  final artist = track['artist'] as String? ?? '';
  final title = track['title'] as String? ?? '';
  final trackId = track['id'] as String? ?? '';
  final durationMs = track['durationMs'] as int? ?? 200000;

  try {
    final normKey = '${_normalizeKey(artist)} - ${_normalizeKey(title)}';
    String? videoId;
    if (_resolveCache.containsKey(normKey)) {
      videoId = _resolveCache[normKey]!['videoId'] as String?;
    } else if (trackId.isNotEmpty && _resolveCache.containsKey('track_$trackId')) {
      videoId = _resolveCache['track_$trackId']!['videoId'] as String?;
    }

    if (videoId == null || videoId.isEmpty) {
      final query = '$artist - $title official audio';
      final searchResults = await _yt.search.search(query);
      if (searchResults.isNotEmpty) {
        final video = searchResults.firstWhere((v) => !v.isLive, orElse: () => searchResults.first);
        videoId = video.id.value;
      }
    }

    if (videoId != null && videoId.isNotEmpty) {
      final entryData = {
        'streamUrl': '/api/stream?videoId=$videoId',
        'durationMs': durationMs,
        'bitrate': 160,
        'format': 'webm',
        'videoId': videoId,
        'title': title,
        'artist': artist,
        if (trackId.isNotEmpty) 'trackId': trackId,
      };
      _saveResolveEntry('$artist - $title official audio', entryData, artist: artist, title: title, trackId: trackId);
      final ok = await _downloadTrackToDisk(videoId);
      return ok ? videoId : null;
    }
  } catch (e) {
    print('Failed to resolve and download track "$title" by "$artist": $e');
  }
  return null;
}

Future<bool> _downloadTrackToDisk(String videoId) async {
  final targetFile = File('${_cacheDir.path}/audio_$videoId.webm');
  if (await targetFile.exists() && await targetFile.length() > 50000) {
    return true;
  }

  try {
    String? streamUrl = _remoteUrlCache[videoId];
    if (streamUrl == null) {
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
        streamUrl = lines.last.trim();
        _remoteUrlCache[videoId] = streamUrl;
      }
    }

    if (streamUrl != null && streamUrl.startsWith('http')) {
      final req = await _httpClient.getUrl(Uri.parse(streamUrl));
      req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
      final res = await req.close();
      if (res.statusCode == 200 || res.statusCode == 206) {
        final sink = targetFile.openWrite();
        await res.pipe(sink);
        print('Downloaded and cached: ${targetFile.path} (${await targetFile.length()} bytes)');
        return true;
      }
    }
  } catch (e) {
    print('Track download error for $videoId: $e');
  }
  return false;
}

void _batchDownloadTracks(List<dynamic> tracks) async {
  print('Starting batch playlist download of ${tracks.length} tracks...');
  for (final track in tracks) {
    if (track is Map<String, dynamic>) {
      await _resolveAndDownloadSingleTrack(track);
    }
  }
  print('Finished batch playlist download of ${tracks.length} tracks!');
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
