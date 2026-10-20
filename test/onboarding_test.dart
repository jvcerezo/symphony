import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:symphony/core/services/app_prefs.dart';
import 'package:symphony/core/theme/symphony_theme.dart';
import 'package:symphony/features/audio_player/data/services/symphony_audio_handler.dart';
import 'package:symphony/features/audio_player/presentation/controllers/audio_player_providers.dart';
import 'package:symphony/features/audio_player/presentation/views/symphony_player_screen.dart';
import 'package:symphony/features/onboarding/presentation/onboarding_screen.dart';
import 'package:symphony/main.dart';

/// The brand logo animates forever, so pumpAndSettle would never return.
/// Desktop size: the test font's block glyphs overflow the phone header.
void _desktopView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('AppPrefs', () {
    test('a fresh install has not onboarded', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await AppPrefs.load();
      expect(prefs.onboardingDone, isFalse);
      expect(prefs.accent.id, SymphonyTheme.monochrome.id);
    });

    test('users of earlier builds skip onboarding', () async {
      SharedPreferences.setMockInitialValues({'symphony_user_playlists': '[]'});
      expect((await AppPrefs.load()).onboardingDone, isTrue);
    });

    test('remembers the accent', () async {
      SharedPreferences.setMockInitialValues({});
      await AppPrefs.saveAccent(SymphonyTheme.violet);
      expect((await AppPrefs.load()).accent.id, 'violet');
    });
  });

  testWidgets('walkthrough saves name and color, then opens the player', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final handler = SymphonyAudioHandler();
    addTearDown(() {
      handler.release();
    });
    final container = ProviderContainer(overrides: [
      startupSplashProvider.overrideWithValue(false),
      audioHandlerProvider.overrideWithValue(handler),
      onboardingCompleteProvider.overrideWith((ref) => false),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const SymphonyApp()));
    await _settle(tester);
    expect(find.text('Welcome to Symphony'), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'Sam');
    await tester.tap(find.text('Continue'));
    await _settle(tester);

    await tester.tap(find.text('Violet'));
    await tester.pump();
    expect(container.read(accentThemeProvider).id, 'violet');
    await tester.tap(find.text('Continue'));
    await _settle(tester);

    expect(find.text('Add your first music'), findsOneWidget);
    await tester.tap(find.text('Look around first'));
    await _settle(tester);

    expect(find.byType(SymphonyPlayerScreen), findsOneWidget);
    expect(find.textContaining('Sam'), findsWidgets);
    expect(find.text('Your library is empty'), findsOneWidget);

    final prefs = await AppPrefs.load();
    expect(prefs.onboardingDone, isTrue);
    expect(prefs.accent.id, 'violet');
  });

  testWidgets('skip goes straight to the player', (tester) async {
    SharedPreferences.setMockInitialValues({});
    _desktopView(tester);
    final handler = SymphonyAudioHandler();
    addTearDown(() {
      handler.release();
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        startupSplashProvider.overrideWithValue(false),
        audioHandlerProvider.overrideWithValue(handler),
        onboardingCompleteProvider.overrideWith((ref) => false),
      ],
      child: const SymphonyApp(),
    ));
    await _settle(tester);
    await tester.tap(find.text('Skip'));
    await _settle(tester);
    expect(find.byType(SymphonyPlayerScreen), findsOneWidget);
  });
}
