import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/data/services/symphony_audio_handler.dart';
import 'package:symphony/features/audio_player/presentation/controllers/audio_player_providers.dart';
import 'package:symphony/features/jam/data/jam_links.dart';
import 'package:symphony/features/jam/domain/jam_invite.dart';
import 'package:symphony/features/jam/presentation/jam_invite_prompt.dart';
import 'package:symphony/features/jam/presentation/jam_providers.dart';
import 'package:symphony/features/landing/presentation/widgets/jam_invite_card.dart';

class _FakeJam extends JamController {
  _FakeJam(SymphonyAudioHandler handler) : super(handler: handler, displayName: () => 'Me');

  final calls = <String>[];

  @override
  Future<void> join({required String code}) async => calls.add('join $code');

  @override
  Future<void> leave() async => calls.add('leave');
}

void main() {
  group('JamInvite', () {
    test('reads the code from either kind of link', () {
      expect(JamInvite.codeFrom(Uri.parse('https://symphony.jettimothycerezo.dev/?jam=K7M2QX')), 'K7M2QX');
      expect(JamInvite.codeFrom(Uri.parse('https://symphony.jettimothycerezo.dev/?jam=k7m2qx')), 'K7M2QX');
      expect(JamInvite.codeFrom(Uri.parse('symphony://jam/4821')), '4821');
      expect(JamInvite.codeFrom(JamInvite.appLink('K7M2QX')), 'K7M2QX');
      expect(JamInvite.codeFrom(JamInvite.webLink('4821')), '4821');
    });

    test('ignores links that aren\'t Jam invites', () {
      expect(JamInvite.codeFrom(Uri.parse('https://symphony.jettimothycerezo.dev/')), isNull);
      expect(JamInvite.codeFrom(Uri.parse('https://x.dev/?jam=12')), isNull);
      // 0, O, 1, I and L are never in online codes.
      expect(JamInvite.codeFrom(Uri.parse('symphony://jam/K0M2QX')), isNull);
      expect(JamInvite.codeFrom(Uri.parse('symphony://other/K7M2QX')), isNull);
    });

    test('the message has the link, the code, and who sent it', () {
      final text = JamInvite.message('K7M2QX', online: true, hostName: 'Jet');
      expect(text, startsWith('Jet invited you to a Jam on Symphony'));
      expect(text, contains('https://symphony.jettimothycerezo.dev/?jam=K7M2QX'));
      expect(text, contains('enter K7M2QX'));
      expect(JamInvite.message('4821', online: false), contains('same Wi-Fi'));
    });
  });

  group('JamLinks', () {
    const channel = MethodChannel('test/links');
    late List<String> codes;
    late DateTime now;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      codes = [];
      now = DateTime(2026, 10, 20);
    });

    Future<void> deliver(String link) => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, channel.codec.encodeMethodCall(MethodCall('link', link)), (_) {});

    test('the start link and later links become codes; a repeat is dropped', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        return call.method == 'initialLink' ? 'symphony://jam/K7M2QX' : null;
      });
      JamLinks(channel: channel, supported: true, clock: () => now).listen(codes.add);
      await pumpEventQueue();

      await deliver('symphony://jam/K7M2QX'); // The same link again, from the activity.
      await deliver('symphony://jam/4821');
      await deliver('symphony://elsewhere');
      expect(codes, ['K7M2QX', '4821']);
    });

    test('elsewhere than Android, nothing is asked', () async {
      var asked = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
        asked = true;
        return null;
      });
      JamLinks(channel: channel, supported: false).listen(codes.add);
      await pumpEventQueue();
      expect(asked, isFalse);
    });
  });

  group('offerJamInvite', () {
    late SymphonyAudioHandler handler;
    late _FakeJam jam;

    setUp(() {
      handler = SymphonyAudioHandler();
      jam = _FakeJam(handler);
    });
    tearDown(() => handler.release());

    Future<WidgetRef> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late WidgetRef captured;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(handler),
          jamProvider.overrideWith((ref) => jam),
        ],
        child: MaterialApp(
          home: Consumer(builder: (context, ref, _) {
            captured = ref;
            return const Scaffold();
          }),
        ),
      ));
      return captured;
    }

    testWidgets('joins only after the user says yes', (tester) async {
      final ref = await pump(tester);
      final context = tester.element(find.byType(Scaffold));

      offerJamInvite(context, ref, 'K7M2QX');
      await tester.pumpAndSettle();
      expect(find.text('Join this Jam?'), findsOneWidget);
      expect(jam.calls, isEmpty);

      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      expect(jam.calls, ['join K7M2QX']);
    });

    testWidgets('"Not now" does nothing', (tester) async {
      final ref = await pump(tester);
      offerJamInvite(tester.element(find.byType(Scaffold)), ref, 'K7M2QX');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(jam.calls, isEmpty);
    });
  });

  testWidgets('the landing page invite shows the code and how to get in', (tester) async {
    var downloads = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: JamInviteCard(code: 'K7M2QX', onDownload: () => downloads++)),
    ));
    expect(find.text('You’re invited to a Jam'), findsOneWidget);
    expect(find.text('K7M2QX'), findsOneWidget);
    expect(find.textContaining('wherever they are'), findsOneWidget);

    expect(find.text('Open in Symphony'), findsOneWidget, reason: 'tests run as Android');
    await tester.tap(find.text('Get Symphony for Android'));
    expect(downloads, 1);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: JamInviteCard(code: '4821', onDownload: () {}))));
    expect(find.textContaining('same network'), findsOneWidget);
  });
}
