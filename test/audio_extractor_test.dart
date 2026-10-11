import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/core/errors/exceptions.dart';
import 'package:symphony/features/audio_player/data/services/extraction/audio_extractor.dart';

class _Stub implements AudioExtractor {
  _Stub(this.name, {this.available = true, this.fails = false});

  @override
  final String name;
  final bool available;
  final bool fails;
  int calls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<ExtractedAudio> extract(String videoId) async {
    calls++;
    if (fails) throw AudioStreamResolutionException('$name failed');
    return ExtractedAudio(url: Uri.parse('https://$name.example/$videoId'), container: 'm4a');
  }

  @override
  Future<ExtractedAudio> searchSong(String query) async {
    calls++;
    if (fails) throw AudioStreamResolutionException('$name failed');
    return ExtractedAudio(url: Uri.parse('https://$name.example/song'), container: 'm4a', videoId: 'song01aaaaa');
  }

  @override
  void dispose() {}
}

void main() {
  group('ChainedAudioExtractor', () {
    test('skips unavailable extractors and uses the first that works', () async {
      final off = _Stub('off', available: false);
      final broken = _Stub('broken', fails: true);
      final good = _Stub('good');
      final chain = ChainedAudioExtractor([off, broken, good]);

      final audio = await chain.extract('abc');

      expect(audio.url, Uri.parse('https://good.example/abc'));
      expect(off.calls, 0);
      expect(broken.calls, 1);
    });

    test('throws a resolution error naming each failure', () async {
      final chain = ChainedAudioExtractor([_Stub('a', fails: true), _Stub('b', fails: true)]);

      expect(
        () => chain.extract('abc'),
        throwsA(isA<AudioStreamResolutionException>()
            .having((e) => '${e.cause}', 'cause', allOf(contains('a:'), contains('b:')))),
      );
    });

    test('is unavailable only when every extractor is', () async {
      expect(await ChainedAudioExtractor([_Stub('x', available: false)]).isAvailable(), isFalse);
      expect(await ChainedAudioExtractor([_Stub('x', available: false), _Stub('y')]).isAvailable(), isTrue);
    });
  });
}
