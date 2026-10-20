import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/data/services/symphony_audio_handler.dart';
import 'package:symphony/features/audio_player/presentation/controllers/audio_player_providers.dart';
import 'package:symphony/features/audio_player/presentation/controllers/now_playing_panel_provider.dart';
import 'package:symphony/features/audio_player/presentation/desktop/desktop_shell.dart';
import 'package:symphony/features/jam/domain/jam_state.dart';
import 'package:symphony/features/jam/presentation/jam_panel.dart';
import 'package:symphony/features/jam/presentation/jam_providers.dart';
import 'package:symphony/main.dart';

/// Records what the panel asks for; tests set the state directly.
class _FakeJam extends JamController {
  _FakeJam(SymphonyAudioHandler handler) : super(handler: handler, displayName: () => 'Me');

  final calls = <String>[];

  void show(JamSession session) => state = session;

  @override
  Future<void> host({bool online = false}) async => calls.add(online ? 'host online' : 'host');

  @override
  Future<void> join({required String code}) async => calls.add('join $code');

  @override
  Future<void> leave() async => calls.add('leave');

  @override
  void setGuestsControlPlayback(bool allowed) => calls.add('control $allowed');
}

const _members = [
  JamMember(id: 'host', name: 'Jet', isHost: true),
  JamMember(id: 'g1', name: 'Ana'),
];

void main() {
  late SymphonyAudioHandler handler;
  late _FakeJam jam;

  setUp(() {
    handler = SymphonyAudioHandler();
    jam = _FakeJam(handler);
  });
  tearDown(() => handler.release());

  Future<ProviderContainer> pump(WidgetTester tester, Widget home, {Size size = const Size(1400, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      startupSplashProvider.overrideWithValue(false),
      audioHandlerProvider.overrideWithValue(handler),
      jamProvider.overrideWith((ref) => jam),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(home: home)));
    await tester.pump();
    return container;
  }

  testWidgets('desktop: the side panel has a Jam tab with start and join', (tester) async {
    final container = await pump(tester, const DesktopShell(content: SizedBox.expand()));
    container.read(nowPlayingPanelProvider.notifier).state = NowPlayingPanel.queue;
    await tester.pump();

    await tester.tap(find.text('Jam'));
    await tester.pump();
    expect(container.read(nowPlayingPanelProvider), NowPlayingPanel.jam);

    await tester.tap(find.text('Start a Jam'));
    expect(jam.calls, ['host']);
  });

  testWidgets('joining takes a 4-digit Wi-Fi code or a 6-character online one', (tester) async {
    await pump(tester, const Scaffold(body: JamPanel()));
    expect(find.widgetWithText(TextField, 'Host address'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Jam code'), '12');
    await tester.tap(find.text('Join'));
    await tester.pump();
    expect(find.text('Jam codes are 4 digits (same Wi-Fi) or 6 letters and numbers (online)'), findsOneWidget);
    expect(jam.calls, isEmpty);

    await tester.enterText(find.widgetWithText(TextField, 'Jam code'), '0420');
    await tester.tap(find.text('Join'));
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextField, 'Jam code'), 'k7p2qx');
    await tester.tap(find.text('Join'));
    await tester.pump();
    expect(jam.calls, ['join 0420', 'join K7P2QX']);
  });

  testWidgets('a Jam can be started online for friends anywhere', (tester) async {
    await pump(tester, const Scaffold(body: JamPanel()));
    await tester.tap(find.text('Start an online Jam'));
    expect(jam.calls, ['host online']);
  });

  testWidgets('an online Jam shows its code and what the relay sees', (tester) async {
    jam.show(const JamHosting(code: 'K7P2QX', members: _members, online: true));
    await pump(tester, const Scaffold(body: JamPanel()));
    expect(find.text('K7P2QX'), findsOneWidget);
    expect(find.textContaining('Friends anywhere join with this code'), findsOneWidget);
    expect(find.textContaining('never audio'), findsOneWidget);
    expect(find.textContaining('firewall'), findsNothing);
  });

  testWidgets('says why the last Jam ended', (tester) async {
    jam.show(const JamIdle(endReason: 'host_ended'));
    await pump(tester, const Scaffold(body: JamPanel()));
    expect(find.text('The host ended the Jam.'), findsOneWidget);
  });

  testWidgets('hosting shows just the code and the guests', (tester) async {
    jam.show(const JamHosting(code: '0420', members: _members));
    await pump(tester, const Scaffold(body: JamPanel()));

    expect(find.text('0420'), findsOneWidget);
    expect(find.textContaining('192.168'), findsNothing);
    expect(find.textContaining("can't find this Jam"), findsNothing);
    expect(find.text('IN THIS JAM (2)'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);

    await tester.tap(find.text('Guests can control playback'));
    await tester.ensureVisible(find.text('End Jam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('End Jam'));
    expect(jam.calls, ['control false', 'leave']);
  });

  testWidgets('a guest sees who hosts and whether they can control playback', (tester) async {
    jam.show(const JamJoined(
      hostName: 'Jet',
      members: _members,
      permissions: JamPermissions(guestsControlPlayback: false),
    ));
    await pump(tester, const Scaffold(body: JamPanel()));

    expect(find.text('Jamming with Jet'), findsOneWidget);
    expect(find.text('Only Jet controls playback. You can still add songs to the queue.'), findsOneWidget);
    await tester.tap(find.text('Leave Jam'));
    expect(jam.calls, ['leave']);
  });

  testWidgets('phone: the Jam button opens a sheet and lights up in a Jam', (tester) async {
    await pump(tester, const Scaffold(body: Center(child: JamButton(compact: true))), size: const Size(400, 860));

    await tester.tap(find.byTooltip('Jam'));
    await tester.pumpAndSettle();
    expect(find.text('Start a Jam'), findsOneWidget);

    jam.show(const JamJoined(hostName: 'Jet', members: _members, permissions: JamPermissions()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('In a Jam'), findsOneWidget);
    expect(find.text('Jamming with Jet'), findsOneWidget);
  });

  // A layout overflow fails this on its own. (Phone widths aren't checked
  // here: other Home rows already overflow in the test font.)
  testWidgets('desktop Home header fits the Jam button at the 850px breakpoint', (tester) async {
    await pump(tester, const SymphonyApp(), size: const Size(850, 700));
    expect(find.byType(JamButton), findsOneWidget);
  });
}
