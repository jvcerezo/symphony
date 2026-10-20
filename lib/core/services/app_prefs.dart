import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/symphony_theme.dart';

/// Startup settings read once before the first frame, so the app opens on
/// the right screen in the right color with no flash.
class AppPrefs {
  static const _onboardingDoneKey = 'symphony_onboarding_done';
  static const _accentKey = 'symphony_accent_id';
  static const _closeToTrayKey = 'symphony_close_to_tray';
  static const _discordPresenceKey = 'symphony_discord_presence';
  static const _autoDownloadKey = 'symphony_auto_download_playlists';
  static const _autoplayKey = 'symphony_autoplay';

  /// Saved by every earlier build that ran, so their users skip onboarding.
  static const _legacyMarkers = ['symphony_user_playlists', 'symphony_user_name'];

  final bool onboardingDone;
  final SymphonyAccent accent;

  /// Windows: the close button hides to the tray instead of quitting.
  final bool closeToTray;

  /// Windows: show the current song as a Discord status.
  final bool discordPresence;

  /// Save a playing playlist's songs for offline as it plays.
  final bool autoDownloadPlaylists;

  /// Keep playing similar songs when the queue runs out.
  final bool autoplay;

  const AppPrefs({
    required this.onboardingDone,
    required this.accent,
    this.closeToTray = true,
    this.discordPresence = true,
    this.autoDownloadPlaylists = true,
    this.autoplay = true,
  });

  static Future<AppPrefs> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool(_onboardingDoneKey) ?? _legacyMarkers.any(prefs.containsKey);
      final accentId = prefs.getString(_accentKey);
      final accent = SymphonyTheme.allAccents.firstWhere(
        (a) => a.id == accentId,
        orElse: () => SymphonyTheme.monochrome,
      );
      return AppPrefs(
        onboardingDone: done,
        accent: accent,
        closeToTray: prefs.getBool(_closeToTrayKey) ?? true,
        discordPresence: prefs.getBool(_discordPresenceKey) ?? true,
        autoDownloadPlaylists: prefs.getBool(_autoDownloadKey) ?? true,
        autoplay: prefs.getBool(_autoplayKey) ?? true,
      );
    } catch (e) {
      developer.log('Could not read startup settings: $e', name: 'AppPrefs');
      return const AppPrefs(onboardingDone: true, accent: SymphonyTheme.monochrome);
    }
  }

  static Future<void> setOnboardingDone() => _write((p) => p.setBool(_onboardingDoneKey, true));

  static Future<void> saveAccent(SymphonyAccent accent) => _write((p) => p.setString(_accentKey, accent.id));

  static Future<void> saveCloseToTray(bool value) => _write((p) => p.setBool(_closeToTrayKey, value));

  static Future<void> saveDiscordPresence(bool value) => _write((p) => p.setBool(_discordPresenceKey, value));

  static Future<void> saveAutoDownloadPlaylists(bool value) => _write((p) => p.setBool(_autoDownloadKey, value));

  static Future<void> saveAutoplay(bool value) => _write((p) => p.setBool(_autoplayKey, value));

  static Future<void> _write(Future<bool> Function(SharedPreferences prefs) op) async {
    try {
      await op(await SharedPreferences.getInstance());
    } catch (e) {
      developer.log('Could not save setting: $e', name: 'AppPrefs');
    }
  }
}
