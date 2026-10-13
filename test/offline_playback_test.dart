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

/// Records what it was asked to play; songs end and streams break on cue.
class _FakePlayer implements AudioPlayer {
  final _events = StreamController<PlaybackEvent>.broadcast();
  final _states = StreamController<PlayerState>.broadcast();
  final loads = <({Uri uri, Duration? at})>[];
  final failing = <Uri>{};

  bool _playing = false;
  ProcessingState _state = ProcessingState.idle;
  Duration _position = Duration.zero;
  Duration? _duration;

  Uri? get current => loads.isEmpty ? null : loads.last.uri;

  void _emit() => _states.add(PlayerState(_playing, _state));

  void finishSong() {
    _position = _duration!;
    _state = ProcessingState.completed;
    _emit();
  }

  void breakStream({required Duration at}) {
    _position = at;
    _state = ProcessingState.idle;
    _events.addError(PlayerException(0, 'Source error', 0));
  }

  @override
  Future<Duration?> setAudioSource(AudioSource audioSource,
      {bool preload = true, int? initialIndex, Duration? initialPosition}) async {
    final uri = (audioSource as UriAudioSource).uri;
    loads.add((uri: uri, at: initialPosition));
    if (failing.contains(uri)) throw PlayerException(0, 'Source error', 0);
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

class _Store implements LocalTrackStore {
  final byId = <String, LocalTrackEntry>{};

  void put(Track t, String path) => byId[t.id] = LocalTrackEntry(
        trackId: t.id,
        normKey: LocalTrackStore.normKeyFor(t),
        title: t.title,
        artist: t.artist,
        fileName: path,
        fileUri: Uri.file('/data/$path'),
        bytes: 3200000,
        format: 'm4a',
        duration: const Duration(seconds: 200),
        sourceVideoId: t.id.replaceFirst('yt_', ''),
        downloadedAt: DateTime(2026),
      );

  @override
  bool get isSupported => true;
  @override
  Future<LocalTrackEntry?> lookup(Track track) async => byId[track.id];
  @override
  Future<LocalTrackEntry> save(Track track, Stream<List<int>> bytes,
          {required String format, required Duration duration, required String sourceVideoId, int? expectedBytes}) =>
      throw UnsupportedError('read-only');
  @override
  Future<int> remove(Track track) async => byId.remove(track.id)?.bytes ?? 0;
  @override
  Future<List<LocalTrackEntry>> entries() async => byId.values.toList();
  @override
  Future<int> totalBytes() async => 0;
}

/// YouTube extraction that only works online.
class _Extractor implements AudioExtractor {
  _Extractor(this.online);
  final bool Function() online;
  final extracted = <String>[];

  @override
  String get name => 'fake';
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ExtractedAudio> extract(String videoId) async {
    extracted.add(videoId);
    if (!online()) throw StateError('no connection');
    return ExtractedAudio(url: Uri.parse('https://media.example/$videoId'), container: 'm4a', duration: const Duration(seconds: 200));
  }

  @override
  Future<ExtractedAudio> searchSong(String query) => Future.error(UnsupportedError('none'));
  @override
  void dispose() {}
}

Track _song(String id) => Track(
      id: 'yt_$id',
      title: 'Song $id',
      artist: 'Artist',
      expectedDuration: const Duration(seconds: 200),
      artworkUri: Uri.parse('https://art.example/$id.jpg'),
    );

final _a = _song('aaaaaaaaaaa');
final _b = _song('bbbbbbbbbbb');
final _c = _song('ccccccccccc');

void main() {
  late _FakePlayer player;
  late _Store downloads;
  late _Store cache;
  late _Extractor extractor;
  late SymphonyAudioHandler handler;
  var online = true;

  setUp(() {
    online = true;
    player = _FakePlayer();
    downloads = _Store();
    cache = _Store();
    extractor = _Extractor(() => online);
    handler = SymphonyAudioHandler(
      player: player,
      streamResolver: AudioStreamResolverService(
        extractor: extractor,
        localTracks: downloads,
        matchIndex: MemoryMatchIndex(),
        isWeb: false,
      ),
      // Saving a playback copy fails at once; tests add copies themselves.
      playbackCache: PlaybackCache(store: cache, httpClient: MockClient((_) async => http.Response('', 404))),
      notificationPermission: NotificationPermissionService(isAndroid: () => false),
      network: NetworkStatus(probe: () async => online, maxAge: Duration.zero),
    );
  });

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(done(), isTrue);
  }

  group('offline', () {
    test('a downloaded playlist plays on by itself, past songs that are not downloaded', () async {
      downloads
        ..put(_a, 'a.m4a')
        ..put(_c, 'c.m4a');
      online = false;

      await handler.playQueue([_a, _b, _c]);
      expect(player.current, Uri.file('/data/a.m4a'));
      expect(player.playing, isTrue);

      player.finishSong();
      await until(() => player.current == Uri.file('/data/c.m4a'));

      expect(handler.currentTrack, same(_c));
      expect(player.playing, isTrue);
      expect(extractor.extracted, isEmpty);
    });

    test('playing a queue starts at the first song on the device', () async {
      downloads.put(_c, 'c.m4a');
      online = false;

      await handler.playQueue([_a, _b, _c]);

      expect(player.current, Uri.file('/data/c.m4a'));
      expect(extractor.extracted, isEmpty);
    });

    test('next skips songs that are not on the device', () async {
      downloads
        ..put(_a, 'a.m4a')
        ..put(_c, 'c.m4a');
      online = false;
      await handler.playQueue([_a, _b, _c]);

      await handler.skipToNext();

      expect(handler.currentTrack, same(_c));
    });

    test('a song that is not on the device fails at once instead of searching', () async {
      online = false;

      await expectLater(handler.playTrack(_b), throwsA(anything));
      expect(extractor.extracted, isEmpty);
    });

    test('the queue stops at the end when nothing after can play', () async {
      downloads.put(_a, 'a.m4a');
      online = false;
      await handler.playQueue([_a, _b]);

      player.finishSong();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(player.loads, hasLength(1));
      expect(player.playing, isFalse);
    });
  });

  group('when the stream breaks mid-song', () {
    test('it carries on from the copy on the device, at the same spot', () async {
      await handler.playQueue([_a, _b]);
      expect(player.current, Uri.parse('https://media.example/aaaaaaaaaaa'));
      // The background copy finished while the song streamed.
      cache.put(_a, 'cache_a.m4a');
      online = false;

      player.breakStream(at: const Duration(seconds: 61));
      await until(() => player.current == Uri.file('/data/cache_a.m4a'));

      expect(player.loads.last.at, const Duration(seconds: 61));
      expect(handler.currentTrack, same(_a));
      expect(player.playing, isTrue);
    });

    test('offline with no copy, it goes on to the next song that is downloaded', () async {
      downloads.put(_c, 'c.m4a');
      await handler.playQueue([_a, _b, _c]);
      online = false;

      player.breakStream(at: const Duration(seconds: 30));
      await until(() => player.current == Uri.file('/data/c.m4a'));

      expect(handler.currentTrack, same(_c));
    });

    test('online, it fetches a new link and resumes there', () async {
      await handler.playQueue([_a, _b]);

      player.breakStream(at: const Duration(seconds: 45));
      await until(() => player.loads.length == 2);

      expect(player.loads.last.uri, Uri.parse('https://media.example/aaaaaaaaaaa'));
      expect(player.loads.last.at, const Duration(seconds: 45));
      expect(extractor.extracted.where((id) => id == 'aaaaaaaaaaa'), hasLength(2));
    });
  });

  test('a song that will not load is passed over when the last one ends', () async {
    downloads.put(_a, 'a.m4a');
    player.failing.add(Uri.parse('https://media.example/bbbbbbbbbbb'));
    await handler.playQueue([_a, _b, _c]);

    player.finishSong();
    await until(() => player.current == Uri.parse('https://media.example/ccccccccccc'));

    expect(handler.currentTrack, same(_c));
    expect(player.playing, isTrue);
  });
}
