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

    final escapedZip = zipFile.path.replaceAll("'", "''");
    final escapedExtract = extractDir.replaceAll("'", "''");
    final escapedAppDir = currentAppDir.replaceAll("'", "''");
    final escapedExe = currentExe.replaceAll("'", "''");
    final escapedTemp = tempDir.path.replaceAll("'", "''");

    // Resilient hot-swap script
    final psScript = '''
Start-Sleep -Milliseconds 600

# 1. Wait for running Symphony process to completely exit
try {
    Wait-Process -Id $currentPid -Timeout 15 -ErrorAction SilentlyContinue
} catch {}
Start-Sleep -Milliseconds 600

# 2. Extract downloaded release zip
try {
    New-Item -ItemType Directory -Force -Path '$escapedExtract' | Out-Null
    Expand-Archive -Path '$escapedZip' -DestinationPath '$escapedExtract' -Force
} catch {
    exit 1
}

# 3. Locate release payload and copy over app directory
try {
    if (Test-Path '$escapedExtract\\symphony.exe') {
        Copy-Item -Path '$escapedExtract\\*' -Destination '$escapedAppDir' -Recurse -Force
    } else {
        \$subDirs = Get-ChildItem -Path '$escapedExtract' -Directory
        if (\$subDirs.Count -eq 1) {
            Copy-Item -Path "\$(\$subDirs[0].FullName)\\*" -Destination '$escapedAppDir' -Recurse -Force
        } else {
            Copy-Item -Path '$escapedExtract\\*' -Destination '$escapedAppDir' -Recurse -Force
        }
    }
} catch {
    exit 2
}

# 4. Relaunch fresh Symphony version
Start-Sleep -Milliseconds 400
try {
    Start-Process -FilePath '$escapedExe'
} catch {}

# 5. Clean up temporary update files
Start-Sleep -Seconds 3
try {
    Remove-Item -Path '$escapedTemp' -Recurse -Force -ErrorAction SilentlyContinue
} catch {}
''';

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
