import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:symphony/core/services/legacy_data_migration_io.dart';

void main() {
  late Directory root;
  late Directory legacy;
  late Directory target;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('migration_test');
    legacy = await Directory(p.join(root.path, 'com.symphony', 'symphony')).create(recursive: true);
    target = Directory(p.join(root.path, 'Symphony', 'Symphony'));
    await File(p.join(legacy.path, 'shared_preferences.json')).writeAsString('{"old":true}');
    await Directory(p.join(legacy.path, 'offline_tracks')).create();
    await File(p.join(legacy.path, 'offline_tracks', 'index.json')).writeAsString('[]');
    await File(p.join(legacy.path, 'offline_tracks', 'song.m4a')).writeAsString('audio');
  });
  tearDown(() => root.delete(recursive: true));

  test('copies settings and downloads into an empty new folder', () async {
    await migrateLegacyAppData(appData: root, target: target);
    expect(await File(p.join(target.path, 'shared_preferences.json')).readAsString(), '{"old":true}');
    expect(await File(p.join(target.path, 'offline_tracks', 'song.m4a')).readAsString(), 'audio');
  });

  test('never overwrites existing data in the new folder', () async {
    await target.create(recursive: true);
    await File(p.join(target.path, 'shared_preferences.json')).writeAsString('{"new":true}');
    await migrateLegacyAppData(appData: root, target: target);
    expect(await File(p.join(target.path, 'shared_preferences.json')).readAsString(), '{"new":true}');
    expect(File(p.join(target.path, 'offline_tracks', 'song.m4a')).existsSync(), isFalse);
  });

  test('does nothing without a legacy folder', () async {
    await legacy.delete(recursive: true);
    await migrateLegacyAppData(appData: root, target: target);
    expect(target.existsSync(), isFalse);
  });
}
