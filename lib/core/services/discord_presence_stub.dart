import 'package:audio_service/audio_service.dart';

/// No-op on web.
Future<void> initDiscordPresence({required AudioHandler handler, required bool enabled}) async {}

/// No-op on web.
void setDiscordPresenceEnabled(bool value) {}
