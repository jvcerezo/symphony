import 'dart:async';
import 'dart:developer' as developer;
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/track.dart';
import 'audio_stream_resolver_service.dart';

class SymphonyAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;
  final AudioStreamResolverService _streamResolver;

  final List<Track> _queue = [];
  int _currentIndex = -1;

  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;

  SymphonyAudioHandler({
    AudioPlayer? player,
    AudioStreamResolverService? streamResolver,
  })  : _player = player ?? AudioPlayer(),
        _streamResolver = streamResolver ?? AudioStreamResolverService() {
    _initAudioSession();
    _broadcastPlaybackState();
  }

  /// Configures platform-specific audio session (audio focus, interruptions, noisy headphones)
  Future<void> _initAudioSession() async {
    if (kIsWeb) return; // AudioSession is handled by the browser on Web

    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      _interruptionSub = session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.setVolume(0.5);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              pause();
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.setVolume(1.0);
              break;
            case AudioInterruptionType.pause:
              play();
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });

      // Automatically pause when headphones are unplugged
      _noisySub = session.becomingNoisyEventStream.listen((_) {
        developer.log('Headphones disconnected. Pausing playback.', name: 'AudioHandler');
        pause();
      });
    } catch (e) {
      developer.log('Could not initialize AudioSession: $e', name: 'AudioHandler');
    }
  }

  /// Maps just_audio events to audio_service PlaybackState for Android/iOS/Web system controls
  void _broadcastPlaybackState() {
    _playbackEventSub = _player.playbackEventStream.listen((PlaybackEvent event) {
      final isPlaying = _player.playing;
      final processingState = _transformProcessingState(_player.processingState);

      playbackState.add(
        PlaybackState(
          controls: [
            MediaControl.skipToPrevious,
            if (isPlaying) MediaControl.pause else MediaControl.play,
            MediaControl.stop,
            MediaControl.skipToNext,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          androidCompactActionIndices: const [0, 1, 3],
          processingState: processingState,
          playing: isPlaying,
          updatePosition: _player.position,
          bufferedPosition: _player.bufferedPosition,
          speed: _player.speed,
          queueIndex: _currentIndex >= 0 ? _currentIndex : null,
        ),
      );
    });
  }

  AudioProcessingState _transformProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  Track? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _queue.length) ? _queue[_currentIndex] : null;

  /// Loads and plays a given [Track].
  Future<void> playTrack(Track track) async {
    try {
      // 1. Resolve audio stream on-device
      final streamInfo = await _streamResolver.resolveBestAudioStream(track);

      // 2. Sync system notification metadata
      final item = track.toMediaItem(actualDuration: streamInfo.duration);
      mediaItem.add(item);

      // 3. Update queue
      _queue
        ..clear()
        ..add(track);
      _currentIndex = 0;

      // 4. Load audio stream into engine
      final audioSource = AudioSource.uri(streamInfo.streamUri, tag: item);
      await _player.setAudioSource(audioSource, preload: true);

      // 5. Play
      await _player.play();

      developer.log(
        'Started playback: "${track.title}" [${streamInfo.bitrateKbps}kbps, ${streamInfo.format}]',
        name: 'AudioHandler',
      );
    } catch (e, st) {
      developer.log('Error starting playback', error: e, stackTrace: st, name: 'AudioHandler');
      if (e is AudioStreamResolutionException) rethrow;
      throw PlaybackInitializationException('Failed to play "${track.title}"', e);
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_currentIndex + 1 < _queue.length) {
      _currentIndex++;
      await playTrack(_queue[_currentIndex]);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position.inSeconds > 3) {
      await seek(Duration.zero);
    } else if (_currentIndex > 0) {
      _currentIndex--;
      await playTrack(_queue[_currentIndex]);
    }
  }

  Future<void> setVolume(double volume) => _player.setVolume(volume);

  Future<void> release() async {
    await _playbackEventSub?.cancel();
    await _interruptionSub?.cancel();
    await _noisySub?.cancel();
    _streamResolver.dispose();
    await _player.dispose();
  }
}
