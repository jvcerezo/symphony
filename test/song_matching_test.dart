import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/data/services/audio_stream_resolver_service.dart';
import 'package:symphony/features/audio_player/data/services/extraction/audio_extractor.dart';
import 'package:symphony/features/audio_player/data/services/matching/match_index.dart';
import 'package:symphony/features/audio_player/data/services/offline/local_track_store.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';

/// Song search returns [song]; extract() records ids. No network.
class _FakeExtractor implements AudioExtractor {
  _FakeExtractor({this.song});
  final ExtractedAudio? song;
  final searched = <String>[];
  final extracted = <String>[];

  @override
  String get name => 'fake';
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ExtractedAudio> extract(String videoId) async {
    extracted.add(videoId);
    return ExtractedAudio(url: Uri.parse('https://media.example/$videoId'), container: 'm4a', duration: const Duration(seconds: 219));
  }
  @override
  Future<ExtractedAudio> searchSong(String query) async {
    searched.add(query);
    return song ?? (throw UnsupportedError('none'));
  }
  @override
  void dispose() {}
}

const _eden = Track(id: 'spotify:track:eden', title: 'sex', artist: 'EDEN', expectedDuration: Duration(seconds: 219));

AudioStreamResolverService _resolver(_FakeExtractor ex, MatchIndex index) => AudioStreamResolverService(
      extractor: ex,
      localTracks: const UnsupportedLocalTrackStore(),
      matchIndex: index,
      isWeb: false,
    );

