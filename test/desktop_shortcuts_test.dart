import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/presentation/controllers/audio_player_providers.dart';
import 'package:symphony/features/audio_player/presentation/controllers/navigation_history_provider.dart';
import 'package:symphony/features/audio_player/presentation/desktop/desktop_shortcuts.dart';
import 'package:symphony/features/audio_player/presentation/desktop/desktop_volume_provider.dart';

class _RecordingCommands implements PlayerKeyboardCommands {
  final List<String> calls = [];

  @override
  Future<void> togglePlayPause() async => calls.add('toggle');

  @override
  Future<void> skip({required bool forward}) async => calls.add(forward ? 'next' : 'previous');

  @override
  Future<void> seekBy(Duration offset) async => calls.add('seek ${offset.inSeconds}');

  @override
  void changeVolume(double delta) => calls.add('volume $delta');

  @override
  void openSearch() => calls.add('search');

  @override
  void navigateHistory({required bool forward}) => calls.add(forward ? 'forward' : 'back');
}

Future<void> _pumpHarness(
  WidgetTester tester, {
  PlayerKeyboardCommands? commands,
  List<Override> overrides = const [],
  VoidCallback? onButton,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: DesktopShortcuts(
          commands: commands,
          child: Scaffold(
            body: Column(
              children: [
                const TextField(key: Key('field')),
                ElevatedButton(
                  key: const Key('button'),
                  onPressed: onButton ?? () {},
                  child: const Text('Button'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _chord(WidgetTester tester, LogicalKeyboardKey modifier, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

bool _textFieldFocused() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  return ctx != null && ctx.findAncestorStateOfType<EditableTextState>() != null;
}

void main() {
  group('desktop shortcut bindings', () {
    testWidgets('Space toggles play/pause', (tester) async {
      final commands = _RecordingCommands();
      await _pumpHarness(tester, commands: commands);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(commands.calls, ['toggle']);
    });

    testWidgets('Ctrl+Right / Ctrl+Left skip tracks', (tester) async {
      final commands = _RecordingCommands();
      await _pumpHarness(tester, commands: commands);

      await _chord(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.arrowRight);
      await _chord(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.arrowLeft);

      expect(commands.calls, ['next', 'previous']);
    });

    testWidgets('Shift+Right / Shift+Left seek by 10 seconds', (tester) async {
      final commands = _RecordingCommands();
      await _pumpHarness(tester, commands: commands);

      await _chord(tester, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.arrowRight);
      await _chord(tester, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.arrowLeft);

      expect(commands.calls, ['seek 10', 'seek -10']);
    });

    testWidgets('Ctrl+Up / Ctrl+Down change volume', (tester) async {
      final commands = _RecordingCommands();
      await _pumpHarness(tester, commands: commands);

      await _chord(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.arrowUp);
      await _chord(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.arrowDown);

      expect(commands.calls, ['volume 0.1', 'volume -0.1']);
    });

    testWidgets('Ctrl+F and "/" open search', (tester) async {
      final commands = _RecordingCommands();
      await _pumpHarness(tester, commands: commands);

      await _chord(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyF);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
      await tester.pump();

      expect(commands.calls, ['search', 'search']);
    });

    testWidgets('Alt+Left / Alt+Right navigate history', (tester) async {
      final commands = _RecordingCommands();
      await _pumpHarness(tester, commands: commands);

      await _chord(tester, LogicalKeyboardKey.altLeft, LogicalKeyboardKey.arrowLeft);
      await _chord(tester, LogicalKeyboardKey.altLeft, LogicalKeyboardKey.arrowRight);

      expect(commands.calls, ['back', 'forward']);
    });
  });

  group('text fields and controls keep their keys', () {
    testWidgets('no shortcut fires while a text field is focused; Esc leaves it', (tester) async {
      final commands = _RecordingCommands();
      await _pumpHarness(tester, commands: commands);

      await tester.tap(find.byKey(const Key('field')));
      await tester.pump();
      expect(_textFieldFocused(), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
      await _chord(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.arrowRight);
      await _chord(tester, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.arrowLeft);
      await _chord(tester, LogicalKeyboardKey.altLeft, LogicalKeyboardKey.arrowLeft);
      expect(commands.calls, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(_textFieldFocused(), isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(commands.calls, ['toggle']);
    });

    testWidgets('shortcuts recover when the focused text field is removed', (tester) async {
      final commands = _RecordingCommands();
      final showField = ValueNotifier<bool>(true);
      addTearDown(showField.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DesktopShortcuts(
              commands: commands,
              child: Scaffold(
                body: ValueListenableBuilder<bool>(
                  valueListenable: showField,
                  builder: (_, show, __) => show ? const TextField(key: Key('field')) : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('field')));
      await tester.pump();
      expect(_textFieldFocused(), isTrue);

      showField.value = false; // e.g. switching away from the Search tab
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(commands.calls, ['toggle']);
    });

    testWidgets('Space activates a keyboard-focused button instead of play/pause', (tester) async {
      final commands = _RecordingCommands();
      var pressed = 0;
      await _pumpHarness(tester, commands: commands, onButton: () => pressed++);

      Focus.of(tester.element(find.text('Button'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(pressed, 1);
      expect(commands.calls, isEmpty);
    });
  });

  group('help overlay and dialogs', () {
    testWidgets('"?" opens the shortcuts overlay and Esc closes it', (tester) async {
      await _pumpHarness(tester, commands: _RecordingCommands());

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(find.byType(ShortcutsHelpDialog), findsOneWidget);
      expect(find.text('Keyboard shortcuts'), findsOneWidget);
      expect(find.text('Play / pause'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ShortcutsHelpDialog), findsNothing);
    });

    testWidgets('shortcuts are inactive while a dialog is open', (tester) async {
      final commands = _RecordingCommands();
      await _pumpHarness(tester, commands: commands);

      showDialog<void>(
        context: tester.element(find.byType(Scaffold)),
        builder: (_) => const AlertDialog(content: Text('Dialog')),
      );
      await tester.pumpAndSettle();

      await _chord(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.arrowRight);
      expect(commands.calls, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Dialog'), findsNothing);
    });
  });

  group('default commands', () {
    testWidgets('Alt+Left / Alt+Right drive navigation history', (tester) async {
      await _pumpHarness(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold)));

      container.read(navigationHistoryProvider.notifier).record('home', null);
      container.read(activeNavTabProvider.notifier).state = 'library';
      container.read(navigationHistoryProvider.notifier).record('library', null);
      await tester.pump();

      await _chord(tester, LogicalKeyboardKey.altLeft, LogicalKeyboardKey.arrowLeft);
      expect(container.read(activeNavTabProvider), 'home');

      await _chord(tester, LogicalKeyboardKey.altLeft, LogicalKeyboardKey.arrowRight);
      expect(container.read(activeNavTabProvider), 'library');
    });

    testWidgets('Ctrl+F switches to the Search tab', (tester) async {
      await _pumpHarness(tester);
      final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold)));

      await _chord(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.keyF);
      await tester.pump();

      expect(container.read(activeNavTabProvider), 'search');
    });

    testWidgets('Ctrl+Up / Ctrl+Down step the shared volume', (tester) async {
      final applied = <double>[];
      await _pumpHarness(
        tester,
        overrides: [
          volumeProvider.overrideWith((ref) => VolumeNotifier((v) async => applied.add(v))),
        ],
      );
      final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold)));

      await _chord(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.arrowDown);
      await _chord(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.arrowDown);
      expect(container.read(volumeProvider).level, 0.8);

      await _chord(tester, LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.arrowUp);
      expect(container.read(volumeProvider).level, 0.9);
      expect(applied, [0.9, 0.8, 0.9]);
    });
  });

  group('VolumeNotifier', () {
    test('clamps, rounds and unmutes on step', () {
      final applied = <double>[];
      final notifier = VolumeNotifier((v) async => applied.add(v));

      notifier.step(0.1);
      expect(notifier.state.level, 1.0);

      notifier.toggleMute();
      expect(notifier.state.effective, 0.0);
      expect(notifier.state.level, 1.0);

      notifier.step(0.1);
      expect(notifier.state.muted, isFalse);
      expect(notifier.state.level, 0.1);

      notifier.step(-0.5);
      expect(notifier.state.level, 0.0);
      expect(applied, [1.0, 0.0, 0.1, 0.0]);
    });
  });
}
