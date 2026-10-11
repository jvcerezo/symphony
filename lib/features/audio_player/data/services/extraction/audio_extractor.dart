import '../../../../../core/errors/exceptions.dart';

/// A playable audio stream for one YouTube video, produced on the user's
/// own device.
class ExtractedAudio {
  final Uri url;

  /// Container reported by the extractor (`m4a`, `mp4`, `webm`, …).
  final String container;
  final int? bitrateKbps;
  final Duration? duration;

  /// Headers the player must send when fetching [url], if any.
  final Map<String, String>? headers;

  const ExtractedAudio({
    required this.url,
    required this.container,
    this.bitrateKbps,
    this.duration,
    this.headers,
  });
}

/// Turns a YouTube video id into a full-length, seekable audio URL without
/// any Symphony server. Implementations run entirely on the device.
///
/// Implementations must throw [AudioStreamResolutionException] when they
/// cannot produce a stream, and should prefer AAC (`m4a`) because Windows
/// playback only works reliably with it.
abstract class AudioExtractor {
  /// Short label for logs, e.g. `yt-dlp`.
  String get name;

  /// Whether this extractor can run on this device right now (binary present,
  /// native library loaded, …). Cheap to call repeatedly.
  Future<bool> isAvailable();

  Future<ExtractedAudio> extract(String videoId);

  void dispose() {}
}

/// Tries each extractor in order and returns the first success.
class ChainedAudioExtractor implements AudioExtractor {
  final List<AudioExtractor> _extractors;

  ChainedAudioExtractor(this._extractors);

  @override
  String get name => _extractors.map((e) => e.name).join(' → ');

  @override
  Future<bool> isAvailable() async {
    for (final e in _extractors) {
      if (await e.isAvailable()) return true;
    }
    return false;
  }

  @override
  Future<ExtractedAudio> extract(String videoId) async {
    final errors = <String>[];
    for (final e in _extractors) {
      try {
        if (!await e.isAvailable()) continue;
        return await e.extract(videoId);
      } catch (err) {
        errors.add('${e.name}: $err');
      }
    }
    throw AudioStreamResolutionException(
      'No extractor could produce audio for $videoId',
      errors.isEmpty ? 'no extractor available' : errors.join('; '),
    );
  }

  @override
  void dispose() {
    for (final e in _extractors) {
      e.dispose();
    }
  }
}
