import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html_parser;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

final Directory _cacheDir = Directory('.symphony_cache');
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

      // Sanitize cache: automatically purge any bad entries (> 11 mins or gaming/podcast redflags)
      final keysToRemove = <String>[];
      for (final entry in _resolveCache.entries) {
        final val = entry.value;
        final dMs = val['durationMs'] as int? ?? 0;
        final t = (val['title'] as String? ?? '').toLowerCase();
        final vid = val['videoId'] as String?;
        bool isBad = false;
        if (dMs > 660000) isBad = true; // > 11 mins
        for (final rf in ['gameplay', 'walkthrough', 'playthrough', 'podcast', 'elden ring', '1shotplays', 'part 23', 'live stream']) {
          if (t.contains(rf)) isBad = true;
        }
        if (isBad) {
          keysToRemove.add(entry.key);
          if (vid != null) {
            final f = File('${_cacheDir.path}/audio_$vid.webm');
            if (f.existsSync()) {
              try { f.deleteSync(); } catch (_) {}
            }
          }
        }
      }
      for (final k in keysToRemove) {
        _resolveCache.remove(k);
      }
      if (keysToRemove.isNotEmpty) {
        print('Purged ${keysToRemove.length} invalid entries from resolve cache.');
        try {
          _resolveIndexFile.writeAsStringSync(jsonEncode(_resolveCache));
        } catch (_) {}
      }

      print('Loaded ${_resolveCache.length} track mappings from resolve index.');
    } catch (e) {
      print('Error reading resolve index: $e');
    }
  }
}

void _saveResolveEntry(String primaryKey, Map<String, dynamic> data, {String? artist, String? title, String? trackId}) {
  final dMs = data['durationMs'] as int? ?? 0;
  final vTitle = (data['title'] as String? ?? '').toLowerCase();
  // Never save tracks > 11 minutes or tracks with red flag keywords into cache
  if (dMs > 660000) return;
  for (final rf in ['gameplay', 'walkthrough', 'playthrough', 'podcast', 'elden ring', '1shotplays', 'part 23', 'live stream']) {
    if (vTitle.contains(rf)) return;
  }

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

const int _defaultCacheQuotaBytes = 3 * 1024 * 1024 * 1024; // 3 GB quota

Future<void> _cleanStaleTempFiles() async {
  if (await _cacheDir.exists()) {
    int count = 0;
    for (final entity in _cacheDir.listSync()) {
      if (entity is File && entity.path.endsWith('.tmp')) {
        try {
          entity.deleteSync();
          count++;
        } catch (_) {}
      }
    }
    if (count > 0) {
      print('Cleaned up $count stale temporary download files.');
    }
  }
}

Future<void> _enforceCacheQuota({int quotaBytes = _defaultCacheQuotaBytes}) async {
  if (!await _cacheDir.exists()) return;

  final audioFiles = <File>[];
  int totalBytes = 0;

  for (final entity in _cacheDir.listSync()) {
    if (entity is File && entity.path.contains('audio_') && entity.path.endsWith('.webm')) {
      audioFiles.add(entity);
      totalBytes += entity.lengthSync();
    }
  }

  if (totalBytes <= quotaBytes) return;

  // Sort LRU: oldest modified first
  audioFiles.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

  final targetBytes = (quotaBytes * 0.8).round();
  int evictedCount = 0;

  for (final file in audioFiles) {
    if (totalBytes <= targetBytes) break;
    final size = file.lengthSync();
    try {
      file.deleteSync();
      totalBytes -= size;
      evictedCount++;
    } catch (_) {}
  }

  if (evictedCount > 0) {
    print('LRU Cache quota enforced: evicted $evictedCount transient tracks. New cache size: ${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB');
  }
}

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final webDir = Directory(Platform.environment['WEB_DIR'] ?? 'build/web');

  if (!await webDir.exists()) {
    print('Warning: build/web directory not found at ${webDir.path}');
  }

  if (!await _cacheDir.exists()) {
    await _cacheDir.create(recursive: true);
  }

  await _cleanStaleTempFiles();
  await _loadResolveIndex();
  await _enforceCacheQuota();

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

  // 7. Cache Info & Data Retention Status: /api/offline/cache-info
  if (uri.path == '/api/offline/cache-info') {
    await _handleCacheInfo(request);
    return;
  }

  // 8. User Cache Eviction & Cleanup: /api/offline/clear
  if (uri.path == '/api/offline/clear') {
    await _handleClearCache(request);
    return;
  }

  // 9. Cleanly Uninstall/Delete Downloaded Playlist Cache: /api/offline/delete-playlist
  if (uri.path == '/api/offline/delete-playlist') {
    await _handleDeletePlaylistCache(request);
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
    final length = await file.length();
    request.response.headers.contentLength = length;
    if (filePath.endsWith('.apk')) {
      request.response.headers.add('Content-Disposition', 'attachment; filename="symphony.apk"');
    }
    if (filePath.endsWith('.html') || filePath.endsWith('.js') || filePath.endsWith('.json')) {
      request.response.headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
      request.response.headers.set('Pragma', 'no-cache');
      request.response.headers.set('Expires', '0');
    }
    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }
    await file.openRead().pipe(request.response);
  } else {
    // SPA fallback to index.html
    final indexFile = File('${webDir.path}/index.html');
    if (await indexFile.exists()) {
      request.response.headers.contentType = ContentType.html;
      request.response.headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
      request.response.headers.set('Pragma', 'no-cache');
      request.response.headers.set('Expires', '0');
      await indexFile.openRead().pipe(request.response);
    } else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }
}

