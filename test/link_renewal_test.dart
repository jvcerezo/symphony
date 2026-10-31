import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/data/services/audio_stream_resolver_service.dart';
import 'package:symphony/features/audio_player/data/services/extraction/audio_extractor.dart';
import 'package:symphony/features/audio_player/data/services/matching/match_index.dart';
import 'package:symphony/features/audio_player/data/services/offline/local_track_store.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';

/// Links that last an hour, as YouTube's do (for about 6).
Uri _link(String id) => Uri.parse(
    'https://media.example/$id?expire=${DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000}');

/// Records each yt-dlp run: single extracts and batches.
class _BatchExtractor implements BatchAudioExtractor {
  final singles = <String>[];
  final batches = <List<String>>[];
  final broken = <String>{};

  ExtractedAudio _audio(String id) =>
      ExtractedAudio(url: _link(id), container: 'm4a', duration: const Duration(seconds: 200), videoId: id);

  @override
  String get name => 'fake batch';
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ExtractedAudio> extract(String videoId) async {
    singles.add(videoId);
    return _audio(videoId);
  }

  @override
  Future<Map<String, ExtractedAudio>> extractMany(List<String> videoIds) async {
    batches.add(videoIds);
    return {for (final id in videoIds) if (!broken.contains(id)) id: _audio(id)};
  }

  @override
  Future<ExtractedAudio> searchSong(String query) => Future.error(UnsupportedError('none'));
  @override
  void dispose() {}
}

Track _yt(String id) => Track(id: 'yt_$id', title: 'Song $id', artist: 'Artist', expectedDuration: const Duration(seconds: 200));
Track _imported(String name) =>
    Track(id: 'spotify:track:$name', title: name, artist: 'Artist', expectedDuration: const Duration(seconds: 200));

void main() {
  late _BatchExtractor ex;
  late MemoryMatchIndex index;
  late AudioStreamResolverService r;

  setUp(() {
    ex = _BatchExtractor();
    index = MemoryMatchIndex();
    r = AudioStreamResolverService(
      extractor: ex,
      localTracks: const UnsupportedLocalTrackStore(),
      matchIndex: index,
      isWeb: false,
    );
  });
  tearDown(() => r.dispose());

  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('songs ahead with expired links are renewed in one run', () async {
    // Played yesterday: the video of each is known, the link is gone.
    final songs = [_yt('aaaaaaaaaaa'), _yt('bbbbbbbbbbb'), _imported('one'), _imported('two')];
    await index.remember('artist - one', const MatchEntry('ccccccccccc', source: MatchSource.songSearch));
    await index.remember('artist - two', const MatchEntry('ddddddddddd', source: MatchSource.songSearch));

    r.prefetch(const [], linksAhead: songs);
    await settle();

    expect(ex.batches, [
      ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc', 'ddddddddddd']
    ]);
    expect(ex.singles, isEmpty);
    for (final s in songs) {
      expect(await r.hasInstantSource(s), isTrue, reason: s.title);
    }
    // Starting one now needs no yt-dlp at all.
    await r.resolveBestAudioStream(songs[2]);
    expect(ex.singles, isEmpty);
  });

  test('too few songs wait for more instead of a run of their own', () async {
    r.prefetch(const [], linksAhead: [_yt('aaaaaaaaaaa'), _yt('bbbbbbbbbbb')]);
    await settle();

    expect(ex.batches, isEmpty);
  });

  test('songs never matched, or with fresh links, are left out', () async {
    final fresh = _yt('eeeeeeeeeee');
    await r.resolveBestAudioStream(fresh);
    ex.singles.clear();

    r.prefetch(const [], linksAhead: [
      fresh,
      _imported('never played'),
      _yt('aaaaaaaaaaa'),
      _yt('bbbbbbbbbbb'),
      _yt('ccccccccccc'),
    ]);
    await settle();

    expect(ex.batches, [
      ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc']
    ]);
  });

  test('a song the run could not renew is still found on its own when played', () async {
    ex.broken.add('bbbbbbbbbbb');
    final songs = [_yt('aaaaaaaaaaa'), _yt('bbbbbbbbbbb'), _yt('ccccccccccc')];

    r.prefetch(const [], linksAhead: songs);
    await settle();

    expect(await r.hasInstantSource(songs[0]), isTrue);
    expect(await r.hasInstantSource(songs[1]), isFalse);
    await r.resolveBestAudioStream(songs[1]);
    expect(ex.singles, ['bbbbbbbbbbb']);
  });

  test('the next song is still prepared on its own', () async {
    r.prefetch([_yt('aaaaaaaaaaa')], linksAhead: [_yt('aaaaaaaaaaa')]);
    await settle();

    expect(ex.batches, isEmpty);
    expect(ex.singles, ['aaaaaaaaaaa']);
  });
}
