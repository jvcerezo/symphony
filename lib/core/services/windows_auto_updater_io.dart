// windows_auto_updater_io.dart
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

Future<void> runWindowsAutoUpdate(
  String downloadUrl, {
  required void Function(double progress) onProgress,
  required void Function() onInstalling,
}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;

  final client = http.Client();
  Directory? tempDir;
  try {
    final uri = Uri.parse(downloadUrl);
    final request = http.Request('GET', uri);
    request.headers['User-Agent'] = 'Symphony-Windows-Updater/1.0';

    final streamedResponse = await client.send(request).timeout(const Duration(seconds: 30));
    if (streamedResponse.statusCode != 200) {
      throw Exception('Server returned HTTP ${streamedResponse.statusCode}');
    }

    final totalBytes = streamedResponse.contentLength ?? 0;
    tempDir = Directory.systemTemp.createTempSync('symphony_update_');
    final zipFile = File('${tempDir.path}\\symphony_update.zip');
    final sink = zipFile.openWrite();

    int receivedBytes = 0;
    await for (final chunk in streamedResponse.stream) {
      sink.add(chunk);
      receivedBytes += chunk.length;
      if (totalBytes > 0) {
        final pct = (receivedBytes / totalBytes).clamp(0.0, 1.0);
        onProgress(pct);
      }
    }
    await sink.flush();
    await sink.close();

    onInstalling();

    final currentExe = Platform.resolvedExecutable;
    final currentAppDir = File(currentExe).parent.path;
    final currentPid = pid;
    final extractDir = '${tempDir.path}\\extracted';
    final scriptPath = '${tempDir.path}\\apply_update.ps1';

    final psScript = buildUpdateScript(
      zipPath: zipFile.path,
      extractDir: extractDir,
      appDir: currentAppDir,
      exePath: currentExe,
      appPid: currentPid,
      logPath: '${Directory.systemTemp.path}\symphony_update.log',
    );

    await File(scriptPath).writeAsString(psScript);

    // Launch detached updater process
    await Process.start(
      'powershell',
      [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptPath,
      ],
      mode: ProcessStartMode.detached,
    );

    // Clean exit of current Flutter app to release file locks
    exit(0);
  } catch (e, st) {
    developer.log('Windows auto-update failed', error: e, stackTrace: st, name: 'WindowsAutoUpdater');
    if (tempDir != null && tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
    rethrow;
  } finally {
    client.close();
  }
}

/// PowerShell that swaps in the extracted update after Symphony exits.
/// Always relaunches the app and logs each step to [logPath].
@visibleForTesting
String buildUpdateScript({
  required String zipPath,
  required String extractDir,
  required String appDir,
  required String exePath,
  required int appPid,
  required String logPath,
}) {
  final escapedZip = zipPath.replaceAll("'", "''");
  final escapedExtract = extractDir.replaceAll("'", "''");
  final escapedAppDir = appDir.replaceAll("'", "''");
  final escapedExe = exePath.replaceAll("'", "''");
  final escapedLog = logPath.replaceAll("'", "''");
  // The zip and extracted files live together in one temp folder.
  final escapedTemp = File(zipPath).parent.path.replaceAll("'", "''");

  final psScript = '''
\$log = '$escapedLog'
function Log(\$m) { "\$(Get-Date -Format o) \$m" | Out-File -FilePath \$log -Append -Encoding utf8 }
Log 'update started'

# 1. Wait for Symphony to exit, then stop any yt-dlp it left running from
#    the app folder (a running exe would be locked and block the copy).
try { Wait-Process -Id $appPid -Timeout 15 -ErrorAction SilentlyContinue } catch {}
try {
    Get-Process -Name 'yt-dlp' -ErrorAction SilentlyContinue |
        Where-Object { \$_.Path -and \$_.Path.StartsWith('$escapedAppDir', [System.StringComparison]::OrdinalIgnoreCase) } |
        Stop-Process -Force -ErrorAction SilentlyContinue
} catch {}
Start-Sleep -Milliseconds 800

# 2. Extract and copy over the app folder.
try {
    New-Item -ItemType Directory -Force -Path '$escapedExtract' | Out-Null
    Expand-Archive -Path '$escapedZip' -DestinationPath '$escapedExtract' -Force -ErrorAction Stop
    \$source = '$escapedExtract'
    if (-not (Test-Path (Join-Path \$source 'symphony.exe'))) {
        \$subDirs = @(Get-ChildItem -Path \$source -Directory)
        if (\$subDirs.Count -eq 1) { \$source = \$subDirs[0].FullName }
    }
    Copy-Item -Path (Join-Path \$source '*') -Destination '$escapedAppDir' -Recurse -Force -ErrorAction Stop
    Log 'files replaced'
} catch {
    Log "update failed: \$_"
}

# 3. Relaunch Symphony (new version, or the old one if the copy failed).
Start-Sleep -Milliseconds 400
try { Start-Process -FilePath '$escapedExe'; Log 'relaunched' } catch { Log "relaunch failed: \$_" }

# 4. Clean up temporary update files
Start-Sleep -Seconds 3
try {
    Remove-Item -Path '$escapedTemp' -Recurse -Force -ErrorAction SilentlyContinue
} catch {}
''';
  return psScript;
}
