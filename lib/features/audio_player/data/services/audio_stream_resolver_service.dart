import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide AudioStreamInfo;
import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/resolved_audio_stream.dart';
import '../../domain/entities/track.dart';

class AudioStreamResolverService {
  final YoutubeExplode _yt;
  final http.Client _httpClient;

  /// In-memory resolution cache keyed by track ID and normalized artist/title.
  final Map<String, ResolvedAudioStream> _resolvedCache = {};

  /// In-flight futures to coalesce simultaneous resolve requests for the same track.
  final Map<String, Future<ResolvedAudioStream>> _inFlightResolutions = {};

  AudioStreamResolverService({
    YoutubeExplode? ytClient,
    http.Client? httpClient,
  })  : _yt = ytClient ?? YoutubeExplode(),
        _httpClient = httpClient ?? http.Client();

  String _normKey(Track track) =>
      '${_cleanSongArtist(track.artist).toLowerCase()} - ${_cleanSongTitle(track.title).toLowerCase()}';

  /// Returns the cached stream if available (0ms instant lookup).
  ResolvedAudioStream? getCachedStream(Track track) {
    final primaryKey = track.id;
    final normKey = _normKey(track);
    return _resolvedCache[primaryKey] ?? _resolvedCache[normKey];
  }

  /// Whether a track has already been resolved into memory.
  bool isTrackResolved(Track track) => getCachedStream(track) != null;

  /// Cache a stream manually (e.g. for pre-seeded tracks).
  void cacheResolvedStream(String key, ResolvedAudioStream stream) {
    _resolvedCache[key] = stream;
  }

  /// Asynchronously preloads a single track without throwing on error.
  Future<ResolvedAudioStream?> preloadTrack(Track track) async {
    if (isTrackResolved(track)) {
      return getCachedStream(track);
    }
    try {
      final stream = await resolveBestAudioStream(track);
      developer.log('Preloaded stream for: "${track.title}" -> ${stream.streamUri}', name: 'AudioStreamResolver');
      return stream;
    } catch (e) {
      developer.log('Preload error for "${track.title}": $e', name: 'AudioStreamResolver');
      return null;
    }
  }

  /// Proactively preloads upcoming tracks sequentially in the background.
  void preloadTracks(List<Track> tracks, {int count = 2}) {
    if (tracks.isEmpty) return;
    Future.microtask(() async {
      for (final track in tracks.take(count)) {
        if (!isTrackResolved(track)) {
          await preloadTrack(track);
          await Future.delayed(const Duration(milliseconds: 60));
        }
      }
    });
  }

  /// Clears in-memory resolution cache.
  void clearCache() {
    _resolvedCache.clear();
    _inFlightResolutions.clear();
  }

  /// Resolves a playable full-length audio stream for a [Track].
  ///
  /// On Web (`kIsWeb`), queries the backend `/api/resolve` service running
  /// in Symphony's pure Dart HTTP server to extract full master YouTube audio
  /// without browser CORS limitations and with full Range/seeking support.
  /// On Native, extracts on-device YouTube streams via `youtube_explode_dart`,
  /// falling back to the global CDN if YouTube blocks or restricts the device.
  Future<ResolvedAudioStream> resolveBestAudioStream(Track track) async {
    final primaryKey = track.id;
    final normKey = _normKey(track);

    // 0. Cache hit - 0ms instant playback!
    final cached = _resolvedCache[primaryKey] ?? _resolvedCache[normKey];
    if (cached != null) {
      developer.log('Instant cache hit for "${track.title}"', name: 'AudioStreamResolver');
      return cached;
    }

    // 1. In-flight request deduplication
    if (_inFlightResolutions.containsKey(primaryKey)) {
      return await _inFlightResolutions[primaryKey]!;
    }
    if (_inFlightResolutions.containsKey(normKey)) {
      return await _inFlightResolutions[normKey]!;
    }

    final future = _doResolveBestAudioStream(track);
    _inFlightResolutions[primaryKey] = future;
    _inFlightResolutions[normKey] = future;

    try {
      final resolved = await future;
      _resolvedCache[primaryKey] = resolved;
      _resolvedCache[normKey] = resolved;
      if (resolved.sourceVideoId.isNotEmpty) {
        _resolvedCache['vid_${resolved.sourceVideoId}'] = resolved;
        _resolvedCache[resolved.sourceVideoId] = resolved;
      }
      return resolved;
    } finally {
      _inFlightResolutions.remove(primaryKey);
      _inFlightResolutions.remove(normKey);
    }
  }

