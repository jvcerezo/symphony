import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/symphony_audio_handler.dart';

/// Global provider for the Symphony AudioHandler instance
final audioHandlerProvider = Provider<SymphonyAudioHandler>((ref) {
  throw UnimplementedError('audioHandlerProvider must be overridden with the initialized instance');
});

/// Stream provider for reactive playback state changes (playing, buffering, position)
final playbackStateStreamProvider = StreamProvider<PlaybackState>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.playbackState;
});

/// Stream provider for current active media item (title, artist, artwork)
final currentMediaItemStreamProvider = StreamProvider<MediaItem?>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.mediaItem;
});