void main() {
  group('isAcceptableSongMatch', () {
    bool ok(String title, int? dur, String target, int? exp) => AudioStreamResolverService.isAcceptableSongMatch(
          resultTitle: title, resultDurationSec: dur, targetTitle: target, expectedSec: exp);

    test('accepts the album track within a few seconds', () {
      expect(ok("I'm In Love With You", 263, "I'm In Love With You", 262), isTrue);
      expect(ok('sex', 219, 'sex', 219), isTrue);
    });

    test('rejects a version 15 s off (music-video length)', () {
      expect(ok('Sweater Weather', 255, 'Sweater Weather', 240), isFalse);
    });

    test('rejects live / acoustic / remix versions the track is not', () {
      expect(ok('I Love You So (Acoustic)', 160, 'I Love You So', 160), isFalse);
      expect(ok('Robbers (Live)', 255, 'Robbers', 255), isFalse);
      expect(ok('Robbers (Live)', 255, 'Robbers (Live)', 255), isTrue);
    });

    test('non-Latin titles rely on the length check', () {
      expect(ok('我知道你知道我爱你', 121, '我知道你知道我爱你', 121), isTrue);
      expect(ok('我知道你知道我爱你', 121, '我知道你知道我爱你', null), isFalse);
    });

    test('without a known length the title must match closely', () {
      expect(ok('Mona Lisa', 186, 'Mona Lisa', null), isTrue);
      expect(ok('Mona Lisa Smile', 186, 'Totally Different Song', null), isFalse);
    });
  });

  group('resolution order (native)', () {
    test('uses the YouTube Music song result and remembers it', () async {
      final ex = _FakeExtractor(
        song: ExtractedAudio(
          url: Uri.parse('https://media.example/dNNf9rJMt8E'),
          container: 'm4a',
          duration: const Duration(seconds: 219),
          videoId: 'dNNf9rJMt8E',
          title: 'sex',
          channel: 'EDEN',
        ),
      );
      final index = MemoryMatchIndex();
      final r = _resolver(ex, index);
      addTearDown(r.dispose);

      final resolved = await r.resolveBestAudioStream(_eden);

      expect(resolved.sourceVideoId, 'dNNf9rJMt8E');
      expect(ex.searched.single, 'EDEN sex');
      expect((await index.lookup('eden - sex'))?.videoId, 'dNNf9rJMt8E');
    });

    test('a remembered match skips searching entirely', () async {
      final ex = _FakeExtractor();
      final index = MemoryMatchIndex();
      await index.remember('eden - sex', const MatchEntry('dNNf9rJMt8E'));
      final r = _resolver(ex, index);
      addTearDown(r.dispose);

      final resolved = await r.resolveBestAudioStream(_eden);

      expect(resolved.sourceVideoId, 'dNNf9rJMt8E');
      expect(ex.extracted, ['dNNf9rJMt8E']);
      expect(ex.searched, isEmpty);
    });
  });

  group('remembered stream links', () {
    Uri link(DateTime expires) => Uri.parse(
        'https://rr1---sn.googlevideo.com/videoplayback?id=x&expire=${expires.millisecondsSinceEpoch ~/ 1000}');

    test('a fresh remembered link plays without running yt-dlp', () async {
      final ex = _FakeExtractor();
      final index = MemoryMatchIndex();
      final url = link(DateTime.now().add(const Duration(hours: 5)));
      await index.remember('eden - sex', MatchEntry('dNNf9rJMt8E', url: url, expiresAt: MatchEntry.expiryOf(url), durationMs: 219000));
      final r = _resolver(ex, index);
      addTearDown(r.dispose);

      final resolved = await r.resolveBestAudioStream(_eden);

      expect(resolved.streamUri, url);
      expect(resolved.duration, const Duration(seconds: 219));
      expect(ex.extracted, isEmpty);
      expect(ex.searched, isEmpty);
      expect(await r.hasInstantSource(_eden), isTrue);
    });

    test('an expiring link is re-extracted from the remembered video', () async {
      final ex = _FakeExtractor();
      final index = MemoryMatchIndex();
      final url = link(DateTime.now().add(const Duration(minutes: 5)));
      await index.remember('eden - sex', MatchEntry('dNNf9rJMt8E', url: url, expiresAt: MatchEntry.expiryOf(url)));
      final r = _resolver(ex, index);
      addTearDown(r.dispose);

      expect(await r.hasInstantSource(_eden), isFalse);
      await r.resolveBestAudioStream(_eden);

      expect(ex.extracted, ['dNNf9rJMt8E']);
      expect(ex.searched, isEmpty);
    });

    test('forgetTrack drops the link but keeps the video', () async {
      final ex = _FakeExtractor();
      final index = MemoryMatchIndex();
      final url = link(DateTime.now().add(const Duration(hours: 5)));
      await index.remember('eden - sex', MatchEntry('dNNf9rJMt8E', url: url, expiresAt: MatchEntry.expiryOf(url)));
      final r = _resolver(ex, index);
      addTearDown(r.dispose);

      r.forgetTrack(_eden);
      await Future<void>.delayed(Duration.zero);
      final entry = await index.lookup('eden - sex');

      expect(entry?.videoId, 'dNNf9rJMt8E');
      expect(entry?.url, isNull);
    });

    test('old files with a bare video id still load', () {
      expect(MatchEntry.fromJson('dNNf9rJMt8E')?.videoId, 'dNNf9rJMt8E');
      expect(MatchEntry.fromJson({'v': 'abc', 'e': 1}).toString(), isNotEmpty);
    });
  });

  group('prefetch', () {
    test('resolves queued tracks in the background and skips ready ones', () async {
      final ex = _FakeExtractor();
      final index = MemoryMatchIndex();
      await index.remember('eden - sex', const MatchEntry('dNNf9rJMt8E'));
      await index.remember('eden - start', const MatchEntry('startaaaaaa'));
      final r = _resolver(ex, index);
      addTearDown(r.dispose);
      const start = Track(id: 'spotify:track:start', title: 'start', artist: 'EDEN', expectedDuration: Duration(seconds: 219));

      r.prefetch([_eden, start, _eden]); // duplicate is ignored
      for (var i = 0; i < 20 && ex.extracted.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(ex.extracted, ['dNNf9rJMt8E', 'startaaaaaa']);
      expect(await r.hasInstantSource(_eden), isTrue);
    });
  });

  group('scoreVideoCandidate', () {
    int score(String title, String author, int dur, {String target = 'Sweater Weather', String artist = 'The Neighbourhood', int exp = 240}) =>
        AudioStreamResolverService.scoreVideoCandidate(
          videoTitle: title, videoAuthor: author, durationSec: dur, targetTitle: target, targetArtist: artist, expectedDurationMs: exp * 1000);

    test('an exact-length upload beats the longer official music video', () {
      expect(score('Sweater Weather', 'The Neighbourhood', 241),
          greaterThan(score('The Neighbourhood - Sweater Weather (Official Video)', 'The Neighbourhood', 253)));
    });

    test('an acoustic version loses to the album track', () {
      int s(String t, int d) => score(t, 'The Walters', d, target: 'I Love You So', artist: 'The Walters', exp: 160);
      expect(s('The Walters -- I Love You So', 161), greaterThan(s('The Walters - I Love You So Acoustic [Official Audio]', 148)));
    });
  });
}
