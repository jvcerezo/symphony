import 'dart:async';

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
import 'package:symphony/features/audio_player/domain/playback_remote.dart';

/// Plays whatever it is given; songs end on cue.
class _FakePlayer implements AudioPlayer {
  final _events = StreamController<PlaybackEvent>.broadcast();
  final _states = StreamController<PlayerState>.broadcast();
  final loads = <({Uri uri, Duration? at})>[];

  bool _playing = false;
  ProcessingState _state = ProcessingState.idle;
  Duration _position = Duration.zero;
  Duration? _duration;

  void _emit() => _states.add(PlayerState(_playing, _state));

  void finishSong() {
    _position = _duration!;
    _state = ProcessingState.completed;
    _emit();
  }

  @override
  Future<Duration?> setAudioSource(AudioSource audioSource,
      {bool preload = true, int? initialIndex, Duration? initialPosition}) async {
    loads.add((uri: (audioSource as UriAudioSource).uri, at: initialPosition));
    _duration = const Duration(seconds: 200);
    _position = initialPosition ?? Duration.zero;
    _state = ProcessingState.ready;
    _emit();
    return _duration;
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
  Duration? get duration => _duration;
  @override
  Duration get bufferedPosition => _position;
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

/// Records the actions sent to the Jam host.
class _Remote implements PlaybackRemote {
  final sent = <String>[];
  @override
  void play() => sent.add('play');
  @override
  void pause() => sent.add('pause');
  @override
  void seek(Duration position) => sent.add('seek ${position.inSeconds}');
  @override
  void next() => sent.add('next');
  @override
  void previous() => sent.add('previous');
  @override
  void jumpTo(int index) => sent.add('jump $index');
  @override
  void add(Track track) => sent.add('add ${track.id}');
  @override
  void playNext(Track track) => sent.add('playNext ${track.id}');
  @override
  void remove(int index) => sent.add('remove $index');
  @override
  void move(int from, int to) => sent.add('move $from $to');
}

Track _song(String id) => Track(id: 'yt_$id', title: 'Song $id', artist: 'Artist',
    expectedDuration: const Duration(seconds: 200), artworkUri: Uri.parse('https://art.example/$id.jpg'));

final _a = _song('aaaaaaaaaaa');
final _b = _song('bbbbbbbbbbb');

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

  test('the video a song plays from is published once it loads', () async {
    await handler.playTrack(_a);
    expect(handler.resolvedVideoIdStream.value, 'aaaaaaaaaaa');
  });

  group('with a remote (Jam guest)', () {
    late _Remote remote;

    setUp(() async {
      await handler.playQueue([_a, _b]);
      remote = _Remote();
      handler.remote = remote;
    });

    test("the user's actions go to the host instead of playing here", () async {
      final loadsBefore = player.loads.length;

      await handler.pause();
      await handler.seek(const Duration(seconds: 42));
      await handler.skipToNext();
      await handler.skipToPrevious();
      await handler.skipToQueueItem(1);
      handler.enqueue(_b);
      handler.playNext(_b);
      handler.removeFromQueue(1);
      handler.moveInQueue(0, 1);
      await handler.playTrack(_b);

      expect(remote.sent, [
        'pause',
        'seek 42',
        'next',
        'previous',
        'jump 1',
        'add yt_bbbbbbbbbbb',
        'playNext yt_bbbbbbbbbbb',
        'remove 1',
        'move 0 1',
        'playNext yt_bbbbbbbbbbb',
        'next',
      ]);
      expect(player.playing, isTrue);
      expect(player.loads, hasLength(loadsBefore));
      expect(handler.currentQueue, [_a, _b]);
    });

    test('a song that ends waits for the host instead of moving on', () async {
      player.finishSong();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(handler.currentTrack, same(_a));
      expect(player.loads, hasLength(1));
      expect(player.playing, isFalse);
    });

    test('follow methods drive playback directly', () async {
      handler.followQueue([_b, _a], 0);
      expect(handler.currentQueue, [_b, _a]);

      await handler.followLoadCurrent(startAt: const Duration(seconds: 30), play: false);
      expect(player.loads.last, (uri: Uri.parse('https://media.example/bbbbbbbbbbb'), at: const Duration(seconds: 30)));
      expect(player.playing, isFalse);

      await handler.followPlaying(true);
      expect(player.playing, isTrue);
      await handler.followSeek(const Duration(seconds: 31));
      expect(handler.position, const Duration(seconds: 31));
      expect(remote.sent, isEmpty);
    });

    test('without the remote, the handler is back to normal', () async {
      handler.remote = null;
      await handler.pause();
      expect(player.playing, isFalse);
      expect(remote.sent, isEmpty);
    });
  });
}
