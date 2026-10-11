import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../../../../core/errors/exceptions.dart';
import 'audio_extractor.dart';

/// Android: yt-dlp running on the phone via the `youtubedl-android` library,
/// reached over a method channel implemented in `YtDlpBridge.kt`.
///
/// Channel contract (`com.symphony.symphony/ytdlp`):
/// - `isAvailable` → `bool`
/// - `extract` `{videoId: String}` →
///   `{url: String, ext: String, abr: num?, durationMs: int?, headers: Map<String, String>?}`;
///   errors are `PlatformException`s.
/// - `update` → `String?` (new yt-dlp version, or null if already current)
///
/// The Kotlin side (`YtDlpBridge.kt`) initialises the library off the main
/// thread at app start (`isAvailable` waits for that), coalesces concurrent
/// `extract` calls for the same id, kills a yt-dlp run after 90 s, and
/// updates yt-dlp from the stable channel at most once a day by itself.
class AndroidYtDlpExtractor implements AudioExtractor {
  @visibleForTesting
  static const channel = MethodChannel('com.symphony.symphony/ytdlp');

  bool? _available;

  @override
  String get name => 'yt-dlp (android)';

  @override
  Future<bool> isAvailable() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    if (_available != null) return _available!;
    try {
      _available = await channel.invokeMethod<bool>('isAvailable') ?? false;
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
      final raw = await channel.invokeMapMethod<String, dynamic>('extract', {'videoId': videoId});
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
    } on MissingPluginException catch (e) {
      throw AudioStreamResolutionException('yt-dlp (android) is not available', e.message);
    }
  }

  /// Updates yt-dlp on the device now (the native side already does this
  /// daily). Returns the new version, or null when already current or when
  /// the update could not run.
  Future<String?> update() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await channel.invokeMethod<String>('update');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  void dispose() {}
}
