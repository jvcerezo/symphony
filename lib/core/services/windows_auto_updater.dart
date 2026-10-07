// windows_auto_updater.dart
import 'windows_auto_updater_stub.dart'
    if (dart.library.io) 'windows_auto_updater_io.dart';

Future<void> platformWindowsAutoUpdate(
  String downloadUrl, {
  required void Function(double progress) onProgress,
  required void Function() onInstalling,
}) =>
    runWindowsAutoUpdate(
      downloadUrl,
      onProgress: onProgress,
      onInstalling: onInstalling,
    );
