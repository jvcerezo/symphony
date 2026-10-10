import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:symphony/features/audio_player/data/services/audio_stream_resolver_service.dart';
import 'package:symphony/features/audio_player/data/services/offline/local_track_store.dart';
import 'package:symphony/features/audio_player/data/services/offline/local_track_store_io.dart';
import 'package:symphony/features/audio_player/data/services/offline/offline_download_service.dart';
import 'package:symphony/features/audio_player/domain/entities/resolved_audio_stream.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';

const _track = Track(
  id: 'spotify:track:abc123',
  title: 'Blinding Lights',
  artist: 'The Weeknd',
  expectedDuration: Duration(seconds: 200),
);

LocalTrackEntry _entryFor(Track t, {int bytes = 3200000}) => LocalTrackEntry(
      trackId: t.id,
      normKey: LocalTrackStore.normKeyFor(t),
      title: t.title,
      artist: t.artist,
      fileName: 'local.m4a',
      fileUri: Uri.file('/data/offline_tracks/local.m4a'),
      bytes: bytes,
      format: 'm4a',
      duration: const Duration(seconds: 200),
      sourceVideoId: 'vid_local',
      downloadedAt: DateTime(2026),
    );

/// In-memory [LocalTrackStore] that records calls.
class FakeLocalTrackStore implements LocalTrackStore {
  FakeLocalTrackStore({this.isSupported = true, this.throwOnLookup = false});

  @override
  final bool isSupported;
  final bool throwOnLookup;
  final Map<String, LocalTrackEntry> byId = {};
  int lookups = 0;
  final List<List<int>> saved = [];

  @override
  Future<LocalTrackEntry?> lookup(Track track) async {
    lookups++;
    if (throwOnLookup) throw const FileSystemException('disk unavailable');
    return byId[track.id];
  }

  @override
  Future<LocalTrackEntry> save(
    Track track,
    Stream<List<int>> bytes, {
    required String format,
    required Duration duration,
    required String sourceVideoId,
    int? expectedBytes,
  }) async {
    final data = <int>[];
    await for (final c in bytes) {
      data.addAll(c);
    }
    saved.add(data);
    final entry = _entryFor(track, bytes: data.length);
    byId[track.id] = entry;
    return entry;
  }

  @override
  Future<int> remove(Track track) async => byId.remove(track.id)?.bytes ?? 0;

  @override
  Future<List<LocalTrackEntry>> entries() async => byId.values.toList();

  @override
  Future<int> totalBytes() async => byId.values.fold<int>(0, (s, e) => s + e.bytes);
}

/// Server `/api/resolve` stub; counts requests.
class ResolveServer {
  int requests = 0;
  late final MockClient client = MockClient((req) async {
    requests++;
    if (req.url.path == '/api/resolve') {
      return http.Response(
        jsonEncode({'streamUrl': '/api/stream?videoId=srv1', 'durationMs': 201000, 'videoId': 'srv1', 'format': 'm4a'}),
        200,
      );
    }
    return http.Response('not found', 404);
  });
}

