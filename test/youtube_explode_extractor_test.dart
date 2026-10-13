import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/data/services/extraction/youtube_explode_extractor.dart';

void main() {
  group('firstWorking', () {
    test('skips links that fail the check and returns the first full one', () async {
      final tried = <String>[];
      final result = await firstWorking<String>(
        [() async => 'cut-off', () async => null, () async => 'full', () async => 'unused'],
        (link) async {
          tried.add(link);
          return link == 'full';
        },
      );

      expect(result, 'full');
      expect(tried, ['cut-off', 'full']);
    });

    test('null when no client gives a full link', () async {
      expect(await firstWorking<String>([() async => 'a', () async => null], (_) async => false), isNull);
    });
  });
}
