import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../../../../core/errors/exceptions.dart';
import 'audio_extractor.dart';

/// Android: yt-dlp running on the phone via the `youtubedl-android` library,
/// reached over a method channel implemented in `MainActivity.kt`.
///
/// Channel contract (`com.symphony.symphony/ytdlp`):
/// - `isAvailable` → `bool`
/// - `extract` `{videoId: String}` → `{url: String, ext: String,
///   abr: num?, durationMs: int?, headers: Map<String, String>?}`;
///   errors are `PlatformException`s.
/// - `update` → `String?` (new yt-dlp version, or null if already current)
class AndroidYtDlpExtractor implements AudioExtractor {
  static const _channel = MethodChannel('com.symphony.symphony/ytdlp');

  bool? _available;

  @override
  String get name => 'yt-dlp (android)';

  @override
  Future<bool> isAvailable() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    if (_available != null) return _available!;
    try {
      _available = await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      _available = false;
    }
    return _available!;
  }

  @override
  Future<ExtractedAudio> extract(String videoId) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('extract', {'videoId': videoId});
      final url = raw?['url'] as String?;
      if (url == null || url.isEmpty) {
        throw AudioStreamResolutionException('yt-dlp returned no URL for $videoId');
      }
      final durationMs = (raw?['durationMs'] as num?)?.toInt();
      final headers = (raw?['headers'] as Map?)?.map((k, v) => MapEntry('$k', '$v'));
      return ExtractedAudio(
        url: Uri.parse(url),
        container: (raw?['ext'] as String?) ?? 'm4a',
        bitrateKbps: (raw?['abr'] as num?)?.round(),
        duration: durationMs != null && durationMs > 0 ? Duration(milliseconds: durationMs) : null,
        headers: headers,
      );
    } on PlatformException catch (e) {
      throw AudioStreamResolutionException('yt-dlp (android) failed for $videoId', e.message);
    }
  }

  @override
  void dispose() {}
}
