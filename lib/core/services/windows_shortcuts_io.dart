// windows_shortcuts_io.dart
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _shortcutsForKey = 'symphony_shortcuts_for';

/// Puts "Symphony" shortcuts on the Desktop and in the Start menu, once per
/// install location: if the user deletes one it stays deleted, unless
/// Symphony is moved (then the shortcuts are written for the new path).
/// Windows release builds only, so `flutter run` doesn't leave shortcuts to
/// a debug build.
Future<void> ensureWindowsShortcuts() async {
  if (defaultTargetPlatform != TargetPlatform.windows || !kReleaseMode) return;
  try {
    final exe = Platform.resolvedExecutable;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_shortcutsForKey) == exe) return;

    final result = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      buildShortcutScript(exe),
    ]);
    if (result.exitCode == 0) {
      await prefs.setString(_shortcutsForKey, exe);
      developer.log('Shortcuts created for $exe', name: 'Shortcuts');
    } else {
      developer.log('Shortcut creation failed: ${result.stderr}', name: 'Shortcuts');
    }
  } catch (e) {
    developer.log('Shortcut creation failed: $e', name: 'Shortcuts');
  }
}

/// PowerShell that writes `Symphony.lnk` pointing at [exePath] into each of
/// [folders] (default: the user's Desktop and Start menu Programs folder,
/// which follow OneDrive redirection).
@visibleForTesting
String buildShortcutScript(String exePath, {List<String>? folders}) {
  String quote(String s) => "'${s.replaceAll("'", "''")}'";
  final dirs = folders == null
      ? "@([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))"
      : '@(${folders.map(quote).join(', ')})';
  return '''
\$ErrorActionPreference = 'Stop'
\$exe = ${quote(exePath)}
\$shell = New-Object -ComObject WScript.Shell
foreach (\$dir in $dirs) {
    if (-not \$dir) { continue }
    New-Item -ItemType Directory -Force -Path \$dir | Out-Null
    \$lnk = \$shell.CreateShortcut((Join-Path \$dir 'Symphony.lnk'))
    \$lnk.TargetPath = \$exe
    \$lnk.WorkingDirectory = Split-Path -Parent \$exe
    \$lnk.IconLocation = "\$exe,0"
    \$lnk.Description = 'Symphony music player'
    \$lnk.Save()
}
''';
}
