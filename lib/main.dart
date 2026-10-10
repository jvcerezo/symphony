import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/symphony_theme.dart';
import 'features/audio_player/data/services/symphony_audio_handler.dart';
import 'features/audio_player/presentation/controllers/audio_player_providers.dart';
import 'features/audio_player/presentation/views/symphony_player_screen.dart';
import 'features/landing/presentation/views/symphony_landing_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background AudioService singleton
  final audioHandler = await AudioService.init(
    builder: () => SymphonyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.symphony.symphony.audio',
      androidNotificationChannelName: 'Symphony Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'drawable/ic_stat_symphony',
    ),
  );

  runApp(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const SymphonyApp(),
    ),
  );
}

class SymphonyApp extends StatelessWidget {
  const SymphonyApp({super.key});

  @override
  Widget build(BuildContext context) {
    Widget initialHome;
    if (kIsWeb) {
      final uri = Uri.base;
      final isDirectPlayer = uri.fragment == 'player' ||
          uri.path.contains('/player') ||
          uri.queryParameters['view'] == 'player' ||
          uri.queryParameters['demo'] == 'true';

      initialHome = isDirectPlayer
          ? const SymphonyPlayerScreen(isWebDemoMode: true)
          : const SymphonyLandingPage();
    } else {
      initialHome = const SymphonyPlayerScreen();
    }

    return MaterialApp(
      title: 'Symphony — Minimalist Offline Music',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: SymphonyTheme.darkTheme,
      darkTheme: SymphonyTheme.darkTheme,
      home: initialHome,
    );
  }
}