void main() {
  group('AudioStreamResolverService resolution order', () {
    late ResolveServer server;
    setUp(() => server = ResolveServer());

    AudioStreamResolverService resolverWith(LocalTrackStore store, {bool isWeb = false}) {
      final r = AudioStreamResolverService(httpClient: server.client, localTracks: store, isWeb: isWeb);
      addTearDown(r.dispose);
      return r;
    }

    test('on-device file wins over memory cache and network', () async {
      final store = FakeLocalTrackStore()..byId[_track.id] = _entryFor(_track);
      final resolver = resolverWith(store);
      resolver.cacheResolvedStream(
        _track.id,
        ResolvedAudioStream(
          streamUri: Uri.parse('https://example.com/remote.m4a'),
          duration: const Duration(seconds: 200),
          bitrateKbps: 128,
          format: 'm4a',
          sourceVideoId: 'remote',
        ),
      );

      final resolved = await resolver.resolveBestAudioStream(_track);

      expect(resolved.streamUri.scheme, 'file');
      expect(resolved.streamUri, Uri.file('/data/offline_tracks/local.m4a'));
      expect(resolved.sourceVideoId, 'vid_local');
      expect(resolved.bitrateKbps, 128); // 3.2 MB over 200 s
      expect(server.requests, 0);
    });

    test('memory cache is used when nothing is downloaded', () async {
      final store = FakeLocalTrackStore();
      final resolver = resolverWith(store);
      final cached = ResolvedAudioStream(
        streamUri: Uri.parse('https://example.com/cached.m4a'),
        duration: const Duration(seconds: 200),
        bitrateKbps: 128,
        format: 'm4a',
        sourceVideoId: 'cached',
      );
      resolver.cacheResolvedStream(_track.id, cached);

      final resolved = await resolver.resolveBestAudioStream(_track);

      expect(resolved.streamUri, cached.streamUri);
      expect(store.lookups, 1);
      expect(server.requests, 0);
    });

    test('falls through to the server when there is no local file', () async {
      final store = FakeLocalTrackStore();
      final resolver = resolverWith(store);

      final resolved = await resolver.resolveBestAudioStream(_track);

      expect(resolved.streamUri, Uri.parse('http://127.0.0.1:8080/api/stream?videoId=srv1'));
      expect(store.lookups, 1);
      expect(server.requests, 1);
    });

    test('a failing local index falls back to the network', () async {
      final resolver = resolverWith(FakeLocalTrackStore(throwOnLookup: true));

      final resolved = await resolver.resolveBestAudioStream(_track);

      expect(resolved.sourceVideoId, 'srv1');
    });

    test('web never consults the local store', () async {
      final store = FakeLocalTrackStore()..byId[_track.id] = _entryFor(_track);
      final resolver = resolverWith(store, isWeb: true);

      // On web the origin comes from Uri.base, which is not http in tests,
      // so nothing resolves; the point is the store is untouched.
      expect(await resolver.resolveLocal(_track), isNull);
      expect(store.lookups, 0);
    });

    test('unsupported store is skipped', () async {
      final store = FakeLocalTrackStore(isSupported: false)..byId[_track.id] = _entryFor(_track);
      final resolver = resolverWith(store);

      final resolved = await resolver.resolveBestAudioStream(_track);

      expect(resolved.sourceVideoId, 'srv1');
      expect(store.lookups, 0);
    });

    test('deleting a download takes effect on the next resolve', () async {
      final store = FakeLocalTrackStore()..byId[_track.id] = _entryFor(_track);
      final resolver = resolverWith(store);

      expect((await resolver.resolveBestAudioStream(_track)).streamUri.scheme, 'file');
      await store.remove(_track);
      expect((await resolver.resolveBestAudioStream(_track)).streamUri.scheme, 'http');
    });
  });

  group('OfflineDownloadService', () {
    final remote = ResolvedAudioStream(
      streamUri: Uri.parse('https://symphony.example/api/stream?videoId=srv1'),
      duration: const Duration(seconds: 201),
      bitrateKbps: 160,
      format: 'm4a',
      sourceVideoId: 'srv1',
    );

    test('streams the resolved audio into the store and reports progress', () async {
      final store = FakeLocalTrackStore();
      var resolves = 0;
      final progress = <int>[];
      final service = OfflineDownloadService(
        resolve: (_) async {
          resolves++;
          return remote;
        },
        store: store,
        httpClient: MockClient((req) async {
          expect(req.url, remote.streamUri);
          return http.Response.bytes(List<int>.filled(1000, 7), 200);
        }),
      );

      final entry = await service.download(_track, onProgress: (received, _) => progress.add(received));

      expect(entry.bytes, 1000);
      expect(store.saved.single.length, 1000);
      expect(progress.last, 1000);
      expect(resolves, 1);
    });

    test('skips network entirely when already downloaded', () async {
      final store = FakeLocalTrackStore()..byId[_track.id] = _entryFor(_track);
      final service = OfflineDownloadService(
        resolve: (_) async => fail('should not resolve'),
        store: store,
        httpClient: MockClient((_) async => fail('should not fetch')),
      );

      expect((await service.download(_track)).sourceVideoId, 'vid_local');
    });

    test('concurrent requests for one track share a download', () async {
      var fetches = 0;
      final service = OfflineDownloadService(
        resolve: (_) async => remote,
        store: FakeLocalTrackStore(),
        httpClient: MockClient((_) async {
          fetches++;
          return http.Response.bytes([1, 2, 3], 200);
        }),
      );

      await Future.wait([service.download(_track), service.download(_track)]);
      expect(fetches, 1);
    });

    test('non-200 responses fail and store nothing', () async {
      final store = FakeLocalTrackStore();
      final service = OfflineDownloadService(
        resolve: (_) async => remote,
        store: store,
        httpClient: MockClient((_) async => http.Response('gone', 403)),
      );

      await expectLater(service.download(_track), throwsA(isA<http.ClientException>()));
      expect(store.byId, isEmpty);
    });

    test('is unavailable when the store is unsupported (web)', () async {
      final service = OfflineDownloadService(
        resolve: (_) async => remote,
        store: const UnsupportedLocalTrackStore(),
        httpClient: MockClient((_) async => http.Response('', 200)),
      );

      expect(service.isSupported, isFalse);
      await expectLater(service.download(_track), throwsUnsupportedError);
    });
  });

  group('IoLocalTrackStore', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('symphony_offline_test'));
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    IoLocalTrackStore storeAt() => IoLocalTrackStore(baseDirectory: () async => dir);

    Future<LocalTrackEntry> saveBytes(IoLocalTrackStore store, Track t, List<int> data, {int? expected}) =>
        store.save(
          t,
          Stream.value(data),
          format: 'm4a',
          duration: const Duration(seconds: 200),
          sourceVideoId: 'v1',
          expectedBytes: expected,
        );

    test('saves, finds by id or normalized name, and persists the index', () async {
      final store = storeAt();
      final entry = await saveBytes(store, _track, [1, 2, 3, 4]);

      expect(await File.fromUri(entry.fileUri).readAsBytes(), [1, 2, 3, 4]);
      expect(entry.fileUri.path.endsWith('.m4a'), isTrue);

      final reopened = storeAt();
      expect((await reopened.lookup(_track))?.bytes, 4);
      final sameSongOtherId = _track.copyWith(id: 'itunes_999');
      expect((await reopened.lookup(sameSongOtherId))?.trackId, _track.id);
      expect(await reopened.totalBytes(), 4);
    });

    test('remove deletes the file and reports bytes freed', () async {
      final store = storeAt();
      final entry = await saveBytes(store, _track, [1, 2, 3]);

      expect(await store.remove(_track), 3);
      expect(await File.fromUri(entry.fileUri).exists(), isFalse);
      expect(await store.lookup(_track), isNull);
      expect(await store.entries(), isEmpty);
    });

    test('drops index entries whose file vanished', () async {
      final store = storeAt();
      final entry = await saveBytes(store, _track, [9]);
      await File.fromUri(entry.fileUri).delete();

      expect(await store.lookup(_track), isNull);
      expect(await storeAt().entries(), isEmpty);
    });

    test('rejects a truncated download and leaves no files behind', () async {
      final store = storeAt();

      await expectLater(saveBytes(store, _track, [1, 2], expected: 10), throwsA(isA<LocalTrackStoreException>()));
      expect(await store.lookup(_track), isNull);
      expect(dir.listSync().whereType<File>().where((f) => !f.path.endsWith('.json')), isEmpty);
    });
  });
}
