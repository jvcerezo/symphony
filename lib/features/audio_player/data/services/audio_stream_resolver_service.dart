import 'dart:developer' as developer;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' hide AudioStreamInfo;
import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/resolved_audio_stream.dart';
import '../../domain/entities/track.dart';

class AudioStreamResolverService {
  final YoutubeExplode _yt;

  AudioStreamResolverService({YoutubeExplode? ytClient})
      : _yt = ytClient ?? YoutubeExplode();

  /// Resolves the optimal audio-only stream URI for a given [Track].
  ///
  /// Searches YouTube using an optimized query heuristic, evaluates candidate
  /// results against duration bounds, and extracts high-bitrate audio streams
  /// with automated fallback across candidates in case of manifest errors or restrictions.
  Future<ResolvedAudioStream> resolveBestAudioStream(Track track) async {
    final query = '${track.artist} - ${track.title} official audio';
    developer.log('Resolving audio stream for query: "$query"', name: 'AudioStreamResolver');

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
        // Guard against duration discrepancies if an expected duration is available (>60s delta)
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

          // Prioritize highest bitrate audio stream
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
            'Failed extracting manifest for candidate: ${candidate.id.value}. Falling back to next candidate.',
            error: e,
            stackTrace: st,
            name: 'AudioStreamResolver',
          );
          continue;
        }
      }

      throw AudioStreamResolutionException(
        'Exhausted all search candidates without finding a playable audio stream for "$query".',
      );
    } catch (e) {
      if (e is AudioStreamResolutionException) rethrow;
      throw AudioStreamResolutionException(
        'Unexpected stream resolution failure for track: ${track.title}',
        e,
      );
    }
  }

  void dispose() {
    _yt.close();
  }
}
