import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:symphony/features/audio_player/data/services/offline/chunked_download.dart';
import 'package:symphony/features/audio_player/data/services/offline/local_track_store_io.dart';
import 'package:symphony/features/audio_player/data/services/offline/playback_cache.dart';
import 'package:symphony/features/audio_player/domain/entities/resolved_audio_stream.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';

/// Serves [data] honoring single `bytes=a-b` ranges; counts requests.
class RangeServer {
  RangeServer(this.data, {this.ignoreRange = false});
  final List<int> data;
  final bool ignoreRange;
  int requests = 0;

  late final MockClient client = MockClient((req) async {
    requests++;
    final range = req.headers['Range'];
    if (ignoreRange || range == null) return http.Response.bytes(data, 200);
    final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
    final start = int.parse(m.group(1)!);
    if (start >= data.length) return http.Response('', 416);
    final end = (int.parse(m.group(2)!)).clamp(0, data.length - 1);
    return http.Response.bytes(
      data.sublist(start, end + 1),
      206,
      headers: {'content-range': 'bytes $start-$end/${data.length}'},
    );
  });
}

List<int> _bytes(int n) => List<int>.generate(n, (i) => i % 251);

Future<List<int>> _collect(Stream<List<int>> s) async => [for (final c in await s.toList()) ...c];

ResolvedAudioStream _stream(String id) => ResolvedAudioStream(
      streamUri: Uri.parse('https://rr1---sn.googlevideo.com/videoplayback?id=$id'),
      duration: const Duration(seconds: 200),
      bitrateKbps: 128,
      format: 'm4a',
      sourceVideoId: id,
    );

Track _track(String id) => Track(id: id, title: 'Song $id', artist: 'Artist');

void main() {
  group('chunkedDownload', () {
    test('reassembles a file from consecutive ranges', () async {
      final server = RangeServer(_bytes(2500));
      final progress = <int>[];

      final out = await _collect(chunkedDownload(
        server.client,
        Uri.parse('https://x.example/a'),
        chunkSize: 1000,
        onProgress: (r, _) => progress.add(r),
      ));

      expect(out, _bytes(2500));
      expect(server.requests, 3);
      expect(progress.last, 2500);
    });

    test('exact multiple of the chunk size stops without an extra request', () async {
      final server = RangeServer(_bytes(2000));
      await _collect(chunkedDownload(server.client, Uri.parse('https://x.example/a'), chunkSize: 1000));
      expect(server.requests, 2);
    });

    test('server that ignores Range is read once', () async {
      final server = RangeServer(_bytes(1500), ignoreRange: true);
      final out = await _collect(chunkedDownload(server.client, Uri.parse('https://x.example/a'), chunkSize: 1000));
      expect(out, _bytes(1500));
      expect(server.requests, 1);
    });

    test('errors surface as ClientException', () async {
      final client = MockClient((_) async => http.Response('nope', 403));
      expect(
        _collect(chunkedDownload(client, Uri.parse('https://x.example/a'))),
        throwsA(isA<http.ClientException>()),
      );
    });
  });

  group('PlaybackCache', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('playback_cache_test'));
    tearDown(() async => dir.delete(recursive: true));

    PlaybackCache cacheWith(RangeServer server, {int maxBytes = 1 << 30}) => PlaybackCache(
          store: IoLocalTrackStore(baseDirectory: () async => dir),
          httpClient: server.client,
          maxBytes: maxBytes,
        );

    test('downloads once, then serves the local file', () async {
      final server = RangeServer(_bytes(3000));
      final cache = cacheWith(server);

      final first = await cache.fileFor(_track('a'), _stream('a'));
      final requestsAfterFirst = server.requests;
      final second = await cache.fileFor(_track('a'), _stream('a'));

      expect(first.scheme, 'file');
      expect(await File.fromUri(first).readAsBytes(), _bytes(3000));
      expect(second, first);
      expect(server.requests, requestsAfterFirst);
    });

    test('concurrent requests share one download', () async {
      final server = RangeServer(_bytes(3000));
      final cache = cacheWith(server);

      await Future.wait([
        cache.fileFor(_track('a'), _stream('a')),
        cache.fileFor(_track('a'), _stream('a')),
      ]);

      expect(server.requests, 1); // 3000 bytes fits one 1 MiB chunk
    });

    test('evicts oldest entries beyond the size limit, keeping the newest', () async {
      final server = RangeServer(_bytes(1000));
      final cache = cacheWith(server, maxBytes: 2500);

      for (final id in ['a', 'b', 'c']) {
        await cache.fileFor(_track(id), _stream(id));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50)); // eviction runs async
      await cache.fileFor(_track('d'), _stream('d'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await cache.cachedFileFor(_track('a')), isNull);
      expect(await cache.cachedFileFor(_track('d')), isNotNull);
    });

    test('forget drops the cached copy', () async {
      final cache = cacheWith(RangeServer(_bytes(100)));
      await cache.fileFor(_track('a'), _stream('a'));
      await cache.forget(_track('a'));
      expect(await cache.cachedFileFor(_track('a')), isNull);
    });

    test('only remote streams are cached', () {
      expect(PlaybackCache.shouldCache(_stream('a')), isTrue);
      final local = ResolvedAudioStream(
        streamUri: Uri.file('/x/a.m4a'),
        duration: Duration.zero,
        bitrateKbps: 0,
        format: 'm4a',
        sourceVideoId: 'a',
      );
      expect(PlaybackCache.shouldCache(local), isFalse);
    });
  });
}
