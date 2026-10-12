import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/symphony_theme.dart';

/// Startup settings read once before the first frame, so the app opens on
/// the right screen in the right color with no flash.
class AppPrefs {
  static const _onboardingDoneKey = 'symphony_onboarding_done';
  static const _accentKey = 'symphony_accent_id';

  /// Saved by every earlier build that ran, so their users skip onboarding.
  static const _legacyMarkers = ['symphony_user_playlists', 'symphony_user_name'];

  final bool onboardingDone;
  final SymphonyAccent accent;

  const AppPrefs({required this.onboardingDone, required this.accent});

  static Future<AppPrefs> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool(_onboardingDoneKey) ?? _legacyMarkers.any(prefs.containsKey);
      final accentId = prefs.getString(_accentKey);
      final accent = SymphonyTheme.allAccents.firstWhere(
        (a) => a.id == accentId,
        orElse: () => SymphonyTheme.monochrome,
      );
      return AppPrefs(onboardingDone: done, accent: accent);
    } catch (e) {
      developer.log('Could not read startup settings: $e', name: 'AppPrefs');
      return const AppPrefs(onboardingDone: true, accent: SymphonyTheme.monochrome);
    }
  }

  static Future<void> setOnboardingDone() => _write((p) => p.setBool(_onboardingDoneKey, true));

  static Future<void> saveAccent(SymphonyAccent accent) => _write((p) => p.setString(_accentKey, accent.id));

  static Future<void> _write(Future<bool> Function(SharedPreferences prefs) op) async {
    try {
      await op(await SharedPreferences.getInstance());
    } catch (e) {
      developer.log('Could not save setting: $e', name: 'AppPrefs');
    }
  }
}
