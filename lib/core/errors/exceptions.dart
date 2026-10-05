class AudioStreamResolutionException implements Exception {
  final String message;
  final dynamic cause;

  const AudioStreamResolutionException(this.message, [this.cause]);

  @override
  String toString() =>
      'AudioStreamResolutionException: $message ${cause != null ? '($cause)' : ''}';
}

class PlaybackInitializationException implements Exception {
  final String message;
  final dynamic cause;

  const PlaybackInitializationException(this.message, [this.cause]);

  @override
  String toString() =>
      'PlaybackInitializationException: $message ${cause != null ? '($cause)' : ''}';
}
