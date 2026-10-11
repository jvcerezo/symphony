import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../../../../core/errors/exceptions.dart';
import 'audio_extractor.dart';

/// Pure-Dart fallback. YouTube currently rejects mid-file range requests on
/// these URLs (no JS challenge solver), so playback can stall partway through.
/// Use only when no yt-dlp based extractor is available.
class YoutubeExplodeExtractor implements AudioExtractor {
  final YoutubeExplode _yt;

  YoutubeExplodeExtractor(this._yt);

  @override
  String get name => 'youtube_explode';

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ExtractedAudio> extract(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audio = manifest.audioOnly;
      if (audio.isEmpty) {
        throw AudioStreamResolutionException('No audio streams for $videoId');
      }
      final aac = audio.where((s) =>
          s.container.name == 'mp4' || s.codec.mimeType.contains('mp4') || s.codec.mimeType.contains('aac'));
      final best = aac.isNotEmpty ? aac.withHighestBitrate() : audio.withHighestBitrate();
      return ExtractedAudio(
        url: best.url,
        container: best.container.name == 'mp4' ? 'm4a' : best.container.name,
        bitrateKbps: best.bitrate.kiloBitsPerSecond.round(),
      );
    } on AudioStreamResolutionException {
      rethrow;
    } catch (e) {
      throw AudioStreamResolutionException('youtube_explode failed for $videoId', e);
    }
  }

  @override
  Future<ExtractedAudio> searchSong(String query) =>
      Future.error(UnsupportedError('youtube_explode cannot search YouTube Music'));

  // The YoutubeExplode client is owned by the resolver.
  @override
  void dispose() {}
}
