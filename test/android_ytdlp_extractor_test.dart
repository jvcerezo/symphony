import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/core/errors/exceptions.dart';
import 'package:symphony/features/audio_player/data/services/extraction/android_ytdlp_extractor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = AndroidYtDlpExtractor.channel;
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('AndroidYtDlpExtractor', () {
    test('maps a successful extract reply', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return {
          'url': 'https://rr1.googlevideo.com/videoplayback?id=abc',
          'ext': 'm4a',
          'abr': 129.476,
          'durationMs': 213040,
          'headers': {'User-Agent': 'Mozilla/5.0'},
        };
      });

      final audio = await AndroidYtDlpExtractor().extract('dQw4w9WgXcQ');

      expect(calls.single.method, 'extract');
      expect(calls.single.arguments, {'videoId': 'dQw4w9WgXcQ'});
      expect(audio.url.host, 'rr1.googlevideo.com');
      expect(audio.container, 'm4a');
      expect(audio.bitrateKbps, 129);
      expect(audio.duration, const Duration(milliseconds: 213040));
      expect(audio.headers, {'User-Agent': 'Mozilla/5.0'});
    });

    test('tolerates missing optional fields', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => {'url': 'https://example.com/a'});

      final audio = await AndroidYtDlpExtractor().extract('dQw4w9WgXcQ');

      expect(audio.container, 'm4a');
      expect(audio.bitrateKbps, isNull);
      expect(audio.duration, isNull);
      expect(audio.headers, isNull);
    });

    test('a reply without a url is a resolution failure', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => {'ext': 'm4a'});

      expect(
        AndroidYtDlpExtractor().extract('dQw4w9WgXcQ'),
        throwsA(isA<AudioStreamResolutionException>()),
      );
    });

    test('PlatformException becomes AudioStreamResolutionException', () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'extract_failed', message: 'ERROR: Sign in to confirm');
      });

      await expectLater(
        AndroidYtDlpExtractor().extract('dQw4w9WgXcQ'),
        throwsA(isA<AudioStreamResolutionException>()
            .having((e) => e.cause, 'cause', 'ERROR: Sign in to confirm')),
      );
    });

    test('MissingPluginException becomes AudioStreamResolutionException', () async {
      // No handler registered → MissingPluginException.
      await expectLater(
        AndroidYtDlpExtractor().extract('dQw4w9WgXcQ'),
        throwsA(isA<AudioStreamResolutionException>()),
      );
    });

    test('isAvailable asks the platform once and caches the answer', () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        expect(call.method, 'isAvailable');
        return true;
      });
      final extractor = AndroidYtDlpExtractor();

      expect(await extractor.isAvailable(), isTrue);
      expect(await extractor.isAvailable(), isTrue);
      expect(calls, 1);
    });

    test('isAvailable is false on PlatformException', () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'init_failed');
      });

      expect(await AndroidYtDlpExtractor().isAvailable(), isFalse);
    });

    test('isAvailable is false on MissingPluginException', () async {
      expect(await AndroidYtDlpExtractor().isAvailable(), isFalse);
    });

    test('isAvailable is false off Android without calling the platform', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return true;
      });

      expect(await AndroidYtDlpExtractor().isAvailable(), isFalse);
      expect(calls, 0);
    });

    test('update returns the new version, or null on failure', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'update');
        return '2026.08.19';
      });
      expect(await AndroidYtDlpExtractor().update(), '2026.08.19');

      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'update_failed');
      });
      expect(await AndroidYtDlpExtractor().update(), isNull);

      messenger.setMockMethodCallHandler(channel, null);
      expect(await AndroidYtDlpExtractor().update(), isNull);
    });
  });
}
