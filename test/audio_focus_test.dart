import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio/just_audio.dart';
import 'package:symphony/core/services/network_status.dart';
import 'package:symphony/core/services/notification_permission_service.dart';
import 'package:symphony/features/audio_player/data/services/audio_stream_resolver_service.dart';
import 'package:symphony/features/audio_player/data/services/extraction/audio_extractor.dart';
import 'package:symphony/features/audio_player/data/services/matching/match_index.dart';
import 'package:symphony/features/audio_player/data/services/offline/local_track_store.dart';
import 'package:symphony/features/audio_player/data/services/offline/playback_cache.dart';
import 'package:symphony/features/audio_player/data/services/symphony_audio_handler.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';

/// Plays whatever it is given; a load can be held open with [gate].
class _FakePlayer implements AudioPlayer {
  final _events = StreamController<PlaybackEvent>.broadcast();
  final _states = StreamController<PlayerState>.broadcast();
  final loaded = <Uri>[];
  Completer<void>? gate;

  bool _playing = false;
  ProcessingState _state = ProcessingState.idle;
  double volumeSet = 1;

  void _emit() => _states.add(PlayerState(_playing, _state));

  @override
  Future<Duration?> setAudioSource(AudioSource audioSource,
      {bool preload = true, int? initialIndex, Duration? initialPosition}) async {
    await gate?.future;
    loaded.add((audioSource as UriAudioSource).uri);
    _state = ProcessingState.ready;
    _emit();
    return const Duration(seconds: 200);
  }

  @override
  Future<void> play() async {
    _playing = true;
    _emit();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _emit();
  }

  @override
  Future<void> setVolume(double volume) async => volumeSet = volume;
  @override
  Future<void> seek(Duration? position, {int? index}) async {}
  @override
  Future<void> stop() async => pause();
  @override
  Future<void> dispose() async {}
  @override
  Stream<PlaybackEvent> get playbackEventStream => _events.stream;
  @override
  Stream<PlayerState> get playerStateStream => _states.stream;
  @override
  bool get playing => _playing;
  @override
  ProcessingState get processingState => _state;
  @override
  Duration get position => Duration.zero;
  @override
  Duration? get duration => const Duration(seconds: 200);
  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  double get speed => 1;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoStore implements LocalTrackStore {
  @override
  bool get isSupported => true;
  @override
  Future<LocalTrackEntry?> lookup(Track track) async => null;
  @override
  Future<LocalTrackEntry> save(Track track, Stream<List<int>> bytes,
          {required String format, required Duration duration, required String sourceVideoId, int? expectedBytes}) =>
      throw UnsupportedError('read-only');
  @override
  Future<int> remove(Track track) async => 0;
  @override
  Future<List<LocalTrackEntry>> entries() async => const [];
  @override
  Future<int> totalBytes() async => 0;
}

class _Extractor implements AudioExtractor {
  @override
  String get name => 'fake';
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ExtractedAudio> extract(String videoId) async =>
      ExtractedAudio(url: Uri.parse('https://media.example/$videoId'), container: 'm4a', duration: const Duration(seconds: 200));
  @override
  Future<ExtractedAudio> searchSong(String query) => Future.error(UnsupportedError('none'));
  @override
  void dispose() {}
}

Track _song(String id) => Track(id: 'yt_$id', title: 'Song $id', artist: 'Artist',
    expectedDuration: const Duration(seconds: 200), artworkUri: Uri.parse('https://art.example/$id.jpg'));

final _a = _song('aaaaaaaaaaa');
final _b = _song('bbbbbbbbbbb');

final _shortLoss = AudioInterruptionEvent(true, AudioInterruptionType.pause);
final _lastingLoss = AudioInterruptionEvent(true, AudioInterruptionType.unknown);
final _focusBack = AudioInterruptionEvent(false, AudioInterruptionType.pause);

void main() {
  late _FakePlayer player;
  late SymphonyAudioHandler handler;

  setUp(() {
    player = _FakePlayer();
    handler = SymphonyAudioHandler(
      player: player,
      streamResolver: AudioStreamResolverService(
        extractor: _Extractor(),
        localTracks: _NoStore(),
        matchIndex: MemoryMatchIndex(),
        isWeb: false,
      ),
      playbackCache: PlaybackCache(store: _NoStore(), httpClient: MockClient((_) async => http.Response('', 404))),
      notificationPermission: NotificationPermissionService(isAndroid: () => false),
      network: NetworkStatus(probe: () async => true, maxAge: Duration.zero),
    );
  });

  test('a short loss of the audio pauses, then resumes', () async {
    await handler.playTrack(_a);

    handler.handleInterruption(_shortLoss);
    expect(player.playing, isFalse);

    handler.handleInterruption(_focusBack);
    await pumpEventQueue();
    expect(player.playing, isTrue);
  });

  test('a song the user had paused stays paused when the audio comes back', () async {
    await handler.playTrack(_a);
    await handler.pause();

    handler.handleInterruption(_shortLoss);
    handler.handleInterruption(_focusBack);
    await pumpEventQueue();
    expect(player.playing, isFalse);
  });

  test('pausing during the interruption is kept', () async {
    await handler.playTrack(_a);

    handler.handleInterruption(_shortLoss);
    await handler.pause();
    handler.handleInterruption(_focusBack);
    await pumpEventQueue();
    expect(player.playing, isFalse);
  });

  test('another player taking over pauses for good', () async {
    await handler.playTrack(_a);

    handler.handleInterruption(_lastingLoss);
    handler.handleInterruption(_focusBack);
    await pumpEventQueue();
    expect(player.playing, isFalse);
  });

  test('a song loading when the audio is lost finishes loading and waits for it', () async {
    await handler.playTrack(_a);
    player.gate = Completer<void>();
    final loading = handler.playTrack(_b);
    await pumpEventQueue();

    handler.handleInterruption(_shortLoss);
    player.gate!.complete();
    await loading;
    expect(player.loaded.last, Uri.parse('https://media.example/bbbbbbbbbbb'));
    expect(player.playing, isFalse, reason: 'another app still has the audio');

    handler.handleInterruption(_focusBack);
    await pumpEventQueue();
    expect(player.playing, isTrue);
    expect(handler.mediaItem.value?.id, _b.toMediaItem().id);
  });

  test('the audio coming back mid-load lets the song start when ready', () async {
    await handler.playTrack(_a);
    player.gate = Completer<void>();
    final loading = handler.playTrack(_b);
    await pumpEventQueue();

    handler.handleInterruption(_shortLoss);
    handler.handleInterruption(_focusBack);
    player.gate!.complete();
    await loading;
    expect(player.playing, isTrue);
  });

  test('ducking lowers the volume and restores it', () async {
    await handler.playTrack(_a);

    handler.handleInterruption(AudioInterruptionEvent(true, AudioInterruptionType.duck));
    expect(player.volumeSet, 0.5);
    handler.handleInterruption(AudioInterruptionEvent(false, AudioInterruptionType.duck));
    expect(player.volumeSet, 1.0);
    expect(player.playing, isTrue);
  });
}
