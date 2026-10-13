import 'dart:async';
import 'dart:developer' as developer;
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/services/network_status.dart';
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
  final NetworkStatus _network;

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

  /// True while a song whose stream broke is being picked up again.
  bool _recovering = false;

  /// The song already picked up once after its stream broke; a second
  /// break moves on instead of retrying forever.
  Track? _recoveredTrack;

  SymphonyAudioHandler({
    AudioPlayer? player,
    AudioStreamResolverService? streamResolver,
    ArtworkResolverService? artworkResolver,
    NotificationPermissionService? notificationPermission,
    PlaybackCache? playbackCache,
    PlayQueue? queue,
    NetworkStatus? network,
  })  : _player = player ?? AudioPlayer(),
        _queue = queue ?? PlayQueue(),
        _playbackCache = playbackCache ?? PlaybackCache(),
        _streamResolver = streamResolver ?? AudioStreamResolverService(),
        _artworkResolver = artworkResolver ?? ArtworkResolverService(),
        _notificationPermission = notificationPermission ?? NotificationPermissionService(),
        _network = network ?? NetworkStatus() {
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
        // Prepare stream links for the few after that, so skipping ahead
        // also starts at once. Background, one at a time, yields to taps.
        final later = _queue.upcoming(ahead + 4).skip(ahead).toList();
        unawaited(() async {
          // Offline every lookup would fail, and a failed one forgets the
          // song's remembered match.
          if (!await _network.isOnline()) return;
          for (final t in upcoming) {
            unawaited(_warmTrack(t));
          }
          _streamResolver.prefetch(later, replace: true);
        }());
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
    _playbackEventSub = _player.playbackEventStream.listen(
      (_) => _updatePlaybackState(),
      onError: _onPlayerError,
    );
  }

  /// The player gave up on the current source, e.g. the connection dropped
  /// mid-song. Failures while a song loads are handled by that load.
  void _onPlayerError(Object error, [StackTrace? stackTrace]) {
    developer.log('Player error: $error', name: 'AudioHandler');
    if (_loading || _recovering || _queue.isEmpty) return;
    unawaited(_recoverPlayback());
  }

  void _listenToCompletion() {
    _playerStateSub = _player.playerStateStream.listen((state) {
      _updatePlaybackState();
      if (state.processingState == ProcessingState.completed && !_isAutoSkipping && !_loading && !_recovering) {
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
    }, onError: (Object _) {}); // Reported through playbackEventStream.
  }

  void _startCompletionWatchdog() {
    _completionWatchdogTimer?.cancel();
    _lastObservedPosition = Duration.zero;
    _lastPositionAdvanceTime = DateTime.now();

    _completionWatchdogTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_isAutoSkipping || _loading || _recovering || _queue.isEmpty || !_player.playing) return;

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

      // 3. Stuck buffering mid-song (the connection dropped): carry on from
      //    the copy on this device, or move on when offline.
      if (_player.processingState == ProcessingState.buffering &&
          DateTime.now().difference(_lastPositionAdvanceTime) > _stallLimit) {
        unawaited(_recoverPlayback(fromStall: true));
      }
    });
  }

  static const _stallLimit = Duration(seconds: 8);

  Future<void> _handleTrackCompleted([String reason = '']) async {
    if (_isAutoSkipping || _loading || _queue.isEmpty) return;
    _isAutoSkipping = true;
    _completionWatchdogTimer?.cancel();
    developer.log('Track completed ($reason). Moving on...', name: 'AudioHandler');
    try {
      final next = _queue.nextIndex(auto: true);
      if (next == null) {
        await _stopAtEnd();
      } else if (next == currentIndex) {
        await _player.seek(Duration.zero);
        unawaited(_player.play().catchError((Object e) {
          developer.log('play() failed: $e', name: 'AudioHandler');
        }));
        _startCompletionWatchdog();
        _updatePlaybackState();
      } else {
        // Not awaited: the next song can take a while to load, and the
        // queue must keep going after it (_loading guards it meanwhile).
        unawaited(_playOnFrom(next));
      }
    } catch (e) {
      developer.log('Auto-skip error: $e', name: 'AudioHandler');
    } finally {
      await Future.delayed(const Duration(milliseconds: 600));
      _isAutoSkipping = false;
    }
  }

  /// End of the queue with repeat off: stop on the last song, rewound.
  Future<void> _stopAtEnd() async {
    await _player.pause();
    await _player.seek(Duration.zero);
    _updatePlaybackState();
  }

  /// Keeps the queue playing from [index] without the user: a song that
  /// can't play (offline and not on this device, or no match found) is
  /// passed over instead of stopping everything.
  Future<void> _playOnFrom(int index) async {
    final wrap = _queue.repeatMode == QueueRepeatMode.all;
    var token = _playRequestId;
    int? candidate = index;
    for (var tries = 0; candidate != null && tries < _queue.length; tries++) {
      final target = await _playableFrom(candidate, wrap: wrap);
      // The user chose something else meanwhile.
      if (token != _playRequestId) return;
      if (target == null) {
        developer.log('Nothing left in the queue can play offline', name: 'AudioHandler');
        return _stopAtEnd();
      }
      try {
        await _playAt(target);
        return;
      } catch (e) {
        if (token + 1 != _playRequestId) return;
        token = _playRequestId;
        developer.log('Passing over "${_queue.current?.title}": $e', name: 'AudioHandler');
        candidate = _indexAfter(target, wrap: wrap);
      }
    }
    if (token == _playRequestId) await _stopAtEnd();
  }

  int? _indexAfter(int index, {required bool wrap}) {
    if (index + 1 < _queue.length) return index + 1;
    return wrap && _queue.length > 1 ? 0 : null;
  }

  /// [start], or offline the first song from there on (backwards with a
  /// negative [step]) that is on this device. Null when none is.
  Future<int?> _playableFrom(int start, {required bool wrap, int step = 1}) async {
    if (!_usesPlaybackCache || await _network.isOnline()) return start;
    final tracks = _queue.tracks;
    final n = tracks.length;
    var i = start;
    for (var seen = 0; seen < n; seen++) {
      if (await _onDeviceCopy(tracks[i]) != null) return i;
      final next = i + step;
      if (next < 0 || next >= n) {
        if (!wrap) return null;
        i = (next + n) % n;
      } else {
        i = next;
      }
    }
    return null;
  }

  /// [track]'s audio already on this device: its download, else a copy
  /// kept from playing it. Never touches the network.
  Future<ResolvedAudioStream?> _onDeviceCopy(Track track) async {
    if (!_usesPlaybackCache) return null;
    return await _streamResolver.resolveLocal(track) ?? await _playbackCache.cachedStreamFor(track);
  }

  /// Picks the current song up again after its stream broke: from the copy
  /// on this device at the same spot, else from a fresh link when online,
  /// else (offline) with the next song that can play. Only once per song;
  /// a second break moves on. [fromStall]: the player is stuck buffering
  /// rather than failed, so with a connection and no copy it is left to
  /// keep trying.
  Future<void> _recoverPlayback({bool fromStall = false}) async {
    final track = currentTrack;
    if (track == null || _recovering || _loading) return;
    _recovering = true;
    final requestId = _playRequestId;
    final position = _player.position;
    try {
      if (identical(_recoveredTrack, track)) {
        if (fromStall && await _network.isOnline()) return;
        developer.log('"${track.title}" broke again; moving on', name: 'AudioHandler');
        _moveOn();
        return;
      }

      final copy = await _onDeviceCopy(track);
      if (requestId != _playRequestId) return;
      if (copy != null) {
        _recoveredTrack = track;
        developer.log('Stream for "${track.title}" broke; continuing from the copy on this device at $position',
            name: 'AudioHandler');
        await _player
            .setAudioSource(AudioSource.uri(copy.streamUri, tag: mediaItem.value), initialPosition: position)
            .timeout(const Duration(seconds: 10));
        if (requestId != _playRequestId) return;
        unawaited(_player.play().catchError((Object e) {
          developer.log('play() failed: $e', name: 'AudioHandler');
        }));
        _startCompletionWatchdog();
        _updatePlaybackState();
        return;
      }

      if (await _network.isOnline()) {
        if (fromStall) return;
        _recoveredTrack = track;
        // The link may have expired: fetch a new one and resume there.
        _streamResolver.forgetTrack(track);
        _recovering = false;
        await _loadAndPlayTrack(track, startAt: position);
        return;
      }

      developer.log('Offline and "${track.title}" isn\'t on this device; moving on', name: 'AudioHandler');
      _recoveredTrack = track;
      _moveOn();
    } catch (e) {
      developer.log('Could not pick "${track.title}" up again: $e', name: 'AudioHandler');
      if (identical(currentTrack, track) && !_loading) _moveOn();
    } finally {
      _recovering = false;
    }
  }

  /// Leaves a song that can't go on for the next one that can play.
  void _moveOn() {
    final next = _indexAfter(currentIndex, wrap: _queue.repeatMode == QueueRepeatMode.all);
    unawaited(next == null ? _stopAtEnd() : _playOnFrom(next));
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
    // Offline, start at the first song from there that's on this device.
    await _playAt(await _playableFrom(_queue.index, wrap: true) ?? _queue.index);
  }

  /// Plays a single [Track], updating the current queue.
  Future<void> playTrack(Track track) async {
    _queue.load([track]);
    await _playAt(0);
  }

  /// Makes [index] (in play order) current and starts it.
  Future<void> _playAt(int index) async {
    if (!_queue.jumpTo(index)) return;
    _recoveredTrack = null;
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

  /// Plays [track] from [startAt] (the start unless a broken stream is
  /// being picked up again).
  Future<void> _loadAndPlayTrack(Track track, {Duration startAt = Duration.zero}) async {
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
        updatePosition: startAt,
        bufferedPosition: Duration.zero,
        queueIndex: currentIndex >= 0 ? currentIndex : null,
      ),
    );

    try {
      if (requestId != _playRequestId) return; // Superceded by another user tap

      // A downloaded track, or one played recently, is already on disk:
      // start it without a lookup (and without needing a connection).
      final download = _usesPlaybackCache ? await _streamResolver.resolveLocal(track) : null;
      var cached = download == null && _usesPlaybackCache ? await _playbackCache.cachedStreamFor(track) : null;
      // A copy saved from a match that has since been replaced, or one not
      // yet checked, could be the wrong song: drop it and match again.
      // Offline it is still better than nothing.
      if (cached != null &&
          !await _streamResolver.isSettledMatch(track, cached.sourceVideoId) &&
          await _network.isOnline()) {
        await _playbackCache.forget(track);
        cached = null;
      }
      final onDevice = download ?? cached;
      if (onDevice == null && _usesPlaybackCache && !await _network.isOnline()) {
        throw AudioStreamResolutionException('"${track.title}" isn\'t downloaded and there\'s no internet connection');
      }
      final streamInfo = onDevice ?? await _streamResolver.resolveBestAudioStream(track);
      if (requestId != _playRequestId) return;

      // Resolve artwork if track doesn't have one yet, ensuring rich lock-screen and bottom bar.
      // A song on the device doesn't wait for it (it may be offline).
      Uri? resolvedArt = track.artworkUri;
      if (resolvedArt == null && onDevice == null) {
        try {
          resolvedArt = await _artworkResolver.resolveArtwork(track);
        } catch (_) {}
      } else if (resolvedArt == null) {
        unawaited(_addArtworkLater(track, requestId, streamInfo.duration));
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
          initialPosition: startAt,
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
            await _player.setAudioSource(AudioSource.uri(file, tag: item), preload: true, initialPosition: startAt).timeout(const Duration(seconds: 10));
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
              initialPosition: startAt,
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
              initialPosition: startAt,
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

  /// Fills in [track]'s artwork once found, if it is still the one playing.
  Future<void> _addArtworkLater(Track track, int requestId, Duration duration) async {
    try {
      final art = await _artworkResolver.resolveArtwork(track);
      if (art == null || requestId != _playRequestId) return;
      mediaItem.add(track.copyWith(artworkUri: art).toMediaItem(actualDuration: duration));
    } catch (_) {}
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
    // Offline, go to the next song that's on this device.
    await _playAt(await _playableFrom(next, wrap: true) ?? next);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;
    final prev = _queue.previousIndex();
    if (_player.position.inSeconds > 3 || prev == null || prev == currentIndex) {
      await seek(Duration.zero);
    } else {
      final wrap = _queue.repeatMode == QueueRepeatMode.all;
      await _playAt(await _playableFrom(prev, wrap: wrap, step: -1) ?? prev);
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
