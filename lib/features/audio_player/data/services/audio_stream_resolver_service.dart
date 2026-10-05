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

  AudioStreamResolverService({
    YoutubeExplode? ytClient,
    http.Client? httpClient,
  })  : _yt = ytClient ?? YoutubeExplode(),
        _httpClient = httpClient ?? http.Client();

  /// Resolves a playable full-length audio stream for a [Track].
  ///
  /// On Web (`kIsWeb`), queries the backend `/api/resolve` service running
  /// in Symphony's pure Dart HTTP server to extract full master YouTube audio
  /// without browser CORS limitations and with full Range/seeking support.
  /// On Native, extracts on-device YouTube streams via `youtube_explode_dart`,
  /// falling back to the global CDN if YouTube blocks or restricts the device.
  Future<ResolvedAudioStream> resolveBestAudioStream(Track track) async {
    // 1. Direct YouTube video ID resolution if available (e.g. YouTube imported playlists)
    if (track.id.startsWith('yt_')) {
      final videoId = track.id.replaceFirst('yt_', '');
      if (kIsWeb) {
        final serverResolved = await _resolveViaWebServer(track, videoId: videoId);
        if (serverResolved != null) return serverResolved;
      } else {
        try {
          final manifest = await _yt.videos.streamsClient.getManifest(videoId);
          final audioStreams = manifest.audioOnly;
          if (audioStreams.isNotEmpty) {
            final bestAudio = audioStreams.withHighestBitrate();
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
          developer.log('Direct YouTube video extraction failed: $e', name: 'AudioStreamResolver');
        }
      }
    }

    // 2. Full YouTube audio stream extraction (Plays complete 3-4 min master from 0:00:00 intro to end)
    if (kIsWeb) {
      final serverResolved = await _resolveViaWebServer(track);
      if (serverResolved != null) {
        return serverResolved;
      }
    } else {
      final cleanTitle = _cleanSongTitle(track.title);
      final cleanArtist = _cleanSongArtist(track.artist);
      final query = '$cleanArtist - $cleanTitle official audio';
      developer.log('Resolving full YouTube audio via client: "$query"', name: 'AudioStreamResolver');

      try {
        final searchResults = await _yt.search.search(query);
        if (searchResults.isNotEmpty) {
          final candidates = searchResults
              .where((video) => !video.isLive)
              .take(5)
              .toList();

          for (final candidate in candidates) {
            if (track.expectedDuration != null && candidate.duration != null) {
              final delta = (candidate.duration! - track.expectedDuration!).inSeconds.abs();
              if (delta > 60) continue;
            }

            try {
              final manifest = await _yt.videos.streamsClient.getManifest(candidate.id);
              final audioStreams = manifest.audioOnly;

              if (audioStreams.isNotEmpty) {
                final bestAudio = audioStreams.withHighestBitrate();
                developer.log(
                  'Resolved full YouTube stream: ${candidate.id.value} [${bestAudio.bitrate.kiloBitsPerSecond.round()} kbps, duration: ${candidate.duration}]',
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
  Future<ResolvedAudioStream?> _resolveViaWebServer(Track track, {String? videoId}) async {
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
    }
    if (!candidateOrigins.contains('http://localhost:8080')) {
      candidateOrigins.add('http://localhost:8080');
    }
    if (!candidateOrigins.contains('http://127.0.0.1:8080')) {
      candidateOrigins.add('http://127.0.0.1:8080');
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
        final response = await _httpClient.get(uri).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final streamUrl = data['streamUrl'] as String?;
          final durationMs = data['durationMs'] as int?;

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
              format: (data['format'] as String?) ?? 'webm',
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

  void dispose() {
    _yt.close();
    _httpClient.close();
  }
}
