import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'core/config/feature_flags.dart';
import 'core/services/app_prefs.dart';
import 'core/services/discord_presence.dart';
import 'core/services/legacy_data_migration.dart';
import 'core/services/windows_shortcuts.dart';
import 'core/services/windows_tray.dart';
import 'core/theme/symphony_theme.dart';
import 'features/audio_player/data/services/extraction/desktop_ytdlp_extractor.dart';
import 'features/audio_player/data/services/extraction/ytdlp_update_scheduler.dart';
import 'features/audio_player/data/services/symphony_audio_handler.dart';
import 'features/audio_player/presentation/controllers/audio_player_providers.dart';
import 'features/audio_player/presentation/controllers/offline_provider.dart';
import 'features/audio_player/presentation/views/symphony_player_screen.dart';
import 'features/landing/presentation/views/symphony_landing_page.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';
import 'features/settings/presentation/controllers/desktop_settings_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Older Windows builds stored data under com.symphony\symphony; bring it
  // across before anything reads settings or downloads.
  await migrateLegacyAppData();

  // Windows audio goes through libmpv (media_kit). Must run before the
  // first AudioPlayer is created, i.e. before AudioService.init below.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    JustAudioMediaKit.title = 'Symphony';
    JustAudioMediaKit.ensureInitialized(linux: false, windows: true);
  }

  final startup = await AppPrefs.load();

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

  final container = ProviderContainer(
    overrides: [
      audioHandlerProvider.overrideWithValue(audioHandler),
      accentThemeProvider.overrideWith((ref) => startup.accent),
      closeToTrayProvider.overrideWith((ref) => startup.closeToTray),
      discordPresenceProvider.overrideWith((ref) => startup.discordPresence),
      autoDownloadPlaylistsProvider.overrideWith((ref) => startup.autoDownloadPlaylists),
      // The walkthrough is for the installed apps; web opens as before.
      onboardingCompleteProvider.overrideWith((ref) => kIsWeb || startup.onboardingDone),
    ],
  );
  runApp(UncontrolledProviderScope(container: container, child: const SymphonyApp()));

  // Downloads made from a wrong match get the right recording.
  scheduleDownloadRecheck(container);
  // Playlists being played are saved for offline in the background.
  startQueueAutoDownload(container);

  // Keep the bundled yt-dlp current (YouTube changes often). Background,
  // at most once a day; playback never waits on it.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    unawaited(initWindowsTray(handler: audioHandler, closeToTray: startup.closeToTray));
    unawaited(ensureWindowsShortcuts());
    unawaited(initDiscordPresence(handler: audioHandler, enabled: startup.discordPresence));
    final ytDlp = DesktopYtDlpExtractor();
    YtDlpUpdateScheduler(isAvailable: ytDlp.isAvailable, update: ytDlp.update).scheduleAfterStart();
  }
  // macOS fetches yt-dlp itself on first start, then keeps it current.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
    final ytDlp = DesktopYtDlpExtractor();
    unawaited(ytDlp.install());
    YtDlpUpdateScheduler(isAvailable: ytDlp.isAvailable, update: ytDlp.update).scheduleAfterStart();
  }
}

class SymphonyApp extends ConsumerWidget {
  const SymphonyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the chosen accent across launches, wherever it was picked.
    ref.listen(accentThemeProvider, (prev, next) {
      if (prev?.id != next.id) AppPrefs.saveAccent(next);
    });
    ref.listen(closeToTrayProvider, (prev, next) {
      setCloseToTray(next);
      AppPrefs.saveCloseToTray(next);
    });
    ref.listen(discordPresenceProvider, (prev, next) {
      setDiscordPresenceEnabled(next);
      AppPrefs.saveDiscordPresence(next);
    });
    ref.listen(autoDownloadPlaylistsProvider, (prev, next) => AppPrefs.saveAutoDownloadPlaylists(next));

    Widget initialHome;
    if (kIsWeb) {
      final uri = Uri.base;
      final isDirectPlayer = FeatureFlags.webDemoEnabled && (uri.fragment == 'player' ||
          uri.path.contains('/player') ||
          uri.queryParameters['view'] == 'player' ||
          uri.queryParameters['demo'] == 'true');

      initialHome = isDirectPlayer
          ? const SymphonyPlayerScreen(isWebDemoMode: true)
          : const SymphonyLandingPage();
    } else {
      initialHome = ref.watch(onboardingCompleteProvider)
          ? const SymphonyPlayerScreen()
          : const OnboardingScreen();
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