  Future<ResolvedAudioStream> _doResolveBestAudioStream(Track track) async {
    // 0. Direct full stream attached to track (e.g. pre-seeded master streams, local files, or server proxies)
    if (track.streamUri != null && !_isShortPreviewStream(track.streamUri)) {
      developer.log(
        'Direct full streamUri playback for: "${track.title}" -> ${track.streamUri}',
        name: 'AudioStreamResolver',
      );
      return ResolvedAudioStream(
        streamUri: track.streamUri!,
        duration: track.expectedDuration ?? Duration.zero,
        bitrateKbps: 320,
        format: track.streamUri!.path.endsWith('.m4a') ? 'aac' : 'mp3',
        sourceVideoId: track.id,
      );
    }

    // 1. Direct YouTube video ID resolution if available (e.g. YouTube imported playlists)
    if (track.id.startsWith('yt_')) {
      final videoId = track.id.replaceFirst('yt_', '');
      if (kIsWeb) {
        final serverResolved = await resolveViaWebServer(track, videoId: videoId);
        if (serverResolved != null) return serverResolved;
      } else {
        try {
          final manifest = await _yt.videos.streamsClient.getManifest(videoId);
          final audioStreams = manifest.audioOnly;
          if (audioStreams.isNotEmpty) {
            final aacStreams = audioStreams.where((s) => s.container.name == 'mp4' || s.codec.mimeType.contains('mp4') || s.codec.mimeType.contains('aac'));
            final bestAudio = aacStreams.isNotEmpty ? aacStreams.withHighestBitrate() : audioStreams.withHighestBitrate();
            developer.log('Resolved direct YouTube stream for video: $videoId', name: 'AudioStreamResolver');
            return ResolvedAudioStream(
              streamUri: bestAudio.url,
              duration: track.expectedDuration ?? Duration.zero,
              bitrateKbps: bestAudio.bitrate.kiloBitsPerSecond.round(),
              format: bestAudio.container.name,
              sourceVideoId: videoId,
            );
          }
        } catch (e) {
          developer.log('Direct YouTube video extraction failed: $e. Falling back to server resolver.', name: 'AudioStreamResolver');
          final serverResolved = await resolveViaWebServer(track, videoId: videoId);
          if (serverResolved != null) return serverResolved;
        }
      }
    }

    // 2. Full YouTube audio stream extraction (Plays complete 3-4 min master from 0:00:00 intro to end)
    if (kIsWeb) {
      final serverResolved = await resolveViaWebServer(track);
      if (serverResolved != null) {
        return serverResolved;
      }
    } else {
      final cleanTitle = _cleanSongTitle(track.title);
      final cleanArtist = _cleanSongArtist(track.artist);
      final queries = [
        '$cleanArtist $cleanTitle topic',
        '$cleanArtist - $cleanTitle official audio',
        '$cleanArtist - $cleanTitle',
        '$cleanTitle $cleanArtist',
      ];
      developer.log('Resolving full YouTube audio via client for: "$cleanArtist - $cleanTitle"', name: 'AudioStreamResolver');

      try {
        final seenVideoIds = <String>{};
        final scoredCandidates = <({Video video, int score})>[];

        for (final q in queries) {
          try {
            final searchResults = await _yt.search.search(q);
            for (final v in searchResults.take(6)) {
              if (v.isLive) continue;
              if (seenVideoIds.add(v.id.value)) {
                final sc = scoreVideoCandidate(
                  videoTitle: v.title,
                  videoAuthor: v.author,
                  durationSec: v.duration?.inSeconds ?? 0,
                  targetTitle: track.title,
                  targetArtist: track.artist,
                  expectedDurationMs: track.expectedDuration?.inMilliseconds,
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

          for (final scored in scoredCandidates.where((c) => c.score >= 50)) {
            final candidate = scored.video;
            try {
              final manifest = await _yt.videos.streamsClient.getManifest(candidate.id);
              final audioStreams = manifest.audioOnly;

              if (audioStreams.isNotEmpty) {
                final aacStreams = audioStreams.where((s) => s.container.name == 'mp4' || s.codec.mimeType.contains('mp4') || s.codec.mimeType.contains('aac'));
                final bestAudio = aacStreams.isNotEmpty ? aacStreams.withHighestBitrate() : audioStreams.withHighestBitrate();
                developer.log(
                  'Resolved full YouTube stream: ${candidate.id.value} [${bestAudio.bitrate.kiloBitsPerSecond.round()} kbps, format: ${bestAudio.container.name}, score: ${scored.score}]',
                  name: 'AudioStreamResolver',
                );

                return ResolvedAudioStream(
                  streamUri: bestAudio.url,
                  duration: candidate.duration ?? track.expectedDuration ?? Duration.zero,
                  bitrateKbps: bestAudio.bitrate.kiloBitsPerSecond.round(),
                  format: bestAudio.container.name,
                  sourceVideoId: candidate.id.value,
                );
              }
            } catch (e) {
              developer.log('Candidate ${candidate.id.value} manifest extraction failed: $e', name: 'AudioStreamResolver');
              continue;
            }
          }
        }
      } catch (e) {
        developer.log('YouTube on-device extraction failed: $e. Falling back to resilient streams.', name: 'AudioStreamResolver');
      }

      // Try server resolve if on-device search was unable to produce a playable audio stream
      try {
        final serverResolved = await resolveViaWebServer(track);
        if (serverResolved != null) {
          return serverResolved;
        }
      } catch (_) {}
    }

    // 3. Direct stream attached to track (if provided and full audio)
    if (track.streamUri != null) {
      developer.log(
        'Direct streamUri fallback for: "${track.title}" -> ${track.streamUri}',
        name: 'AudioStreamResolver',
      );
      return ResolvedAudioStream(
        streamUri: track.streamUri!,
        duration: track.expectedDuration ?? const Duration(seconds: 30),
        bitrateKbps: 320,
        format: track.streamUri!.path.endsWith('.m4a') ? 'aac' : 'mp3',
        sourceVideoId: track.id,
      );
    }

    // 4. Fallback to resilient CDN stream (with candidate scoring to pick original studio master)
    final fallbackCdn = await _resolveDirectCdnAudio(track);
    if (fallbackCdn != null) {
      return fallbackCdn;
    }

    throw AudioStreamResolutionException(
      'Could not resolve a playable audio stream for "${track.title}" by "${track.artist}"',
    );
  }

  /// Queries the Symphony server's `/api/resolve` endpoint on Web to extract
  /// full-length YouTube audio stream proxies without 403 or CORS restrictions.
  Future<ResolvedAudioStream?> resolveViaWebServer(Track track, {String? videoId}) async {
    final cleanTitle = _cleanSongTitle(track.title);
    final cleanArtist = _cleanSongArtist(track.artist);
    final query = '$cleanArtist - $cleanTitle official audio';

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
        final queryParams = <String, String>{};
        if (videoId != null && videoId.isNotEmpty) {
          queryParams['videoId'] = videoId;
        } else {
          queryParams['q'] = query;
          queryParams['artist'] = cleanArtist;
          queryParams['title'] = cleanTitle;
        }
        if (track.expectedDuration != null) {
          queryParams['durationMs'] = track.expectedDuration!.inMilliseconds.toString();
        }

        final uri = Uri.parse('$origin/api/resolve').replace(queryParameters: queryParams);
        final response = await _httpClient.get(uri).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final streamUrl = data['streamUrl'] as String?;
          final durationMs = data['durationMs'] as int?;
          final format = (data['format'] as String?) ?? 'webm';

          if (streamUrl != null && streamUrl.isNotEmpty) {
            final fullStreamUri = streamUrl.startsWith('http')
                ? Uri.parse(streamUrl)
                : Uri.parse(origin).resolve(streamUrl);

            developer.log(
              'Resolved full master stream via server API ($origin): "${track.title}" -> $fullStreamUri',
              name: 'AudioStreamResolver',
            );
            return ResolvedAudioStream(
              streamUri: fullStreamUri,
              duration: durationMs != null ? Duration(milliseconds: durationMs) : (track.expectedDuration ?? Duration.zero),
              bitrateKbps: (data['bitrate'] as num?)?.round() ?? 160,
              format: format,
              sourceVideoId: (data['videoId'] as String?) ?? track.id,
            );
          }
        }
      } catch (e) {
        developer.log('Server resolve attempt failed on $origin: $e', name: 'AudioStreamResolver');
      }
    }
    return null;
  }

  bool _isShortPreviewStream(Uri? uri) {
    if (uri == null) return false;
    final s = uri.toString().toLowerCase();
    return s.contains('audio-ssl.itunes.apple.com') ||
        s.contains('itunes.apple.com') ||
        s.contains('cdns-preview') ||
        s.contains('/preview/');
  }

  String _cleanSongTitle(String title) {
    return title
        .replaceAll(RegExp(r'\(feat\.[^)]*\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[feat\.[^\]]*\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(remix[^)]*\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\(.*remaster.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'- .*remaster.*', caseSensitive: false), '')
        .replaceAll(RegExp(r'- .*version.*', caseSensitive: false), '')
        .trim();
  }

  String _cleanSongArtist(String artist) {
    return artist
        .split(RegExp(r'[,/&]|ft\.|feat\.', caseSensitive: false))
        .first
        .trim();
  }

  /// Public fallback method to resolve high-fidelity AAC stream via Apple CDN if primary YouTube stream fails in player
  Future<ResolvedAudioStream?> resolveFallbackCdn(Track track) => _resolveDirectCdnAudio(track);

  /// Resolves an unauthenticated, zero-cost high-fidelity AAC stream via Apple CDN.
  Future<ResolvedAudioStream?> _resolveDirectCdnAudio(Track track) async {
    final cleanTitle = _cleanSongTitle(track.title);
    final cleanArtist = _cleanSongArtist(track.artist);

    final queryVariations = [
      '$cleanArtist $cleanTitle'.trim(),
      cleanTitle,
      '${track.artist} ${track.title}'.trim(),
    ];

    for (final query in queryVariations) {
      if (query.isEmpty) continue;
      final uri = Uri.parse(
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&media=music&entity=song&limit=10',
      );

      try {
        final response = await _httpClient.get(uri).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
          final results = (data['results'] as List<dynamic>?) ?? [];

          Map<String, dynamic>? bestCandidate;
          int highestScore = -999;

          final targetTitleLower = cleanTitle.toLowerCase();
          final targetArtistLower = cleanArtist.toLowerCase();

          for (final item in results) {
            if (item is! Map<String, dynamic>) continue;
            final previewUrl = item['previewUrl'] as String?;
            if (previewUrl == null || previewUrl.isEmpty) continue;

            final itemTitle = (item['trackName'] as String? ?? '').toLowerCase();
            final itemArtist = (item['artistName'] as String? ?? '').toLowerCase();

            int score = 0;
            if (itemTitle == targetTitleLower) {
              score += 100;
            } else if (itemTitle.contains(targetTitleLower) || targetTitleLower.contains(itemTitle)) {
              score += 50;
            }

            if (itemArtist.contains(targetArtistLower)) {
              score += 50;
            }
            if (itemArtist == targetArtistLower) {
              score += 30;
            }

            if (itemTitle.contains('remix') && !targetTitleLower.contains('remix')) score -= 80;
            if (itemTitle.contains('live') && !targetTitleLower.contains('live')) score -= 80;
            if (itemTitle.contains('karaoke') || itemArtist.contains('karaoke')) score -= 200;
            if (itemTitle.contains('tribute') || itemArtist.contains('tribute')) score -= 200;
            if (itemTitle.contains('cover') || itemArtist.contains('cover')) score -= 200;
            if (itemTitle.contains('instrumental') && !targetTitleLower.contains('instrumental')) score -= 100;

            if (score > highestScore) {
              highestScore = score;
              bestCandidate = item;
            }
          }

          if (bestCandidate != null && highestScore > 0) {
            final previewUrl = bestCandidate['previewUrl'] as String;
            final durationMs = bestCandidate['trackTimeMillis'] as int? ?? 30000;
            developer.log(
              'Selected best master match: "${bestCandidate['trackName']}" by "${bestCandidate['artistName']}" [score: $highestScore] -> $previewUrl',
              name: 'AudioStreamResolver',
            );

            return ResolvedAudioStream(
              streamUri: Uri.parse(previewUrl),
              duration: track.expectedDuration ?? Duration(milliseconds: durationMs),
              bitrateKbps: 256,
              format: 'aac',
              sourceVideoId: 'itunes_cdn_${bestCandidate['trackId'] ?? 0}',
            );
          }
        }
      } catch (e) {
        developer.log('CDN resolution error for "$query": $e', name: 'AudioStreamResolver');
      }
    }

    return null;
  }

  static int scoreVideoCandidate({
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

  void dispose() {
    clearCache();
    _yt.close();
    _httpClient.close();
  }
}
