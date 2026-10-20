import 'dart:async';

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

/// Test doubles for the audio handler.
/// Plays whatever it is given; a load can be held open with [gate].
class FakePlayer implements AudioPlayer {
  final _events = StreamController<PlaybackEvent>.broadcast();
  final _states = StreamController<PlayerState>.broadcast();
  final loaded = <Uri>[];
  Completer<void>? gate;

  bool _playing = false;
  ProcessingState _state = ProcessingState.idle;
  double volumeSet = 1;
  Duration _position = Duration.zero;

  void _emit() => _states.add(PlayerState(_playing, _state));

  /// The song plays to its end.
  void finishSong() {
    _position = const Duration(seconds: 200);
    _state = ProcessingState.completed;
    _emit();
  }

  @override
  Future<Duration?> setAudioSource(AudioSource audioSource,
      {bool preload = true, int? initialIndex, Duration? initialPosition}) async {
    await gate?.future;
    loaded.add((audioSource as UriAudioSource).uri);
    _position = initialPosition ?? Duration.zero;
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
  Future<void> seek(Duration? position, {int? index}) async => _position = position ?? Duration.zero;
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
  Duration get position => _position;
  @override
  Duration? get duration => const Duration(seconds: 200);
  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  double get speed => 1;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class NoStore implements LocalTrackStore {
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

class FakeExtractor implements AudioExtractor {
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

Track song(String id) => Track(id: 'yt_$id', title: 'Song $id', artist: 'Artist',
    expectedDuration: const Duration(seconds: 200), artworkUri: Uri.parse('https://art.example/$id.jpg'));

/// A handler around [player] that finds every song online at once, while
/// [isOnline] (default: always).
SymphonyAudioHandler handlerFor(FakePlayer player, {bool Function()? isOnline}) => SymphonyAudioHandler(
      player: player,
      streamResolver: AudioStreamResolverService(
        extractor: FakeExtractor(),
        localTracks: NoStore(),
        matchIndex: MemoryMatchIndex(),
        isWeb: false,
      ),
      playbackCache: PlaybackCache(store: NoStore(), httpClient: MockClient((_) async => http.Response('', 404))),
      notificationPermission: NotificationPermissionService(isAndroid: () => false),
      network: NetworkStatus(probe: () async => isOnline?.call() ?? true, maxAge: Duration.zero),
    );
