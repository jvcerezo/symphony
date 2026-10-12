import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/core/services/windows_auto_updater_io.dart';

void main() {
  test('update script swaps files, logs, and survives a missing relaunch target', () async {
    final root = await Directory.systemTemp.createTemp("sym upd 'test");
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final sep = Platform.pathSeparator;

    // Installed app: old files.
    final app = await Directory('${root.path}${sep}app').create();
    await File('${app.path}${sep}symphony.exe').writeAsString('old');
    await File('${app.path}${sep}yt-dlp.exe').writeAsString('old');

    // Downloaded release zip with new files.
    final payload = await Directory('${root.path}${sep}payload').create();
    await File('${payload.path}${sep}symphony.exe').writeAsString('new');
    await File('${payload.path}${sep}yt-dlp.exe').writeAsString('new');
    final work = await Directory('${root.path}${sep}work').create();
    final zip = '${work.path}${sep}symphony_update.zip';
    final zipped = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      "Compress-Archive -Path '${payload.path.replaceAll("'", "''")}\*' -DestinationPath '${zip.replaceAll("'", "''")}'",
    ]);
    expect(zipped.exitCode, 0, reason: '${zipped.stderr}');

    final log = '${root.path}${sep}update.log';
    final script = buildUpdateScript(
      zipPath: zip,
      extractDir: '${work.path}${sep}extracted',
      appDir: app.path,
      exePath: '${root.path}${sep}does-not-exist.exe', // no window opens in tests
      appPid: 999999, // already exited
      logPath: log,
    );
    final scriptFile = File('${root.path}${sep}apply.ps1');
    await scriptFile.writeAsString(script);

    final run = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      scriptFile.path,
    ]);

    expect(run.exitCode, 0, reason: '${run.stdout}\n${run.stderr}');
    expect(await File('${app.path}${sep}symphony.exe').readAsString(), 'new');
    expect(await File('${app.path}${sep}yt-dlp.exe').readAsString(), 'new');
    final logText = await File(log).readAsString();
    expect(logText, contains('files replaced'));
    expect(logText, contains('relaunch failed'));
  }, skip: !Platform.isWindows, timeout: const Timeout(Duration(seconds: 60)));

  test('the updater launch runs the script after this process lets go', () async {
    // Regression: PowerShell started detached with no console never ran
    // the script, so updates downloaded but were never installed.
    final root = await Directory.systemTemp.createTemp('sym launch test');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final sep = Platform.pathSeparator;
    final log = File('${root.path}${sep}probe.log');
    final script = File('${root.path}${sep}probe.ps1');
    await script.writeAsString("'ran' | Out-File -FilePath '${log.path.replaceAll("'", "''")}' -Encoding utf8\n");

    await Process.start('cmd', updaterLaunchArgs(script.path), mode: ProcessStartMode.detached);

    for (var i = 0; i < 100 && !log.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(log.existsSync(), isTrue, reason: 'update script never ran');
  }, skip: !Platform.isWindows, timeout: const Timeout(Duration(seconds: 30)));
}