int _scoreVideoCandidate({
  required String videoTitle,
  required String videoAuthor,
  required int durationSec,
  required String targetTitle,
  required String targetArtist,
  int? expectedDurationMs,
}) {
  final vTitle = videoTitle.toLowerCase();
  final vAuthor = videoAuthor.toLowerCase();
  final tTitle = targetTitle.toLowerCase();
  final tArtist = targetArtist.toLowerCase();
  final expectedSec = expectedDurationMs != null ? (expectedDurationMs ~/ 1000) : 210;

  // 1. Hard disqualification: Videos > 11 minutes (660s) when expected track is normal song (< 9 mins)
  if (durationSec > 660 && expectedSec < 540) {
    return -9999;
  }
  // If expected duration is known, any video differing by > 80 seconds is rejected
  if (expectedDurationMs != null && expectedSec > 30 && (durationSec - expectedSec).abs() > 80 && expectedSec < 600) {
    return -9999;
  }
  // Videos < 45 seconds when expected track is > 60s
  if (durationSec < 45 && expectedSec > 60) {
    return -9999;
  }

  // 2. Disqualify obvious gameplay, walkthroughs, podcasts, non-music
  final redFlags = [
    'gameplay',
    'walkthrough',
    'playthrough',
    'lets play',
    'let\'s play',
    'podcast',
    'full album',
    'part 1',
    'part 2',
    'part 3',
    'part 4',
    'part 5',
    'part 6',
    'part 7',
    'part 8',
    'part 9',
    'part 10',
    'part 11',
    'part 12',
    'part 13',
    'part 14',
    'part 15',
    'part 16',
    'part 17',
    'part 18',
    'part 19',
    'part 20',
    'part 21',
    'part 22',
    'part 23',
    'episode ',
    'ep 1',
    'ep 2',
    'ep 3',
    'ep 4',
    'ep 5',
    'live stream',
    'livestream',
    'stream vod',
    'vod',
    'reaction',
    'reacts to',
    'reacting to',
    'elden ring',
    '1shotplays',
    'roblox',
    'minecraft',
    'fortnite',
    'gta',
    'review',
    'tier list',
    'unboxing',
    'speedrun',
    'boss fight',
    'cutscenes',
    'tutorial',
    '10 hours',
    '10 hour',
    '1 hour loop',
    'hour loop',
    '100 hours',
    'extended loop',
    'nightcore',
    'slowed + reverb',
    'slowed and reverb',
    '8d audio',
    'bass boosted',
    'pitch shifted',
    'parody',
    'cover by',
    'karaoke',
    'synthesia',
    'piano tutorial',
    'guitar tutorial',
    'guitar tab',
    'ai cover',
  ];
  for (final rf in redFlags) {
    if (vTitle.contains(rf) || vAuthor.contains(rf)) return -9999;
  }

  int score = 0;

  // 3. Match title keywords (MANDATORY)
  final cleanTTitle = tTitle.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').trim();
  final titleWords = cleanTTitle.split(RegExp(r'\s+')).where((w) => w.length >= 3).toList();
  int matchedTitleWords = 0;
  for (final w in titleWords) {
    if (vTitle.contains(w)) matchedTitleWords++;
  }
  if (titleWords.isNotEmpty) {
    if (matchedTitleWords == titleWords.length) {
      score += 70; // All title words matched
    } else if (matchedTitleWords > 0) {
      score += ((matchedTitleWords / titleWords.length) * 50).round();
    } else {
      // NONE of the title words matched: absolute disqualification
      return -9999;
    }
  }

  // Exact clean title substring match bonus
  if (cleanTTitle.isNotEmpty && vTitle.contains(cleanTTitle)) {
    score += 30;
  }

  // 4. Match artist keywords & Topic Channel
  final cleanTArtist = tArtist.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').trim();
  final artistWords = cleanTArtist.split(RegExp(r'\s+')).where((w) => w.length >= 3).toList();
  int matchedArtistWords = 0;
  for (final w in artistWords) {
    if (vTitle.contains(w) || vAuthor.contains(w)) {
      matchedArtistWords++;
    }
  }
  if (artistWords.isNotEmpty) {
    if (matchedArtistWords > 0) {
      score += 35;
    } else if (!vAuthor.contains('topic')) {
      score -= 30; // Artist name not found in title or channel
    }
  }

  // YouTube Music Topic Channel (official automated aggregator release: TuneCore, DistroKid, etc.)
  if (vAuthor.endsWith(' - topic') || vAuthor.contains('topic')) {
    score += 85;
  }

  // 5. Official audio indicators
  if (vTitle.contains('official audio')) {
    score += 45;
  } else if (vTitle.contains('official lyric video') || vTitle.contains('official visualizer')) {
    score += 40;
  } else if (vTitle.contains('official music video') || vTitle.contains('official video')) {
    score += 35;
  } else if (vTitle.contains('audio')) {
    score += 15;
  }

  // 6. Duration proximity
  final diffSec = (durationSec - expectedSec).abs();
  if (diffSec <= 5) {
    score += 50;
  } else if (diffSec <= 15) {
    score += 35;
  } else if (diffSec <= 35) {
    score += 15;
  } else if (diffSec > 50) {
    score -= 30;
  } else if (diffSec > 70) {
    score -= 100;
  }

  return score;
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
        final searchQueries = <String>[];
        if (artist.isNotEmpty && title.isNotEmpty) {
          searchQueries.add('$artist $title topic');
          searchQueries.add('$artist - $title official audio');
          searchQueries.add('$artist - $title');
          searchQueries.add('$title $artist');
        } else {
          searchQueries.add(cleanQuery);
        }

        final seenVideoIds = <String>{};
        final scoredCandidates = <({Video video, int score})>[];

        for (final sq in searchQueries) {
          try {
            final results = await _yt.search.search(sq);
            for (final v in results.take(6)) {
              if (v.isLive) continue;
              if (seenVideoIds.add(v.id.value)) {
                final sc = _scoreVideoCandidate(
                  videoTitle: v.title,
                  videoAuthor: v.author,
                  durationSec: v.duration?.inSeconds ?? 0,
                  targetTitle: title.isNotEmpty ? title : cleanQuery,
                  targetArtist: artist,
                  expectedDurationMs: expectedDurationMs,
                );
                if (sc > 0) {
                  scoredCandidates.add((video: v, score: sc));
                }
              }
            }
            if (scoredCandidates.isNotEmpty && scoredCandidates.any((c) => c.score >= 120)) {
              break;
            }
          } catch (_) {}
        }

        if (scoredCandidates.isNotEmpty) {
          scoredCandidates.sort((a, b) => b.score.compareTo(a.score));
          final topCandidate = scoredCandidates.first;
          if (topCandidate.score >= 50) {
            final best = topCandidate.video;
            resolvedVideoId = best.id.value;
            durationMs = best.duration?.inMilliseconds ?? expectedDurationMs ?? 200000;
            videoTitle = best.title;
          } else {
            print('Top candidate rejected due to low confidence score (${topCandidate.score}): "${topCandidate.video.title}"');
          }
        }
      } catch (searchError) {
        print('YouTube search error (offline?): $searchError');
        // Offline recovery: search for any entry in _resolveCache matching artist AND title
        for (final entry in _resolveCache.values) {
          final eTitle = (entry['title'] as String? ?? '').toLowerCase();
          final eArtist = (entry['artist'] as String? ?? '').toLowerCase();
          final tLower = title.toLowerCase();
          final aLower = artist.toLowerCase();
          final titleMatches = tLower.isNotEmpty && (eTitle.contains(tLower) || tLower.contains(eTitle));
          final artistMatches = aLower.isEmpty || eArtist.contains(aLower) || aLower.contains(eArtist);
          if (titleMatches && artistMatches) {
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

    // 2. Resolve direct URL via yt-dlp -g with youtube_explode fallback
    String? remoteStreamUrl = _remoteUrlCache[videoId];
    if (remoteStreamUrl == null) {
      try {
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
      } catch (_) {}
    }

    if (remoteStreamUrl == null) {
      try {
        final manifest = await _yt.videos.streamsClient.getManifest(videoId);
        final audioStreams = manifest.audioOnly;
        if (audioStreams.isNotEmpty) {
          final aacStreams = audioStreams.where((s) =>
              s.container.name == 'mp4' ||
              s.codec.mimeType.contains('mp4') ||
              s.codec.mimeType.contains('aac'));
          final bestAudio = aacStreams.isNotEmpty
              ? aacStreams.withHighestBitrate()
              : audioStreams.withHighestBitrate();
          remoteStreamUrl = bestAudio.url.toString();
          _remoteUrlCache[videoId] = remoteStreamUrl;
        }
      } catch (ytErr) {
        print('YoutubeExplode direct stream extraction fallback failed for $videoId: $ytErr');
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
  final tmpFile = File('${targetFile.path}.tmp');
  try {
    final req = await _httpClient.getUrl(Uri.parse(streamUrl));
    req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
    final res = await req.close();
    if (res.statusCode == 200 || res.statusCode == 206) {
      final sink = tmpFile.openWrite();
      await res.pipe(sink);
      if (await tmpFile.exists() && await tmpFile.length() > 50000) {
        if (await targetFile.exists()) {
          try {
            await targetFile.delete();
          } catch (_) {}
        }
        await tmpFile.rename(targetFile.path);
        print('Saved track to offline cache: ${targetFile.path} (${await targetFile.length()} bytes)');
      } else {
        if (await tmpFile.exists()) await tmpFile.delete();
      }
    }
  } catch (e) {
    print('Background cache error: $e');
    if (await tmpFile.exists()) {
      try {
        await tmpFile.delete();
      } catch (_) {}
    }
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

    // Handle range requests at or beyond EOF: return 416 so player recognizes EOF cleanly
    if (start >= totalSize) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set('Content-Range', 'bytes */$totalSize');
      await request.response.close();
      return;
    }

    final end = parts.length > 1 && parts[1].isNotEmpty
        ? (int.tryParse(parts[1]) ?? (totalSize - 1))
        : totalSize - 1;
    final safeEnd = end.clamp(start, totalSize - 1);
    final chunkLen = safeEnd - start + 1;

    request.response.statusCode = HttpStatus.partialContent;
    request.response.headers.set('Content-Range', 'bytes $start-$safeEnd/$totalSize');
    request.response.contentLength = chunkLen;
    await file.openRead(start, safeEnd + 1).pipe(request.response);
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
      final searchQueries = <String>[];
      if (artist.isNotEmpty && title.isNotEmpty) {
        searchQueries.add('$artist $title topic');
        searchQueries.add('$artist - $title official audio');
        searchQueries.add('$artist - $title');
        searchQueries.add('$title $artist');
      } else {
        searchQueries.add('$artist $title');
      }

      final seenVideoIds = <String>{};
      final scoredCandidates = <({Video video, int score})>[];

      for (final sq in searchQueries) {
        try {
          final searchResults = await _yt.search.search(sq);
          for (final v in searchResults.take(6)) {
            if (v.isLive) continue;
            if (seenVideoIds.add(v.id.value)) {
              final sc = _scoreVideoCandidate(
                videoTitle: v.title,
                videoAuthor: v.author,
                durationSec: v.duration?.inSeconds ?? 0,
                targetTitle: title,
                targetArtist: artist,
                expectedDurationMs: durationMs,
              );
              if (sc > 0) {
                scoredCandidates.add((video: v, score: sc));
              }
            }
          }
          if (scoredCandidates.isNotEmpty && scoredCandidates.any((c) => c.score >= 120)) {
            break;
          }
        } catch (_) {}
      }

      if (scoredCandidates.isNotEmpty) {
        scoredCandidates.sort((a, b) => b.score.compareTo(a.score));
        final topCandidate = scoredCandidates.first;
        if (topCandidate.score >= 50) {
          videoId = topCandidate.video.id.value;
        } else {
          print('Single track download rejected due to low confidence score (${topCandidate.score}): "${topCandidate.video.title}"');
        }
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
      try {
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
      } catch (_) {}
    }

    if (streamUrl == null) {
      try {
        final manifest = await _yt.videos.streamsClient.getManifest(videoId);
        final audioStreams = manifest.audioOnly;
        if (audioStreams.isNotEmpty) {
          final aacStreams = audioStreams.where((s) =>
              s.container.name == 'mp4' ||
              s.codec.mimeType.contains('mp4') ||
              s.codec.mimeType.contains('aac'));
          final bestAudio = aacStreams.isNotEmpty
              ? aacStreams.withHighestBitrate()
              : audioStreams.withHighestBitrate();
          streamUrl = bestAudio.url.toString();
          _remoteUrlCache[videoId] = streamUrl;
        }
      } catch (ytErr) {
        print('YoutubeExplode direct stream extraction download fallback failed for $videoId: $ytErr');
      }
    }

    if (streamUrl != null && streamUrl.startsWith('http')) {
      final tmpFile = File('${targetFile.path}.tmp');
      final req = await _httpClient.getUrl(Uri.parse(streamUrl));
      req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
      final res = await req.close();
      if (res.statusCode == 200 || res.statusCode == 206) {
        final sink = tmpFile.openWrite();
        await res.pipe(sink);
        if (await tmpFile.exists() && await tmpFile.length() > 50000) {
          if (await targetFile.exists()) {
            try {
              await targetFile.delete();
            } catch (_) {}
          }
          await tmpFile.rename(targetFile.path);
          print('Downloaded and cached: ${targetFile.path} (${await targetFile.length()} bytes)');
          return true;
        } else {
          if (await tmpFile.exists()) await tmpFile.delete();
        }
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
  request.response.write('[]');
  await request.response.close();
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
  if (path.endsWith('.apk')) return ContentType('application', 'vnd.android.package-archive');
  return null;
}

Future<void> _handleCacheInfo(HttpRequest request) async {
  request.response.headers.contentType = ContentType.json;
  int totalBytes = 0;
  int trackCount = 0;

  if (await _cacheDir.exists()) {
    for (final entity in _cacheDir.listSync()) {
      if (entity is File && entity.path.contains('audio_') && entity.path.endsWith('.webm')) {
        totalBytes += entity.lengthSync();
        trackCount++;
      }
    }
  }

  request.response.write(jsonEncode({
    'totalBytes': totalBytes,
    'formattedSize': '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
    'trackCount': trackCount,
    'quotaBytes': _defaultCacheQuotaBytes,
    'quotaFormatted': '${(_defaultCacheQuotaBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB',
  }));
  await request.response.close();
}

Future<void> _handleClearCache(HttpRequest request) async {
  request.response.headers.contentType = ContentType.json;
  try {
    int deletedCount = 0;
    if (await _cacheDir.exists()) {
      for (final entity in _cacheDir.listSync()) {
        if (entity is File && (entity.path.contains('audio_') || entity.path.endsWith('.tmp'))) {
          try {
            entity.deleteSync();
            deletedCount++;
          } catch (_) {}
        }
      }
    }
    _resolveCache.clear();
    if (await _resolveIndexFile.exists()) {
      await _resolveIndexFile.writeAsString('{}');
    }
    request.response.write(jsonEncode({
      'success': true,
      'deletedFiles': deletedCount,
      'message': 'Cache cleared successfully',
    }));
  } catch (e) {
    request.response.statusCode = HttpStatus.internalServerError;
    request.response.write(jsonEncode({'error': e.toString()}));
  }
  await request.response.close();
}

Future<void> _handleDeletePlaylistCache(HttpRequest request) async {
  request.response.headers.contentType = ContentType.json;
  try {
    final body = await utf8.decodeStream(request);
    final data = jsonDecode(body) as Map<String, dynamic>;
    final playlistId = data['playlistId'] as String? ?? '';
    final tracks = (data['tracks'] as List<dynamic>?) ?? [];

    int deletedAudioCount = 0;
    int freedBytes = 0;

    for (final t in tracks) {
      if (t is Map) {
        final id = t['id'] as String? ?? '';
        final artist = t['artist'] as String? ?? '';
        final title = t['title'] as String? ?? '';
        final norm = '${_normalizeKey(artist)} - ${_normalizeKey(title)}';
        final entry = _resolveCache[id] ?? _resolveCache['track_$id'] ?? _resolveCache[norm];

        if (entry != null) {
          final vid = entry['videoId'] as String?;
          if (vid != null) {
            final audioFile = File('${_cacheDir.path}/audio_$vid.webm');
            if (audioFile.existsSync()) {
              final len = audioFile.lengthSync();
              try {
                audioFile.deleteSync();
                deletedAudioCount++;
                freedBytes += len;
              } catch (_) {}
            }
            // Remove resolve cache keys if not pinned in another playlist
            _resolveCache.remove(id);
            _resolveCache.remove('track_$id');
            _resolveCache.remove('vid_$vid');
            _resolveCache.remove(vid);
            _resolveCache.remove(norm);
          }
        }
      }
    }

    try {
      _resolveIndexFile.writeAsStringSync(jsonEncode(_resolveCache));
    } catch (_) {}

    print('Uninstalled offline playlist "$playlistId": deleted $deletedAudioCount audio files, freed ${(freedBytes / (1024 * 1024)).toStringAsFixed(1)} MB');

    request.response.write(jsonEncode({
      'success': true,
      'deletedAudioFiles': deletedAudioCount,
      'freedBytes': freedBytes,
      'freedFormatted': '${(freedBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
    }));
  } catch (e) {
    request.response.statusCode = HttpStatus.internalServerError;
    request.response.write(jsonEncode({'error': e.toString()}));
  }
  await request.response.close();
}
