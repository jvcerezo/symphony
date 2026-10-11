import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Windows only. Builds up to v1.0.27 were stamped CompanyName "com.symphony"
/// / ProductName "symphony", so their data lives in
/// `%APPDATA%\com.symphony\symphony`. Newer builds use `Symphony\Symphony`.
/// On first launch of a newer build, copy playlists/settings and downloads
/// across so nothing appears lost. Never throws; never overwrites.
Future<void> migrateLegacyAppData({Directory? appData, Directory? target}) async {
  if (kIsWeb || (appData == null && !Platform.isWindows)) return;
  try {
    final roaming = appData ?? Directory(Platform.environment['APPDATA'] ?? '');
    final legacy = Directory(p.join(roaming.path, 'com.symphony', 'symphony'));
    final current = target ?? await getApplicationSupportDirectory();
    if (!await legacy.exists() || p.equals(legacy.path, current.path)) return;

    final prefsName = 'shared_preferences.json';
    final newPrefs = File(p.join(current.path, prefsName));
    if (await newPrefs.exists()) return; // already set up (or already migrated)

    await current.create(recursive: true);
    final oldPrefs = File(p.join(legacy.path, prefsName));
    if (await oldPrefs.exists()) await oldPrefs.copy(newPrefs.path);
    await _copyDirIfMissing(Directory(p.join(legacy.path, 'offline_tracks')), Directory(p.join(current.path, 'offline_tracks')));
    developer.log('Migrated app data from ${legacy.path}', name: 'Migration');
  } catch (e) {
    developer.log('Legacy data migration skipped: $e', name: 'Migration');
  }
}

Future<void> _copyDirIfMissing(Directory from, Directory to) async {
  if (!await from.exists()) return;
  await for (final entity in from.list(recursive: true, followLinks: false)) {
    final rel = p.relative(entity.path, from: from.path);
    final dest = p.join(to.path, rel);
    if (entity is Directory) {
      await Directory(dest).create(recursive: true);
    } else if (entity is File && !await File(dest).exists()) {
      await Directory(p.dirname(dest)).create(recursive: true);
      await entity.copy(dest);
    }
  }
}
