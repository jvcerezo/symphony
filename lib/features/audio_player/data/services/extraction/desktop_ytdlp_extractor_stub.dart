import '../../../../../core/errors/exceptions.dart';
import 'audio_extractor.dart';

/// Web build: there is no process to run.
class DesktopYtDlpExtractor implements AudioExtractor {
  @override
  String get name => 'yt-dlp';

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<ExtractedAudio> extract(String videoId) =>
      throw const AudioStreamResolutionException('yt-dlp is not available on this platform');

  /// No self-update on web.
  Future<String?> update() async => null;

  /// Nothing to install on web.
  Future<bool> install() async => false;

  @override
  Future<ExtractedAudio> searchSong(String query) =>
      throw const AudioStreamResolutionException('yt-dlp is not available on this platform');

  @override
  void dispose() {}
}
