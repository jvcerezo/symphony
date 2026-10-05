import 'dart:async';
import 'dart:developer' as developer;
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/track.dart';
import 'audio_stream_resolver_service.dart';

class SymphonyAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;
  final AudioStreamResolverService _streamResolver;

  final List<Track> _playlistQueue = [];
  final BehaviorSubject<int> _currentIndexSubject = BehaviorSubject<int>.seeded(-1);
  final BehaviorSubject<List<Track>> _queueSubject = BehaviorSubject<List<Track>>.seeded([]);

  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;

  SymphonyAudioHandler({
    AudioPlayer? player,
    AudioStreamResolverService? streamResolver,
  })  : _player = player ?? AudioPlayer(),
        _streamResolver = streamResolver ?? AudioStreamResolverService() {
    _initAudioSession();
    _broadcastPlaybackState();
    _listenToCompletion();
  }

  ValueStream<int> get currentIndexStream => _currentIndexSubject.stream;
  ValueStream<List<Track>> get playlistQueueStream => _queueSubject.stream;

  int get currentIndex => _currentIndexSubject.value;
  List<Track> get currentQueue => _playlistQueue;

  Track? get currentTrack => (currentIndex >= 0 && currentIndex < _playlistQueue.length)
      ? _playlistQueue[currentIndex]
      : null;

  Future<void> _initAudioSession() async {
    if (kIsWeb) return;

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

      _noisySub = session.becomingNoisyEventStream.listen((_) {
        developer.log('Audio output unplugged. Pausing playback.', name: 'AudioHandler');
        pause();
      });
    } catch (e) {
      developer.log('AudioSession init error: $e', name: 'AudioHandler');
    }
  }

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
          queueIndex: currentIndex >= 0 ? currentIndex : null,
        ),
      );
    });
  }

  void _listenToCompletion() {
    _playerStateSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        developer.log('Track completed. Auto-skipping to next...', name: 'AudioHandler');
        skipToNext();
      }
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

  /// Sets an entire playlist queue and starts playback at [startIndex].
  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    _playlistQueue
      ..clear()
      ..addAll(tracks);
    _queueSubject.add(List.unmodifiable(_playlistQueue));

    final targetIndex = startIndex.clamp(0, _playlistQueue.length - 1);
    _currentIndexSubject.add(targetIndex);
    await _loadAndPlayTrack(_playlistQueue[targetIndex]);
  }

  /// Plays a single [Track], updating the current queue.
  Future<void> playTrack(Track track) async {
    _playlistQueue
      ..clear()
      ..add(track);
    _queueSubject.add(List.unmodifiable(_playlistQueue));
    _currentIndexSubject.add(0);
    await _loadAndPlayTrack(track);
  }

  Future<void> _loadAndPlayTrack(Track track) async {
    try {
      final streamInfo = await _streamResolver.resolveBestAudioStream(track);
      final item = track.toMediaItem(actualDuration: streamInfo.duration);
      mediaItem.add(item);

      final audioSource = AudioSource.uri(streamInfo.streamUri, tag: item);
      await _player.setAudioSource(audioSource, preload: true);
      await _player.play();

      developer.log(
        'Started: "${track.title}" by "${track.artist}" [${streamInfo.bitrateKbps}kbps]',
        name: 'AudioHandler',
      );
    } catch (e, st) {
      developer.log('Playback start failure', error: e, stackTrace: st, name: 'AudioHandler');
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
    if (currentIndex + 1 < _playlistQueue.length) {
      final nextIdx = currentIndex + 1;
      _currentIndexSubject.add(nextIdx);
      await _loadAndPlayTrack(_playlistQueue[nextIdx]);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position.inSeconds > 3) {
      await seek(Duration.zero);
    } else if (currentIndex > 0) {
      final prevIdx = currentIndex - 1;
      _currentIndexSubject.add(prevIdx);
      await _loadAndPlayTrack(_playlistQueue[prevIdx]);
    }
  }

  Future<void> setVolume(double volume) => _player.setVolume(volume);

  Future<void> release() async {
    await _playbackEventSub?.cancel();
    await _playerStateSub?.cancel();
    await _interruptionSub?.cancel();
    await _noisySub?.cancel();
    await _currentIndexSubject.close();
    await _queueSubject.close();
    _streamResolver.dispose();
    await _player.dispose();
  }
}
