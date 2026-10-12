import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/core/services/windows_shortcuts_io.dart';

void main() {
  test('writes Symphony shortcuts pointing at the app', () async {
    final root = await Directory.systemTemp.createTemp("sym 'shortcut");
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final sep = Platform.pathSeparator;
    final exe = File('${root.path}${sep}app dir${sep}symphony.exe');
    await exe.create(recursive: true);
    final desktop = '${root.path}${sep}Desktop';
    final programs = '${root.path}${sep}Programs';

    final run = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      buildShortcutScript(exe.path, folders: [desktop, programs]),
    ]);
    expect(run.exitCode, 0, reason: '${run.stderr}');

    for (final dir in [desktop, programs]) {
      final lnk = '$dir${sep}Symphony.lnk';
      expect(File(lnk).existsSync(), isTrue);
      final target = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "(New-Object -ComObject WScript.Shell).CreateShortcut('${lnk.replaceAll("'", "''")}').TargetPath",
      ]);
      // Windows stores the long form of 8.3 temp paths (MYPC~1 → My PC).
      expect((target.stdout as String).trim(), endsWith('app dir${sep}symphony.exe'));
    }
  }, skip: !Platform.isWindows, timeout: const Timeout(Duration(seconds: 60)));
}
