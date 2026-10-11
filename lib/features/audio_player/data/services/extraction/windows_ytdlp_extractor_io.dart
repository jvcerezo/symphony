import 'package:flutter/foundation.dart';
import '../../../../../core/errors/exceptions.dart';
import 'audio_extractor.dart';

/// Windows: runs a bundled `yt-dlp.exe` next to the app executable.
///
/// TODO(desktop): implement — locate the bundled binary, run
/// `yt-dlp -f "ba[ext=m4a]/ba" -j --no-playlist <url>`, parse url/ext/abr/
/// duration/http_headers, add a self-update path, and ship the binary from CI.
class WindowsYtDlpExtractor implements AudioExtractor {
  @override
  String get name => 'yt-dlp (windows)';

  @override
  Future<bool> isAvailable() async =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows && false;

  @override
  Future<ExtractedAudio> extract(String videoId) =>
      throw const AudioStreamResolutionException('yt-dlp extractor not implemented yet');

  @override
  void dispose() {}
}
