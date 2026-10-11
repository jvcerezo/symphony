import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'match_index.dart';

MatchIndex createPlatformMatchIndex() => FileMatchIndex();

/// `<app support>/match_index.json`: `{ "artist - title": "videoId", ... }`.
/// Writes are debounced; a corrupt or missing file just starts empty.
class FileMatchIndex implements MatchIndex {
  FileMatchIndex({Future<File> Function()? file, this.maxEntries = 5000})
      : _file = file ?? _defaultFile;

  final Future<File> Function() _file;
  final int maxEntries;
  Map<String, String>? _map;
  Future<Map<String, String>>? _loading;
  Timer? _saveTimer;

  static Future<File> _defaultFile() async =>
      File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}match_index.json');

  Future<Map<String, String>> _load() => _loading ??= () async {
        try {
          final f = await _file();
          if (await f.exists()) {
            final decoded = jsonDecode(await f.readAsString());
            if (decoded is Map) {
              _map = decoded.map((k, v) => MapEntry('$k', '$v'));
              return _map!;
            }
          }
        } catch (e) {
          developer.log('Match index unreadable, starting empty: $e', name: 'MatchIndex');
        }
        return _map = <String, String>{};
      }();

  @override
  Future<String?> lookup(String key) async => (await _load())[key];

  @override
  Future<void> remember(String key, String videoId) async {
    final map = await _load();
    if (map[key] == videoId) return;
    map.remove(key); // re-insert so the newest entries survive trimming
    map[key] = videoId;
    while (map.length > maxEntries) {
      map.remove(map.keys.first);
    }
    _scheduleSave();
  }

  @override
  Future<void> forget(String key) async {
    if ((await _load()).remove(key) != null) _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), flush);
  }

  /// Writes pending changes now (also called by the debounce timer).
  Future<void> flush() async {
    _saveTimer?.cancel();
    final map = _map;
    if (map == null) return;
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(map));
      await tmp.rename(f.path);
    } catch (e) {
      developer.log('Match index save failed: $e', name: 'MatchIndex');
    }
  }
}
