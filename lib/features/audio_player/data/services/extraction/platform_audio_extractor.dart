import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'android_ytdlp_extractor.dart';
import 'audio_extractor.dart';
import 'desktop_ytdlp_extractor.dart';
import 'youtube_explode_extractor.dart';

/// The on-device extractor chain for this platform: yt-dlp where it is
/// available, then the pure-Dart fallback.
AudioExtractor createPlatformAudioExtractor(YoutubeExplode yt) => ChainedAudioExtractor([
      DesktopYtDlpExtractor(),
      AndroidYtDlpExtractor(),
      YoutubeExplodeExtractor(yt),
    ]);
