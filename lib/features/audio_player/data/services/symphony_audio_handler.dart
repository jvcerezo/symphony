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
import '../../domain/playback_remote.dart';
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
  final BehaviorSubject<String?> _resolvedVideoIdSubject = BehaviorSubject<String?>.seeded(null);

  /// Set while this device follows a Jam host; see [remote].
  PlaybackRemote? _remote;

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

  /// True while the queue moves on by itself. A song that fails to load then
  /// leaves the state playing for the next one: reporting it stopped would end
  /// the Android playback service, which a backgrounded app can't restart, so
  /// the music (and its notification) would be gone.
  bool _carryingOn = false;

  /// The last song tried failed to load: the player sits idle, shown as an error.
  bool _loadFailed = false;

  /// Playback was stopped ([stop]): the one time the state may be idle,
  /// which on Android ends the playback service and its notification.
  bool _stopped = false;

  /// The song already picked up once after its stream broke; a second
  /// break moves on instead of retrying forever.
  Track? _recoveredTrack;

  /// Another app took the audio for a moment (a video, a voice note, a
  /// call) while this one was playing; playback picks up when it hands
  /// the audio back. Cleared when the user plays or pauses meanwhile.
  bool _resumeWhenFocusReturns = false;

  /// The song loading when another app took the audio: it finishes
  /// loading but waits, paused, for the audio to come back.
  int? _loadHeldForFocus;

  /// Autoplay: when the queue runs out (repeat off, not in a Jam, online),
  /// asked for songs to carry on with after [last]. None: stop as before.
  Future<List<Track>> Function(Track last, List<Track> queue)? autoplay;

  SymphonyAudioHandler({
    AudioPlayer? player,
    AudioStreamResolverService? streamResolver,
    ArtworkResolverService? artworkResolver,
    NotificationPermissionService? notificationPermission,
    PlaybackCache? playbackCache,
    PlayQueue? queue,
    NetworkStatus? network,
  })  : // Interruptions are handled here; just_audio's own handling would
        // pause and resume the player a second time.
        _player = player ?? AudioPlayer(handleInterruptions: false),
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

  /// The YouTube video the current song plays from, once it has loaded
  /// (null while loading).
  ValueStream<String?> get resolvedVideoIdStream => _resolvedVideoIdSubject.stream;

  /// Where the current song is right now.
  Duration get position => _player.position;

  /// Whether audio is playing on this device right now.
  bool get isPlayingHere => _player.playing;

  /// While set (a Jam guest), the user's playback actions and queue edits
  /// go to [remote] instead of playing here, and a song that ends doesn't
  /// move the queue on; the guest drives playback with the `follow*`
  /// methods. Shuffle and repeat go off: the host's order is the play order.
  PlaybackRemote? get remote => _remote;
  set remote(PlaybackRemote? remote) {
    _remote = remote;
    if (remote == null) return;
    _queue.setShuffle(false);
    _queue.repeatMode = QueueRepeatMode.off;
    _afterQueueEdit();
  }

  NetworkStatus get network => _network;

  /// True while a song is loading or being picked up again; background
  /// downloads wait for it.
  bool get isLoadingTrack => _loading || _recovering;

  /// [track]'s playback copy on this device, if it is of the song's
  /// current match (an older one could be the wrong recording).
  Future<ResolvedAudioStream?> playbackCopyFor(Track track) async {
    if (!_usesPlaybackCache) return null;
    final copy = await _playbackCache.cachedStreamFor(track);
    if (copy == null || !await _streamResolver.isSettledMatch(track, copy.sourceVideoId)) return null;
    return copy;
  }

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
        // Prepare stream links for the two after that, so skipping ahead
        // also starts at once. Background, one at a time, yields to taps.
        final later = _queue.upcoming(ahead + 2).skip(ahead).toList();
        unawaited(() async {
          // Offline every lookup would fail, and a failed one forgets the
          // song's remembered match.
          if (!await _network.isOnline()) return;
          // On mobile data the next song isn't downloaded ahead, only its
          // link found: it would cost data the user may never play.
          if (await _network.isMetered()) {
            _streamResolver.prefetch(upcoming, replace: true);
            return;
          }
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

      _interruptionSub = session.interruptionEventStream.listen(handleInterruption);

      _noisySub = session.becomingNoisyEventStream.listen((_) {
        developer.log('Audio output unplugged. Pausing playback.', name: 'AudioHandler');
        _pauseHere();
      });
    } catch (e) {
      developer.log('AudioSession init error: $e', name: 'AudioHandler');
    }
  }

  /// Another app taking or handing back the audio (on Android, audio
  /// focus). A short loss pauses and resumes only if this was playing; a
  /// lasting one (another player started) just pauses. A song loading
  /// meanwhile still loads, so the one shown is the one that resumes.
  @visibleForTesting
  void handleInterruption(AudioInterruptionEvent event) {
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          _player.setVolume(0.5);
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          final wasPlaying = _loading || _player.playing;
          _resumeWhenFocusReturns = event.type == AudioInterruptionType.pause && wasPlaying;
          if (_loading) _loadHeldForFocus = _playRequestId;
          unawaited(_player.pause());
          _updatePlaybackState();
      }
      return;
    }
    switch (event.type) {
      case AudioInterruptionType.duck:
        _player.setVolume(1.0);
      case AudioInterruptionType.pause:
      case AudioInterruptionType.unknown:
        final held = _loadHeldForFocus;
        _loadHeldForFocus = null;
        if (!_resumeWhenFocusReturns) return;
        _resumeWhenFocusReturns = false;
        // Still loading: it plays when it's ready.
        if (_loading && held == _playRequestId) return;
        unawaited(_playHere());
    }
  }

  void _updatePlaybackState() {
    // Between songs (loading one, or past one that failed) the queue is still
    // playing, whatever the player reports.
    final settling = _loading || (_carryingOn && !_player.playing);
    final isPlaying = settling || _player.playing;
    var processingState =
        settling ? AudioProcessingState.buffering : _transformProcessingState(_player.processingState);
    if (processingState == AudioProcessingState.idle && !_stopped && !_queue.isEmpty) {
      processingState = _loadFailed ? AudioProcessingState.error : AudioProcessingState.ready;
    }

    final next = PlaybackState(
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
    );
    if (_onlyBufferMoved(playbackState.value, next)) return;
    playbackState.add(next);
  }

  /// While a song downloads the player reports progress every half second.
  /// Passing those on would refresh the notification and every screen that
  /// shows the player, with nothing visible changed: listeners work out the
  /// position from the last state, and nothing shows the buffered amount.
  static bool _onlyBufferMoved(PlaybackState last, PlaybackState next) =>
      last.playing == next.playing &&
      last.processingState == next.processingState &&
      last.queueIndex == next.queueIndex &&
      last.shuffleMode == next.shuffleMode &&
      last.repeatMode == next.repeatMode &&
      last.speed == next.speed &&
      last.errorCode == next.errorCode &&
      // Where the last state says the song is now, give or take.
      (next.updatePosition - last.position).abs() < const Duration(milliseconds: 750);

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
    if (_remote != null) {
      // Following a Jam host: it decides what plays next. Pausing emits
      // another completed state, so only pause once.
      _completionWatchdogTimer?.cancel();
      if (!_player.playing) return;
      await _player.pause();
      _updatePlaybackState();
      return;
    }
    _isAutoSkipping = true;
    _completionWatchdogTimer?.cancel();
    developer.log('Track completed ($reason). Moving on...', name: 'AudioHandler');
    try {
      final next = _queue.nextIndex(auto: true) ?? (await _extendQueue() ? _queue.nextIndex(auto: true) : null);
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

  /// Adds [autoplay]'s songs after the last one. True when any were added.
  Future<bool> _extendQueue() async {
    final source = autoplay;
    final last = _queue.tracks.isEmpty ? null : _queue.tracks.last;
    if (source == null || last == null || _remote != null || _queue.repeatMode != QueueRepeatMode.off) return false;
    if (_usesPlaybackCache && !await _network.isOnline()) return false;
    final requestId = _playRequestId;
    try {
      final more = await source(last, _queue.tracks).timeout(const Duration(seconds: 20));
      // The user started something else meanwhile.
      if (requestId != _playRequestId || more.isEmpty) return false;
      for (final t in more) {
        _queue.add(t);
      }
      _emitQueue();
      developer.log('Autoplay added ${more.length} songs after "${last.title}"', name: 'AudioHandler');
      return true;
    } catch (e) {
      developer.log('Autoplay failed: $e', name: 'AudioHandler');
      return false;
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
    final bool stop;
    _carryingOn = true;
    try {
      stop = await _tryPlayOnFrom(index);
    } finally {
      _carryingOn = false;
    }
    stop ? await _stopAtEnd() : _updatePlaybackState();
  }

  /// [_playOnFrom]'s search. True when nothing could play and it should stop.
  Future<bool> _tryPlayOnFrom(int index) async {
    final wrap = _queue.repeatMode == QueueRepeatMode.all;
    var token = _playRequestId;
    int? candidate = index;
    for (var tries = 0; candidate != null && tries < _queue.length; tries++) {
      final target = await _playableFrom(candidate, wrap: wrap);
      // The user chose something else meanwhile.
      if (token != _playRequestId) return false;
      if (target == null) {
        developer.log('Nothing left in the queue can play offline', name: 'AudioHandler');
        return true;
      }
      try {
        await _playAt(target);
        return false;
      } catch (e) {
        if (token + 1 != _playRequestId) return false;
        token = _playRequestId;
        developer.log('Passing over "${_queue.current?.title}": $e', name: 'AudioHandler');
        // The last song failing carries on with autoplay, as finishing it would.
        candidate = _indexAfter(target, wrap: wrap) ??
            (await _extendQueue() && token == _playRequestId ? _indexAfter(target, wrap: wrap) : null);
      }
    }
    return token == _playRequestId;
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
        _carryingOn = true;
        try {
          await _loadAndPlayTrack(track, startAt: position);
        } finally {
          _carryingOn = false;
        }
        return;
      }

      developer.log('Offline and "${track.title}" isn\'t on this device; moving on', name: 'AudioHandler');
      _recoveredTrack = track;
      _moveOn();
    } catch (e) {
      developer.log('Could not pick "${track.title}" up again: $e', name: 'AudioHandler');
      if (identical(currentTrack, track) && !_loading) {
        _moveOn();
      } else {
        _updatePlaybackState();
      }
    } finally {
      _recovering = false;
    }
  }

  /// Leaves a song that can't go on for the next one that can play.
  void _moveOn() {
    if (_remote != null) {
      unawaited(_stopAtEnd());
      return;
    }
    final next = _indexAfter(currentIndex, wrap: _queue.repeatMode == QueueRepeatMode.all);
    unawaited(next == null ? _carryOnPastEnd() : _playOnFrom(next));
  }

  /// The last song can't go on: autoplay's songs, else stop.
  Future<void> _carryOnPastEnd() async {
    final token = _playRequestId;
    final bool extended;
    _carryingOn = true;
    try {
      extended = await _extendQueue();
    } finally {
      _carryingOn = false;
    }
    if (token != _playRequestId) return;
    final next = extended ? _indexAfter(currentIndex, wrap: false) : null;
    await (next == null ? _stopAtEnd() : _playOnFrom(next));
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
    final remote = _remote;
    if (remote != null) {
      // In a Jam, picking a song puts it on next and skips to it.
      remote.playNext(tracks[startIndex.clamp(0, tracks.length - 1)]);
      remote.next();
      return;
    }
    _queue.load(tracks, startIndex: startIndex);
    // Offline, start at the first song from there that's on this device.
    await _playAt(await _playableFrom(_queue.index, wrap: true) ?? _queue.index);
  }

  /// Plays a single [Track], updating the current queue.
  Future<void> playTrack(Track track) async {
    final remote = _remote;
    if (remote != null) {
      remote.playNext(track);
      remote.next();
      return;
    }
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
    final remote = _remote;
    if (remote != null) return remote.playNext(track);
    final wasEmpty = _queue.isEmpty;
    _queue.playNext(track);
    _afterQueueEdit();
    if (wasEmpty) unawaited(_playAt(0));
  }

  void enqueue(Track track) {
    final remote = _remote;
    if (remote != null) return remote.add(track);
    final wasEmpty = _queue.isEmpty;
    _queue.add(track);
    _afterQueueEdit();
    if (wasEmpty) unawaited(_playAt(0));
  }

  void removeFromQueue(int index) {
    final remote = _remote;
    if (remote != null) return remote.remove(index);
    if (_queue.removeAt(index)) _afterQueueEdit();
  }

  void moveInQueue(int from, int to) {
    final remote = _remote;
    if (remote != null) return remote.move(from, to);
    if (_queue.move(from, to)) _afterQueueEdit();
  }

  void _afterQueueEdit() {
    _emitQueue();
    _preloadUpcomingTracks();
    _updatePlaybackState();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    final remote = _remote;
    if (remote != null) return remote.jumpTo(index);
    await _playAt(index);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (_remote != null) return;
    _queue.setShuffle(shuffleMode != AudioServiceShuffleMode.none);
    _afterQueueEdit();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    if (_remote != null) return;
    _queue.repeatMode = switch (repeatMode) {
      AudioServiceRepeatMode.none => QueueRepeatMode.off,
      AudioServiceRepeatMode.one => QueueRepeatMode.one,
      AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => QueueRepeatMode.all,
    };
    _preloadUpcomingTracks();
    _updatePlaybackState();
  }

  /// Plays [track] from [startAt] (the start unless a broken stream is
  /// being picked up again, or a Jam guest joins mid-song). With [autoplay]
  /// false it is left loaded and paused there.
  Future<void> _loadAndPlayTrack(Track track, {Duration startAt = Duration.zero, bool autoplay = true}) async {
    final requestId = ++_playRequestId;
    _loading = true;
    _loadFailed = false;
    _stopped = false;
    _resolvedVideoIdSubject.add(null);

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
      _resolvedVideoIdSubject.add(streamInfo.sourceVideoId);

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
      // On mobile data the copy would download every song twice: there it
      // is made only if streaming fails.
      final metered = _usesPlaybackCache && await _network.isMetered();
      if (requestId != _playRequestId) return;

      // Native, first play: start streaming at once (no wait for a download)
      // and save a local copy in the background for replays and instant seeks.
      // No request headers, so just_audio talks to the CDN directly instead of
      // through its proxy. Recently played tracks already resolved to a file.
      Future<AudioSource> sourceFor(ResolvedAudioStream stream) async {
        if (_usesPlaybackCache && PlaybackCache.shouldCache(stream)) {
          if (!metered) {
            backgroundCopy = _playbackCache.fileFor(track, stream);
            backgroundCopy!.ignore();
          }
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
        final copy = backgroundCopy ??
            (metered && PlaybackCache.shouldCache(activeStream) ? _playbackCache.fileFor(track, activeStream) : null);
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
      // Another app has the audio: wait, loaded, until it hands it back.
      if (!autoplay || _loadHeldForFocus == requestId) {
        _updatePlaybackState();
        _preloadUpcomingTracks();
        return;
      }
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
      _loadFailed = true;
      developer.log('Playback start failure', error: e, stackTrace: st, name: 'AudioHandler');
      // Moving on by itself: stay "playing" for the next song (see _carryingOn).
      // Otherwise an error, not idle: idle ends the Android playback service.
      if (!_carryingOn) {
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            playing: false,
          ),
        );
      }
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
    final remote = _remote;
    if (remote != null) return remote.play();
    _forgetInterruption();
    await _playHere();
  }

  /// The user chose to play or pause while another app had the audio;
  /// that choice stands when the audio comes back.
  void _forgetInterruption() {
    _resumeWhenFocusReturns = false;
    _loadHeldForFocus = null;
  }

  Future<void> _playHere() async {
    if (_player.processingState == ProcessingState.completed) {
      await _seekHere(Duration.zero);
    }
    // Not awaited: the future only completes when playback stops.
    unawaited(_player.play().catchError((Object e) {
      developer.log('play() failed: $e', name: 'AudioHandler');
    }));
    _updatePlaybackState();
  }

  @override
  Future<void> pause() async {
    final remote = _remote;
    if (remote != null) return remote.pause();
    _forgetInterruption();
    await _pauseHere();
  }

  Future<void> _pauseHere() async {
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
    _stopped = true;
    await _player.stop();
    _updatePlaybackState();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    final remote = _remote;
    if (remote != null) return remote.seek(position);
    await _seekHere(position);
  }

  Future<void> _seekHere(Duration position) async {
    await _player.seek(position);
    _updatePlaybackState();
  }

  @override
  Future<void> skipToNext() async {
    final remote = _remote;
    if (remote != null) return remote.next();
    // On the last song a skip carries on with autoplay, else wraps around.
    final atEnd = _queue.index == _queue.length - 1 && _queue.repeatMode == QueueRepeatMode.off;
    if (atEnd) await _extendQueue();
    final next = _queue.nextIndex(auto: false);
    if (next == null) return;
    // Offline, go to the next song that's on this device.
    await _playAt(await _playableFrom(next, wrap: true) ?? next);
  }

  @override
  Future<void> skipToPrevious() async {
    final remote = _remote;
    if (remote != null) return remote.previous();
    if (_queue.isEmpty) return;
    final prev = _queue.previousIndex();
    if (_player.position.inSeconds > 3 || prev == null || prev == currentIndex) {
      await _seekHere(Duration.zero);
    } else {
      final wrap = _queue.repeatMode == QueueRepeatMode.all;
      await _playAt(await _playableFrom(prev, wrap: wrap, step: -1) ?? prev);
    }
  }

  // Jam guest: follows the host, bypassing [remote].

  /// Shows [tracks] as the queue with [index] current, playing nothing.
  void followQueue(List<Track> tracks, int index) {
    _queue.setShuffle(false);
    _queue.load(tracks, startIndex: index < 0 ? 0 : index);
    _emitQueue();
    _preloadUpcomingTracks();
    _updatePlaybackState();
  }

  /// Loads the current song at [startAt] and plays it, or leaves it paused
  /// there when [play] is false.
  Future<void> followLoadCurrent({required Duration startAt, required bool play}) async {
    final track = currentTrack;
    if (track == null) return;
    _recoveredTrack = null;
    await _loadAndPlayTrack(track, startAt: startAt, autoplay: play);
  }

  Future<void> followPlaying(bool playing) => playing ? _playHere() : _pauseHere();

  Future<void> followSeek(Duration position) => _seekHere(position);

  Future<void> setVolume(double volume) => _player.setVolume(volume);

  Future<void> release() async {
    _completionWatchdogTimer?.cancel();
    await _playbackEventSub?.cancel();
    await _playerStateSub?.cancel();
    await _interruptionSub?.cancel();
    await _noisySub?.cancel();
    await _currentIndexSubject.close();
    await _queueSubject.close();
    await _resolvedVideoIdSubject.close();
    _streamResolver.dispose();
    _playbackCache.dispose();
    await _player.dispose();
  }
}
