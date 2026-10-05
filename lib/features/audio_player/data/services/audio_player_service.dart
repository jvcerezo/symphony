import 'dart:async';
import 'dart:developer' as developer;
import 'package:just_audio/just_audio.dart';
import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/track.dart';
import 'audio_stream_resolver_service.dart';

class SymphonyAudioPlayerService {
  final AudioPlayer _player;
  final AudioStreamResolverService _streamResolver;

  Track? _currentTrack;

  SymphonyAudioPlayerService({
    AudioPlayer? player,
    AudioStreamResolverService? streamResolver,
  })  : _player = player ?? AudioPlayer(),
        _streamResolver = streamResolver ?? AudioStreamResolverService();

  Track? get currentTrack => _currentTrack;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;
  bool get isPlaying => _player.playing;

  /// Resolves the YouTube stream URL on-device and initializes playback.
  Future<void> playTrack(Track track) async {
    _currentTrack = track;

    try {
      // 1. Resolve client-side YouTube audio stream
      final streamInfo = await _streamResolver.resolveBestAudioStream(track);

      // 2. Prepare audio source with metadata headers
      final audioSource = AudioSource.uri(
        streamInfo.streamUri,
        tag: track.toMediaItem(actualDuration: streamInfo.duration),
      );

      // 3. Load stream into player engine
      await _player.setAudioSource(audioSource, preload: true);

      // 4. Begin playback
      await _player.play();

      developer.log(
        'Playback started: "${track.title}" by "${track.artist}" [${streamInfo.bitrateKbps} kbps, ${streamInfo.format}]',
        name: 'AudioPlayerService',
      );
    } on AudioStreamResolutionException {
      rethrow;
    } catch (e, st) {
      developer.log(
        'Playback initialization failed for track "${track.title}"',
        error: e,
        stackTrace: st,
        name: 'AudioPlayerService',
      );
      throw PlaybackInitializationException(
        'Failed to initialize audio source for track: "${track.title}"',
        e,
      );
    }
  }

  Future<void> pause() => _player.pause();
  Future<void> resume() => _player.play();
  Future<void> stop() => _player.stop();
  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  Future<void> dispose() async {
    _streamResolver.dispose();
    await _player.dispose();
  }
}
