import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide AudioStreamInfo;
import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/resolved_audio_stream.dart';
import '../../domain/entities/track.dart';
import 'piped_stream_resolver.dart';

class AudioStreamResolverService {
  final YoutubeExplode _yt;
  final PipedStreamResolver _pipedResolver;

  AudioStreamResolverService({
    YoutubeExplode? ytClient,
    PipedStreamResolver? pipedResolver,
  })  : _yt = ytClient ?? YoutubeExplode(),
        _pipedResolver = pipedResolver ?? PipedStreamResolver();

  /// Resolves the optimal audio-only stream URI for a given [Track].
  ///
  /// On Web (`kIsWeb`), delegates to CORS-compliant public streaming APIs.
  /// On Native (Android, iOS, Desktop), queries YouTube on-device via `youtube_explode_dart`,
  /// falling back to Piped if YouTube rate-limits or throws cipher extraction errors.
  Future<ResolvedAudioStream> resolveBestAudioStream(Track track) async {
    // 1. Browser environments cannot make arbitrary cross-origin requests to YouTube
    if (kIsWeb) {
      developer.log('Web environment detected: routing through CORS-compliant resolver', name: 'AudioStreamResolver');
      return _pipedResolver.resolve(track);
    }

    // 2. Native resolution via youtube_explode_dart
    final query = '${track.artist} - ${track.title} official audio';
    developer.log('Resolving audio stream on native client: "$query"', name: 'AudioStreamResolver');

    try {
      final searchResults = await _yt.search.search(query);
      if (searchResults.isEmpty) {
        throw AudioStreamResolutionException(
          'No YouTube candidates discovered for query: "$query"',
        );
      }

      // Filter out live streams and evaluate the top 5 candidates
      final candidates = searchResults
          .where((video) => !video.isLive)
          .take(5)
          .toList();

      if (candidates.isEmpty) {
        throw AudioStreamResolutionException(
          'All candidates were live streams or unplayable for query: "$query"',
        );
      }

      for (final candidate in candidates) {
        // Guard against duration discrepancies (>60s delta)
        if (track.expectedDuration != null && candidate.duration != null) {
          final delta = (candidate.duration! - track.expectedDuration!).inSeconds.abs();
          if (delta > 60) {
            developer.log(
              'Skipping candidate "${candidate.title}" due to duration discrepancy (delta: ${delta}s)',
              name: 'AudioStreamResolver',
            );
            continue;
          }
        }

        try {
          final manifest = await _yt.videos.streamsClient.getManifest(candidate.id);
          final audioStreams = manifest.audioOnly;

          if (audioStreams.isEmpty) {
            developer.log(
              'Candidate "${candidate.id.value}" has no audio-only streams. Falling back.',
              name: 'AudioStreamResolver',
            );
            continue;
          }

          final bestAudio = audioStreams.withHighestBitrate();

          developer.log(
            'Resolved stream: ${candidate.id.value} | Bitrate: ${bestAudio.bitrate} | Container: ${bestAudio.container.name}',
            name: 'AudioStreamResolver',
          );

          return ResolvedAudioStream(
            streamUri: bestAudio.url,
            duration: candidate.duration ?? track.expectedDuration ?? Duration.zero,
            bitrateKbps: bestAudio.bitrate.kiloBitsPerSecond.round(),
            format: bestAudio.container.name,
            sourceVideoId: candidate.id.value,
          );
        } catch (e, st) {
          developer.log(
            'Failed extracting manifest for candidate: ${candidate.id.value}. Falling back.',
            error: e,
            stackTrace: st,
            name: 'AudioStreamResolver',
          );
          continue;
        }
      }

      // 3. If native candidates failed due to cipher/restriction, attempt secondary fallback
      developer.log(
        'Native extraction exhausted for "$query". Attempting secondary fallback resolver...',
        name: 'AudioStreamResolver',
      );
      return await _pipedResolver.resolve(track);
    } catch (e) {
      if (e is AudioStreamResolutionException) {
        // Attempt secondary fallback before giving up
        try {
          return await _pipedResolver.resolve(track);
        } catch (_) {
          rethrow;
        }
      }
      throw AudioStreamResolutionException(
        'Unexpected stream resolution failure for track: ${track.title}',
        e,
      );
    }
  }

  void dispose() {
    _yt.close();
    _pipedResolver.dispose();
  }
}
