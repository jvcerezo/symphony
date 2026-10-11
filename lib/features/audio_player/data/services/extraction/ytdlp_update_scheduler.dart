import 'dart:async';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

/// Runs the yt-dlp self-update at most once per calendar day, in the
/// background. Platform-neutral: [update] is a no-op where yt-dlp isn't
/// bundled, and [isAvailable] gates the attempt.
class YtDlpUpdateScheduler {
  static const prefsKey = 'ytdlp_last_update_check';

  final Future<bool> Function() isAvailable;
  final Future<String?> Function() update;
  final Future<SharedPreferences> Function() _prefs;
  final DateTime Function() _now;

  YtDlpUpdateScheduler({
    required this.isAvailable,
    required this.update,
    Future<SharedPreferences> Function()? prefs,
    DateTime Function()? now,
  })  : _prefs = prefs ?? SharedPreferences.getInstance,
        _now = now ?? DateTime.now;

  /// Returns true when an update attempt was started (and awaited).
  Future<bool> runIfDue() async {
    try {
      if (!await isAvailable()) return false;
      final prefs = await _prefs();
      final today = _dayKey(_now());
      if (prefs.getString(prefsKey) == today) return false;
      // Record the attempt first so a failing update isn't retried on every launch.
      await prefs.setString(prefsKey, today);
      await update();
      return true;
    } catch (e) {
      developer.log('yt-dlp update check failed: $e', name: 'YtDlp');
      return false;
    }
  }

  /// Fire-and-forget after [delay], so it never competes with app start or
  /// the first song.
  void scheduleAfterStart({Duration delay = const Duration(seconds: 30)}) {
    unawaited(Future<void>.delayed(delay, runIfDue));
  }

  static String _dayKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}
