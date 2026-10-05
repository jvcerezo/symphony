class ResolvedAudioStream {
  final Uri streamUri;
  final Duration duration;
  final int bitrateKbps;
  final String format;
  final String sourceVideoId;

  const ResolvedAudioStream({
    required this.streamUri,
    required this.duration,
    required this.bitrateKbps,
    required this.format,
    required this.sourceVideoId,
  });

  @override
  String toString() =>
      'ResolvedAudioStream(videoId: $sourceVideoId, bitrate: ${bitrateKbps}kbps, format: $format, duration: $duration)';
}
