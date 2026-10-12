// windows_tray_stub.dart
import 'package:audio_service/audio_service.dart';

/// No-op on web.
Future<void> initWindowsTray({required AudioHandler handler, required bool closeToTray}) async {}

/// No-op on web.
void setCloseToTray(bool value) {}
