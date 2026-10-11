class ResolvedAudioStream {
  final Uri streamUri;
  final Duration duration;
  final int bitrateKbps;
  final String format;
  final String sourceVideoId;

  /// Headers the player must send when fetching [streamUri], if any.
  final Map<String, String>? headers;

  const ResolvedAudioStream({
    required this.streamUri,
    required this.duration,
    required this.bitrateKbps,
    required this.format,
    required this.sourceVideoId,
    this.headers,
  });

  @override
  String toString() =>
      'ResolvedAudioStream(videoId: $sourceVideoId, bitrate: ${bitrateKbps}kbps, format: $format, duration: $duration)';
}
