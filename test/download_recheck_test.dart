import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:symphony/features/audio_player/data/services/audio_stream_resolver_service.dart';
import 'package:symphony/features/audio_player/data/services/extraction/audio_extractor.dart';
import 'package:symphony/features/audio_player/data/services/matching/match_index.dart';
import 'package:symphony/features/audio_player/data/services/offline/local_track_store.dart';
import 'package:symphony/features/audio_player/data/services/offline/local_track_store_io.dart';
import 'package:symphony/features/audio_player/data/services/offline/offline_download_service.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';

/// Song search answers with [songId] (or throws when null).
class _Extractor implements AudioExtractor {
  _Extractor(this.songId);
  String? songId;
  int searches = 0;

  ExtractedAudio _audio(String id) => ExtractedAudio(
        url: Uri.parse('https://cdn.example/$id'),
        container: 'm4a',
        duration: const Duration(seconds: 225),
        videoId: id,
        title: 'Sincerity Is Scary',
      );

  @override
  String get name => 'fake';
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ExtractedAudio> extract(String videoId) async => _audio(videoId);
  @override
  Future<ExtractedAudio> searchSong(String query) async {
    searches++;
    final id = songId;
    if (id == null) throw const SocketException('offline');
    return _audio(id);
  }

  @override
  void dispose() {}
}

const _track = Track(
    id: 'spotify:track:sis', title: 'Sincerity Is Scary', artist: 'The 1975', expectedDuration: Duration(seconds: 225));

void main() {
  late Directory dir;
  late IoLocalTrackStore store;
  late MatchIndex index;
  // The CDN's file body is the video id, so tests can tell recordings apart.
  final cdn = MockClient((req) async => http.Response(req.url.pathSegments.last, 200));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('symphony_recheck');
    store = IoLocalTrackStore(baseDirectory: () async => dir);
    index = MemoryMatchIndex();
  });
  tearDown(() => dir.delete(recursive: true));

  Future<String> fileBody() async =>
      File.fromUri((await store.lookup(_track))!.fileUri).readAsString();

  (OfflineDownloadService, AudioStreamResolverService) setUpWith(_Extractor ex) {
    final resolver = AudioStreamResolverService(
        extractor: ex, localTracks: const UnsupportedLocalTrackStore(), matchIndex: index, isWeb: false);
    addTearDown(resolver.dispose);
    final service = OfflineDownloadService(
      resolve: resolver.resolveBestAudioStream,
      checkMatch: resolver.checkDownloadedMatch,
      store: store,
      httpClient: cdn,
    );
    return (service, resolver);
  }

  /// A download made from [videoId], with the match saved the old way.
  Future<void> downloadOf(String videoId) async {
    await index.remember('the 1975 - sincerity is scary', MatchEntry(videoId));
    await store.save(_track, Stream.value(utf8.encode(videoId)),
        format: 'm4a', duration: const Duration(seconds: 227), sourceVideoId: videoId);
  }

  test('a download of the wrong recording is replaced', () async {
    final ex = _Extractor('NF07HNKVQd0');
    final (service, resolver) = setUpWith(ex);
    await downloadOf('lyricvideo1');

    expect(await service.recheckDownloads(trackFor: (_) => _track), 1);

    final entry = (await store.lookup(_track))!;
    expect(entry.sourceVideoId, 'NF07HNKVQd0');
    expect(await fileBody(), 'NF07HNKVQd0');
    expect(await store.entries(), hasLength(1));
    expect(await resolver.isSettledMatch(_track, 'NF07HNKVQd0'), isTrue);

    // Checked once: the next launch leaves it alone.
    expect(await service.recheckDownloads(trackFor: (_) => _track), 0);
    expect(ex.searches, 1);
  });

  test('a download that was right is kept and not checked again', () async {
    final ex = _Extractor('NF07HNKVQd0');
    final (service, _) = setUpWith(ex);
    await downloadOf('NF07HNKVQd0');

    expect(await service.recheckDownloads(), 0);
    expect(await service.recheckDownloads(), 0);
    expect(await fileBody(), 'NF07HNKVQd0');
    expect(ex.searches, 1);
  });

  test('offline: the download is kept and checked again later', () async {
    final ex = _Extractor(null);
    final (service, _) = setUpWith(ex);
    await downloadOf('lyricvideo1');

    expect(await service.recheckDownloads(), 0);
    expect(await fileBody(), 'lyricvideo1');

    ex.songId = 'NF07HNKVQd0';
    expect(await service.recheckDownloads(), 1);
    expect(await fileBody(), 'NF07HNKVQd0');
  });

  test('downloads from settled matches are never searched', () async {
    final ex = _Extractor('somethingel');
    final (service, _) = setUpWith(ex);
    await store.save(_track, Stream.value(utf8.encode('NF07HNKVQd0')),
        format: 'm4a', duration: const Duration(seconds: 225), sourceVideoId: 'NF07HNKVQd0');
    await index.remember('the 1975 - sincerity is scary', const MatchEntry('NF07HNKVQd0', source: MatchSource.songSearch));

    expect(await service.recheckDownloads(), 0);
    expect(ex.searches, 0);
  });

  test('without a check (web) nothing happens', () async {
    final service = OfflineDownloadService(
      resolve: (_) async => throw UnimplementedError(),
      store: store,
      httpClient: cdn,
    );
    await downloadOf('lyricvideo1');
    expect(await service.recheckDownloads(), 0);
  });
}
