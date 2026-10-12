import 'dart:async';
import 'dart:developer' as developer;
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/services/notification_permission_service.dart';
import '../../domain/entities/resolved_audio_stream.dart';
import '../../domain/entities/track.dart';
import '../../domain/play_queue.dart';
import '../../../metadata_search/data/services/artwork_resolver_service.dart';
import 'audio_stream_resolver_service.dart';
import 'offline/playback_cache.dart';
import '../../../../core/config/server_config.dart';

class SymphonyAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;
  final AudioStreamResolverService _streamResolver;
  final PlaybackCache _playbackCache;
  final ArtworkResolverService _artworkResolver;
  final NotificationPermissionService _notificationPermission;

  final PlayQueue _queue;
  final BehaviorSubject<int> _currentIndexSubject = BehaviorSubject<int>.seeded(-1);
  final BehaviorSubject<List<Track>> _queueSubject = BehaviorSubject<List<Track>>.seeded([]);

  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;

  int _playRequestId = 0;

  /// True while a track is being resolved/loaded. Raw player events during
  /// that time (idle, paused) must not flip the UI back to "paused".
  bool _loading = false;
  bool _isAutoSkipping = false;
  Timer? _completionWatchdogTimer;
  Duration _lastObservedPosition = Duration.zero;
  DateTime _lastPositionAdvanceTime = DateTime.now();

  SymphonyAudioHandler({
    AudioPlayer? player,
    AudioStreamResolverService? streamResolver,
    ArtworkResolverService? artworkResolver,
    NotificationPermissionService? notificationPermission,
    PlaybackCache? playbackCache,
    PlayQueue? queue,
  })  : _player = player ?? AudioPlayer(),
        _queue = queue ?? PlayQueue(),
        _playbackCache = playbackCache ?? PlaybackCache(),
        _streamResolver = streamResolver ?? AudioStreamResolverService(),
        _artworkResolver = artworkResolver ?? ArtworkResolverService(),
        _notificationPermission = notificationPermission ?? NotificationPermissionService() {
    _initAudioSession();
    _broadcastPlaybackState();
    _listenToCompletion();
  }

  ValueStream<int> get currentIndexStream => _currentIndexSubject.stream;
  ValueStream<List<Track>> get playlistQueueStream => _queueSubject.stream;

  int get currentIndex => _currentIndexSubject.value;
  List<Track> get currentQueue => _queue.tracks;

  Track? get currentTrack => _queue.current;

  bool get isShuffled => _queue.isShuffled;
  QueueRepeatMode get repeatMode => _queue.repeatMode;

  AudioStreamResolverService get streamResolver => _streamResolver;

  /// Proactively preloads tracks into memory cache.
  void preloadTracks(List<Track> tracks, {int count = 2}) =>
      _streamResolver.preloadTracks(tracks, count: count);

  /// Preloads a single track.
  Future<void> preloadTrack(Track track) => _streamResolver.preloadTrack(track);

  /// Native plays from local files: one track ahead is enough and each
  /// lookup launches yt-dlp, so stay light there.
  bool get _usesPlaybackCache => !kIsWeb && _playbackCache.isSupported;

  /// Resolves and caches [track] in the background so the next skip is instant.
  Future<void> _warmTrack(Track track) async {
    try {
      final stream = await _streamResolver.preloadTrack(track);
      if (stream != null && PlaybackCache.shouldCache(stream)) {
        await _playbackCache.fileFor(track, stream);
      }
    } catch (e) {
      developer.log('Warm-up failed for "${track.title}": $e', name: 'AudioHandler');
    }
  }

  /// Helper to pre-resolve the tracks that play next (shuffle/repeat aware).
  void _preloadUpcomingTracks() {
    if (_queue.isEmpty) return;
    final ahead = _usesPlaybackCache ? 1 : 2;
    final upcoming = _queue.upcoming(ahead);
    if (upcoming.isNotEmpty) {
      if (_usesPlaybackCache) {
        for (final t in upcoming) {
          unawaited(_warmTrack(t));
        }
        // Prepare stream links for the few after that, so skipping ahead
        // also starts at once. Background, one at a time, yields to taps.
        final later = _queue.upcoming(ahead + 4).skip(ahead).toList();
        _streamResolver.prefetch(later, replace: true);
      } else {
        _streamResolver.preloadTracks(upcoming, count: 2);
      }
      for (final t in upcoming) {
        if (t.artworkUri == null) {
          _artworkResolver.resolveArtwork(t).catchError((_) => null);
        }
      }
    }
  }

  Future<void> _initAudioSession() async {
    if (kIsWeb || (!kIsWeb && (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux))) return;

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

  void _updatePlaybackState() {
    final isPlaying = _loading || _player.playing;
    final processingState =
        _loading ? AudioProcessingState.buffering : _transformProcessingState(_player.processingState);

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
        shuffleMode: _queue.isShuffled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
        repeatMode: switch (_queue.repeatMode) {
          QueueRepeatMode.off => AudioServiceRepeatMode.none,
          QueueRepeatMode.all => AudioServiceRepeatMode.all,
          QueueRepeatMode.one => AudioServiceRepeatMode.one,
        },
      ),
    );
  }

  void _broadcastPlaybackState() {
    _playbackEventSub = _player.playbackEventStream.listen((_) {
      _updatePlaybackState();
    });
  }

  void _listenToCompletion() {
    _playerStateSub = _player.playerStateStream.listen((state) {
      _updatePlaybackState();
      if (state.processingState == ProcessingState.completed && !_isAutoSkipping) {
        final dur = _player.duration ?? mediaItem.value?.duration ?? currentTrack?.expectedDuration;
        if (dur != null && dur > const Duration(seconds: 15)) {
          final pos = _player.position;
          if (pos >= dur - const Duration(milliseconds: 2500)) {
            _handleTrackCompleted('ProcessingState.completed at end: $pos / $dur');
          } else {
            developer.log('Ignored premature completed event: pos=$pos, dur=$dur', name: 'AudioHandler');
          }
        }
      }
    });
  }

  void _startCompletionWatchdog() {
    _completionWatchdogTimer?.cancel();
    _lastObservedPosition = Duration.zero;
    _lastPositionAdvanceTime = DateTime.now();

    _completionWatchdogTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_isAutoSkipping || _queue.isEmpty || !_player.playing) return;

      final dur = _player.duration ?? mediaItem.value?.duration ?? currentTrack?.expectedDuration;
      if (dur == null || dur <= const Duration(seconds: 15)) return;

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

      // 2. Near end stall watchdog: within 2.0 seconds of end and position hasn't advanced for > 1500ms
      if (pos >= dur - const Duration(milliseconds: 2000)) {
        final timeSinceAdvance = DateTime.now().difference(_lastPositionAdvanceTime);
        final isBufferingOrIdle = _player.processingState == ProcessingState.buffering ||
            _player.processingState == ProcessingState.idle ||
            _player.processingState == ProcessingState.completed;

        if (timeSinceAdvance > const Duration(milliseconds: 1500) || isBufferingOrIdle) {
          _handleTrackCompleted('stalled at end: $pos / $dur, state: ${_player.processingState}');
          return;
        }
      }
    });
  }

  Future<void> _handleTrackCompleted([String reason = '']) async {
    if (_isAutoSkipping || _queue.isEmpty) return;
    _isAutoSkipping = true;
    _completionWatchdogTimer?.cancel();
    developer.log('Track completed ($reason). Moving on...', name: 'AudioHandler');
    try {
      final next = _queue.nextIndex(auto: true);
      if (next == null) {
        // End of the queue with repeat off: stop on the last song, rewound.
        await _player.pause();
        await _player.seek(Duration.zero);
        _updatePlaybackState();
      } else if (next == currentIndex) {
        await _player.seek(Duration.zero);
        unawaited(_player.play().catchError((Object e) {
          developer.log('play() failed: $e', name: 'AudioHandler');
        }));
        _startCompletionWatchdog();
        _updatePlaybackState();
      } else {
        await _playAt(next);
      }
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
  /// With shuffle on, that song plays first and the rest are shuffled.
  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    _queue.load(tracks, startIndex: startIndex);
    await _playAt(_queue.index);
  }

  /// Plays a single [Track], updating the current queue.
  Future<void> playTrack(Track track) async {
    _queue.load([track]);
    await _playAt(0);
  }

  /// Makes [index] (in play order) current and starts it.
  Future<void> _playAt(int index) async {
    if (!_queue.jumpTo(index)) return;
    _emitQueue();
    _preloadUpcomingTracks();
    await _loadAndPlayTrack(_queue.current!);
  }

  void _emitQueue() {
    _queueSubject.add(_queue.tracks);
    _currentIndexSubject.add(_queue.index);
    queue.add(_queue.tracks.map((t) => t.toMediaItem()).toList());
  }

  /// Queue edits from the UI. Indexes are positions in play order, as
  /// listed by [playlistQueueStream].
  void playNext(Track track) {
    final wasEmpty = _queue.isEmpty;
    _queue.playNext(track);
    _afterQueueEdit();
    if (wasEmpty) unawaited(_playAt(0));
  }

  void enqueue(Track track) {
    final wasEmpty = _queue.isEmpty;
    _queue.add(track);
    _afterQueueEdit();
    if (wasEmpty) unawaited(_playAt(0));
  }

  void removeFromQueue(int index) {
    if (_queue.removeAt(index)) _afterQueueEdit();
  }

  void moveInQueue(int from, int to) {
    if (_queue.move(from, to)) _afterQueueEdit();
  }

  void _afterQueueEdit() {
    _emitQueue();
    _preloadUpcomingTracks();
    _updatePlaybackState();
  }

  @override
  Future<void> skipToQueueItem(int index) => _playAt(index);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _queue.setShuffle(shuffleMode != AudioServiceShuffleMode.none);
    _afterQueueEdit();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _queue.repeatMode = switch (repeatMode) {
      AudioServiceRepeatMode.none => QueueRepeatMode.off,
      AudioServiceRepeatMode.one => QueueRepeatMode.one,
      AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => QueueRepeatMode.all,
    };
    _preloadUpcomingTracks();
    _updatePlaybackState();
  }

  Future<void> _loadAndPlayTrack(Track track) async {
    final requestId = ++_playRequestId;
    _loading = true;

    // Android 13+: ask for POST_NOTIFICATIONS on first playback so the media
    // notification is visible. Memoized and non-blocking; no-op elsewhere.
    unawaited(_notificationPermission.ensureRequested());

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
      if (requestId != _playRequestId) return; // Superceded by another user tap

      // A track played recently is already on disk: start it without a lookup.
      final cached = _usesPlaybackCache ? await _playbackCache.cachedStreamFor(track) : null;
      final streamInfo = cached ?? await _streamResolver.resolveBestAudioStream(track);
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

      Map<String, String>? getHeadersForUri(Uri uri) {
        final host = uri.host.toLowerCase();
        // Never send YouTube headers to our server or Apple/iTunes CDN
        if (ServerConfig.isSymphonyHost(host) ||
            host.contains('apple.com') ||
            host.contains('itunes')) {
          return null;
        }
        if (host.contains('googlevideo.com')) {
          return const {
            'Accept': '*/*',
            'Accept-Encoding': 'identity;q=1, *;q=0',
          };
        }
        return null;
      }

      final activeStream = streamInfo;

      // Native: play a local copy. Keeps network streaming (and just_audio's
      // header proxy, which runs on the UI isolate) out of the player.
      // The local copy being saved in the background for the current stream.
      Future<Uri>? backgroundCopy;

      // Native, first play: start streaming at once (no wait for a download)
      // and save a local copy in the background for replays and instant seeks.
      // No request headers, so just_audio talks to the CDN directly instead of
      // through its proxy. Recently played tracks already resolved to a file.
      Future<AudioSource> sourceFor(ResolvedAudioStream stream) async {
        if (_usesPlaybackCache && PlaybackCache.shouldCache(stream)) {
          backgroundCopy = _playbackCache.fileFor(track, stream);
          backgroundCopy!.ignore();
          return AudioSource.uri(stream.streamUri, tag: item);
        }
        return AudioSource.uri(
          stream.streamUri,
          headers: stream.headers ?? getHeadersForUri(stream.streamUri),
          tag: item,
        );
      }

      try {
        final audioSource = await sourceFor(activeStream);
        if (requestId != _playRequestId) return;
        await _player.setAudioSource(
          audioSource,
          preload: true,
        ).timeout(const Duration(seconds: 10));
      } catch (loadErr) {
        developer.log('Primary stream load failed with $loadErr, attempting fallback...', name: 'AudioHandler');
        if (requestId != _playRequestId) return;

        bool recovered = false;

        // Streaming failed (e.g. the CDN wanted headers): play the local copy,
        // which downloads with the extractor's headers in ranged chunks.
        final copy = backgroundCopy;
        if (copy != null) {
          try {
            final file = await copy.timeout(const Duration(seconds: 45));
            if (requestId != _playRequestId) return;
            await _player.setAudioSource(AudioSource.uri(file, tag: item), preload: true).timeout(const Duration(seconds: 10));
            recovered = true;
            developer.log('Recovered "${track.title}" from its local copy', name: 'AudioHandler');
          } catch (e) {
            developer.log('Local copy unavailable for "${track.title}": $e', name: 'AudioHandler');
          }
        }

        if (!recovered) await _playbackCache.forget(track);
        if (!recovered) try {
          final serverResolved = await _streamResolver.resolveViaWebServer(track);
          if (serverResolved != null) {
            final serverSource = AudioSource.uri(serverResolved.streamUri, tag: item);
            await _player.setAudioSource(
              serverSource,
              preload: true,
            ).timeout(const Duration(seconds: 10));
            recovered = true;
            developer.log('Recovered playback via Symphony server stream proxy for: "${track.title}"', name: 'AudioHandler');
          }
        } catch (_) {}

        if (!recovered) {
          developer.log('Activating resilient fallback CDN...', name: 'AudioHandler');
          final fallback = await _streamResolver.resolveFallbackCdn(track);
          if (fallback != null) {
            final fallbackSource = await sourceFor(fallback);
            await _player.setAudioSource(
              fallbackSource,
              preload: true,
            ).timeout(const Duration(seconds: 10));
            recovered = true;
          } else {
            rethrow;
          }
        }
      }
      if (requestId != _playRequestId) return;

      _loading = false;
      // Not awaited: just_audio's play() completes only when playback stops,
      // which would hold up the watchdog, the next-track preload and auto-skip.
      unawaited(_player.play().catchError((Object e) {
        developer.log('play() failed: $e', name: 'AudioHandler');
      }));
      _updatePlaybackState();
      _startCompletionWatchdog();
      _preloadUpcomingTracks();

      developer.log(
        'Started: "${track.title}" by "${track.artist}" [${streamInfo.bitrateKbps}kbps, duration: ${streamInfo.duration.inSeconds}s]',
        name: 'AudioHandler',
      );
    } catch (e, st) {
      if (requestId != _playRequestId) return; // Ignore errors from superseded requests
      _loading = false;
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
    // Not awaited: the future only completes when playback stops.
    unawaited(_player.play().catchError((Object e) {
      developer.log('play() failed: $e', name: 'AudioHandler');
    }));
    _updatePlaybackState();
  }

  @override
  Future<void> pause() async {
    if (_loading) {
      // Pausing while a track loads cancels that load.
      _playRequestId++;
      _loading = false;
    }
    await _player.pause();
    _updatePlaybackState();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _updatePlaybackState();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _updatePlaybackState();
  }

  @override
  Future<void> skipToNext() async {
    final next = _queue.nextIndex(auto: false);
    if (next == null) return;
    await _playAt(next);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;
    final prev = _queue.previousIndex();
    if (_player.position.inSeconds > 3 || prev == null || prev == currentIndex) {
      await seek(Duration.zero);
    } else {
      await _playAt(prev);
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
    _playbackCache.dispose();
    await _player.dispose();
  }
}
