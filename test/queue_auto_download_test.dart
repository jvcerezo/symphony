import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/data/services/offline/local_track_store.dart';
import 'package:symphony/features/audio_player/data/services/offline/offline_download_service.dart';
import 'package:symphony/features/audio_player/data/services/offline/queue_auto_downloader.dart';
import 'package:symphony/features/audio_player/domain/entities/resolved_audio_stream.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';

Track _t(int i) => Track(id: 't$i', title: 'Song $i', artist: 'Artist');
final _queue = [for (var i = 0; i < 6; i++) _t(i)];

class _Harness {
  final saved = <String>[];
  final attempts = <String>[];
  final failing = <String>{};
  var online = true;
  var busy = false;
  Completer<void>? gate;

  late final downloader = QueueAutoDownloader(
    isDownloaded: (t) async => saved.contains(t.id),
    download: (t) async {
      attempts.add(t.id);
      await gate?.future;
      if (failing.contains(t.id)) throw StateError('no match');
      saved.add(t.id);
    },
    isOnline: () async => online,
    isPlayerBusy: () => busy,
    busyPoll: const Duration(milliseconds: 10),
    offlineRetry: const Duration(milliseconds: 50),
  );

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));
}

class _Store implements LocalTrackStore {
  final saved = <String, List<int>>{};

  @override
  bool get isSupported => true;
  @override
  Future<LocalTrackEntry?> lookup(Track track) async => saved.containsKey(track.id) ? _entry(track) : null;
  @override
  Future<LocalTrackEntry> save(Track track, Stream<List<int>> bytes,
      {required String format, required Duration duration, required String sourceVideoId, int? expectedBytes}) async {
    saved[track.id] = [for (final c in await bytes.toList()) ...c];
    return _entry(track);
  }

  LocalTrackEntry _entry(Track t) => LocalTrackEntry(
        trackId: t.id,
        normKey: LocalTrackStore.normKeyFor(t),
        title: t.title,
        artist: t.artist,
        fileName: '${t.id}.m4a',
        fileUri: Uri.file('/data/${t.id}.m4a'),
        bytes: saved[t.id]?.length ?? 0,
        format: 'm4a',
        duration: const Duration(seconds: 200),
        sourceVideoId: 'vid',
        downloadedAt: DateTime(2026),
      );

  @override
  Future<int> remove(Track track) async => saved.remove(track.id)?.length ?? 0;
  @override
  Future<List<LocalTrackEntry>> entries() async => [];
  @override
  Future<int> totalBytes() async => 0;
}

void main() {
  group('QueueAutoDownloader', () {
    test('saves songs from two ahead, then the rest, the next and the current song last', () async {
      final h = _Harness();
      h.downloader.queueChanged(_queue, 1);
      await h.settle();

      expect(h.attempts, ['t3', 't4', 't5', 't0', 't2', 't1']);
    });

    test('songs already on the device are not downloaded again', () async {
      final h = _Harness()..saved.addAll(['t2', 't4']);
      h.downloader.queueChanged(_queue, 0);
      await h.settle();

      expect(h.attempts, ['t3', 't5', 't1', 't0']);
    });

    test('moving through the queue does not repeat finished downloads', () async {
      final h = _Harness();
      h.downloader.queueChanged(_queue, 0);
      await h.settle();
      h.attempts.clear();

      h.downloader.queueChanged(_queue, 1);
      h.downloader.queueChanged(_queue, 2);
      await h.settle();

      expect(h.attempts, isEmpty);
    });

    test('a song listed twice is saved once', () async {
      final h = _Harness();
      h.downloader.queueChanged([_t(0), _t(1), _t(2), _t(1)], 0);
      await h.settle();

      expect(h.attempts.where((id) => id == 't1'), hasLength(1));
    });

    test('a single song is not a playlist', () async {
      final h = _Harness();
      h.downloader.queueChanged([_t(0)], 0);
      await h.settle();

      expect(h.attempts, isEmpty);
    });

    test('waits while the player loads a song', () async {
      final h = _Harness()..busy = true;
      h.downloader.queueChanged(_queue, 0);
      await h.settle();
      expect(h.attempts, isEmpty);

      h.busy = false;
      await h.settle();
      expect(h.attempts, hasLength(6));
    });

    test('pauses offline and carries on once back online', () async {
      final h = _Harness()..online = false;
      h.downloader.queueChanged(_queue, 0);
      await h.settle();
      expect(h.attempts, isEmpty);

      h.online = true;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(h.saved, hasLength(6));
    });

    test('a download cut off by the connection dropping is tried again, not counted', () async {
      final h = _Harness()..gate = Completer<void>();
      h.failing.add('t2');
      h.downloader.queueChanged(_queue, 0);
      await h.settle();
      // t2 is downloading; the connection drops and it fails.
      h.online = false;
      h.gate!.complete();
      await h.settle();
      h.failing.clear();
      h.online = true;
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(h.saved, contains('t2'));
      expect(h.downloader.pending, isEmpty);
    });

    test('a song that keeps failing is given up after two tries', () async {
      final h = _Harness()..failing.add('t3');
      h.downloader.queueChanged(_queue, 0);
      await h.settle();
      h.downloader.queueChanged(_queue, 1);
      await h.settle();
      h.downloader.queueChanged(_queue, 2);
      await h.settle();

      expect(h.attempts.where((id) => id == 't3'), hasLength(2));
      expect(h.saved, isNot(contains('t3')));
    });

    test('songs the user removed are not saved again', () async {
      final h = _Harness();
      h.downloader.removedByUser(_t(3));
      h.downloader.queueChanged(_queue, 0);
      await h.settle();

      expect(h.attempts, isNot(contains('t3')));
    });

    test('turned off, nothing is saved; turned on, it starts', () async {
      final h = _Harness();
      h.downloader.enabled = false;
      h.downloader.queueChanged(_queue, 0);
      await h.settle();
      expect(h.attempts, isEmpty);

      h.downloader.enabled = true;
      await h.settle();
      expect(h.attempts, hasLength(6));
    });

    test('turning it off stops the songs still waiting', () async {
      final h = _Harness()..gate = Completer<void>();
      h.downloader.queueChanged(_queue, 0);
      await h.settle();
      h.downloader.enabled = false;
      h.gate!.complete();
      await h.settle();

      expect(h.attempts, hasLength(1));
    });
  });

  group('OfflineDownloadService', () {
    test("reuses the player's saved copy instead of downloading again", () async {
      final store = _Store();
      var resolves = 0;
      final service = OfflineDownloadService(
        resolve: (t) async {
          resolves++;
          throw StateError('should not be needed');
        },
        playbackCopy: (t) async => ResolvedAudioStream(
          streamUri: Uri.file('/cache/${t.id}.m4a'),
          duration: const Duration(seconds: 200),
          bitrateKbps: 0,
          format: 'm4a',
          sourceVideoId: 'vid',
        ),
        readFile: (uri) => Stream.value([1, 2, 3]),
        store: store,
      );
      addTearDown(service.dispose);

      await service.download(_t(0));

      expect(resolves, 0);
      expect(store.saved['t0'], [1, 2, 3]);
    });

    test('downloads when there is no saved copy', () async {
      final store = _Store();
      var resolves = 0;
      final service = OfflineDownloadService(
        resolve: (t) async {
          resolves++;
          throw StateError('offline');
        },
        playbackCopy: (t) async => null,
        store: store,
      );
      addTearDown(service.dispose);

      await expectLater(service.download(_t(0)), throwsStateError);
      expect(resolves, 1);
    });
  });
}
