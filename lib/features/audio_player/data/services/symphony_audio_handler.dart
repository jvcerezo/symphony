import 'dart:async';
import 'dart:developer' as developer;
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/track.dart';
import '../../../metadata_search/data/services/artwork_resolver_service.dart';
import 'audio_stream_resolver_service.dart';

class SymphonyAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;
  final AudioStreamResolverService _streamResolver;
  final ArtworkResolverService _artworkResolver;

  final List<Track> _playlistQueue = [];
  final BehaviorSubject<int> _currentIndexSubject = BehaviorSubject<int>.seeded(-1);
  final BehaviorSubject<List<Track>> _queueSubject = BehaviorSubject<List<Track>>.seeded([]);

  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;

  int _playRequestId = 0;
  bool _isAutoSkipping = false;
  Timer? _completionWatchdogTimer;
  Duration _lastObservedPosition = Duration.zero;
  DateTime _lastPositionAdvanceTime = DateTime.now();

  SymphonyAudioHandler({
    AudioPlayer? player,
    AudioStreamResolverService? streamResolver,
    ArtworkResolverService? artworkResolver,
  })  : _player = player ?? AudioPlayer(),
        _streamResolver = streamResolver ?? AudioStreamResolverService(),
        _artworkResolver = artworkResolver ?? ArtworkResolverService() {
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
      if (state.processingState == ProcessingState.completed &&
          !_isAutoSkipping &&
          _player.position > const Duration(seconds: 3)) {
        _handleTrackCompleted('ProcessingState.completed event');
      }
    });
  }

  void _startCompletionWatchdog() {
    _completionWatchdogTimer?.cancel();
    _lastObservedPosition = Duration.zero;
    _lastPositionAdvanceTime = DateTime.now();

    _completionWatchdogTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (_isAutoSkipping || _playlistQueue.isEmpty || !_player.playing) return;

      final dur = _player.duration ?? mediaItem.value?.duration ?? currentTrack?.expectedDuration;
      if (dur == null || dur <= const Duration(seconds: 5)) return;

      final pos = _player.position;

      // Track advancement
      if (pos > _lastObservedPosition) {
        _lastObservedPosition = pos;
        _lastPositionAdvanceTime = DateTime.now();
      }

      // 1. Natural end boundary reached (within 500ms of track duration or past duration)
      if (pos >= dur - const Duration(milliseconds: 500)) {
        _handleTrackCompleted('end boundary reached: $pos / $dur');
        return;
      }

      // 2. Near end stall watchdog: within 2.5 seconds of end and position hasn't advanced for > 850ms,
      // or browser audio entered buffering/idle at EOF
      if (pos >= dur - const Duration(milliseconds: 2500)) {
        final timeSinceAdvance = DateTime.now().difference(_lastPositionAdvanceTime);
        final isBufferingOrIdle = _player.processingState == ProcessingState.buffering ||
            _player.processingState == ProcessingState.idle;

        if (timeSinceAdvance > const Duration(milliseconds: 850) || isBufferingOrIdle) {
          _handleTrackCompleted('stalled at end: $pos / $dur, state: ${_player.processingState}');
          return;
        }
      }
    });
  }

  Future<void> _handleTrackCompleted([String reason = '']) async {
    if (_isAutoSkipping || _playlistQueue.isEmpty) return;
    _isAutoSkipping = true;
    _completionWatchdogTimer?.cancel();
    developer.log('Track completed ($reason). Auto-skipping to next...', name: 'AudioHandler');
    try {
      await skipToNext();
    } catch (e) {
      developer.log('Auto-skip error: $e', name: 'AudioHandler');
    } finally {
      await Future.delayed(const Duration(milliseconds: 600));
      _isAutoSkipping = false;
    }
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
    final requestId = ++_playRequestId;

    // 1. Immediately cut off previous audio with zero latency
    try {
      _player.pause();
    } catch (_) {}

    // 2. Immediately update the UI media item & buffering state so the user sees the new track in < 1ms
    mediaItem.add(track.toMediaItem());
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.buffering,
        playing: true,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        queueIndex: currentIndex >= 0 ? currentIndex : null,
      ),
    );

    try {
      // 3. Stop existing playback to reset browser HTML5 audio element cleanly
      await _player.stop();
      await _player.seek(Duration.zero);
      if (requestId != _playRequestId) return; // Superceded by another user tap

      final streamInfo = await _streamResolver.resolveBestAudioStream(track);
      if (requestId != _playRequestId) return;

      // Resolve artwork if track doesn't have one yet, ensuring rich lock-screen and bottom bar
      Uri? resolvedArt = track.artworkUri;
      if (resolvedArt == null) {
        try {
          resolvedArt = await _artworkResolver.resolveArtwork(track);
        } catch (_) {}
      }
      if (requestId != _playRequestId) return;

      final enrichedTrack = resolvedArt != null ? track.copyWith(artworkUri: resolvedArt) : track;
      final item = enrichedTrack.toMediaItem(actualDuration: streamInfo.duration);
      mediaItem.add(item);

      final audioSource = AudioSource.uri(streamInfo.streamUri, tag: item);
      await _player.setAudioSource(
        audioSource,
        preload: true,
        initialPosition: Duration.zero,
      );
      if (requestId != _playRequestId) return;

      await _player.play();
      _startCompletionWatchdog();

      developer.log(
        'Started: "${track.title}" by "${track.artist}" [${streamInfo.bitrateKbps}kbps, duration: ${streamInfo.duration.inSeconds}s]',
        name: 'AudioHandler',
      );
    } catch (e, st) {
      if (requestId != _playRequestId) return; // Ignore errors from superseded requests
      developer.log('Playback start failure', error: e, stackTrace: st, name: 'AudioHandler');
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.idle,
          playing: false,
        ),
      );
      if (e is AudioStreamResolutionException) rethrow;
      throw PlaybackInitializationException('Failed to play "${track.title}"', e);
    }
  }

  @override
  Future<void> play() async {
    if (_player.processingState == ProcessingState.completed) {
      await seek(Duration.zero);
    }
    await _player.play();
  }

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
    if (_playlistQueue.isEmpty) return;
    final nextIdx = (currentIndex + 1) % _playlistQueue.length;
    _currentIndexSubject.add(nextIdx);
    await _loadAndPlayTrack(_playlistQueue[nextIdx]);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_playlistQueue.isEmpty) return;
    if (_player.position.inSeconds > 3) {
      await seek(Duration.zero);
    } else {
      final prevIdx = currentIndex > 0 ? currentIndex - 1 : _playlistQueue.length - 1;
      _currentIndexSubject.add(prevIdx);
      await _loadAndPlayTrack(_playlistQueue[prevIdx]);
    }
  }

  Future<void> setVolume(double volume) => _player.setVolume(volume);

  Future<void> release() async {
    _completionWatchdogTimer?.cancel();
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
