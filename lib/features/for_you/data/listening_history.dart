import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/listening_log.dart';
import '../domain/play_event.dart';
import '../../../core/utils/background_json.dart';

/// Where the listening log is kept. Swapped out in tests.
abstract class ListeningLogStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class PrefsListeningLogStore implements ListeningLogStore {
  @override
  Future<String?> read(String key) async => (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }
}

/// The user's listening on this device. It never leaves the device.
///
/// Plays are saved shortly after they're recorded. The song playing now is
/// also saved as it goes ([setInProgress]), so a play isn't lost when the
/// app is closed mid-song; it's counted at the next start.
class ListeningHistory extends StateNotifier<ListeningLog> {
  ListeningHistory({ListeningLogStore? store, this.saveDelay = const Duration(seconds: 2)})
      : _store = store ?? PrefsListeningLogStore(),
        super(ListeningLog()) {
    _loaded = _load();
  }

  static const logKey = 'symphony_listening_log';
  static const inProgressKey = 'symphony_listening_now';

  final ListeningLogStore _store;
  final Duration saveDelay;
  late final Future<void> _loaded;
  bool _isLoaded = false;
  Timer? _saveTimer;

  /// Completes once the saved log is read.
  Future<void> get loaded => _loaded;

  Future<void> _load() async {
    try {
      final raw = await _store.read(logKey);
      final saved =
          raw == null ? ListeningLog() : ListeningLog.fromJson(await decodeJsonInBackground(raw) as Map<String, dynamic>);
      // Plays recorded before the saved log was read go on top.
      for (final e in state.recent) {
        saved.add(e);
      }
      final pending = await _store.read(inProgressKey);
      if (pending != null) {
        final e = PlayEvent.fromJson(jsonDecode(pending) as Map<String, dynamic>);
        if (e != null) saved.add(e);
        await _store.write(inProgressKey, null);
      }
      if (!mounted) return;
      state = saved;
      if (pending != null) _scheduleSave();
    } catch (e) {
      developer.log('Could not read listening history: $e', name: 'ForYou');
    } finally {
      _isLoaded = true;
    }
  }

  void record(PlayEvent event) {
    final log = state..add(event);
    // A new instance so listeners see the change.
    state = ListeningLog(recent: log.recent, months: log.months);
    _scheduleSave();
    unawaited(_store.write(inProgressKey, null).catchError((_) {}));
  }

  /// The song playing now, as it stands; dropped by [record].
  Future<void> setInProgress(PlayEvent? event) async {
    try {
      await _store.write(inProgressKey, event == null ? null : jsonEncode(event.toJson()));
    } catch (_) {}
  }

  /// Forgets everything listened to.
  Future<void> clear() async {
    state = ListeningLog();
    _saveTimer?.cancel();
    await _store.write(logKey, null);
    await _store.write(inProgressKey, null);
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, () => unawaited(flush()));
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    await _loaded;
    try {
      await _store.write(logKey, jsonEncode(state.toJson()));
    } catch (e) {
      developer.log('Could not save listening history: $e', name: 'ForYou');
    }
  }

  @override
  void dispose() {
    // Save what's waiting, unless the saved log was never read (it would
    // be overwritten with less).
    if ((_saveTimer?.isActive ?? false) && _isLoaded) {
      final json = jsonEncode(state.toJson());
      unawaited(_store.write(logKey, json).catchError((_) {}));
    }
    _saveTimer?.cancel();
    super.dispose();
  }
}
