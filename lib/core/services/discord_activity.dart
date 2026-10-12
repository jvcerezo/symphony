import 'dart:convert';
import 'dart:typed_data';
import 'package:audio_service/audio_service.dart';

/// The Symphony application on the Discord Developer Portal. Its name there
/// is what Discord shows as "Listening to Symphony". Empty turns the
/// Discord status off.
const discordClientId = '';

/// Shown when a song has no web artwork (Discord can't read local files).
const _fallbackArtwork = 'https://raw.githubusercontent.com/jvcerezo/symphony/main/assets/images/symphony_icon_512.png';
const _downloadUrl = 'https://github.com/jvcerezo/symphony/releases/latest';

/// The Discord "Listening to" activity for what's playing, or null to clear
/// it (nothing loaded, or paused, the way Spotify does it).
Map<String, Object?>? buildListeningActivity({
  required MediaItem? item,
  required bool playing,
  required Duration position,
  required DateTime now,
}) {
  if (item == null || !playing) return null;
  final start = now.subtract(position);
  final duration = item.duration;
  final art = item.artUri;
  final album = item.album ?? '';
  return {
    'type': 2, // Listening
    'status_display_type': 2, // member list reads "Listening to <song>"
    'details': _fit(item.title),
    if ((item.artist ?? '').isNotEmpty) 'state': _fit('by ${item.artist}'),
    'timestamps': {
      'start': start.millisecondsSinceEpoch,
      if (duration != null && duration > Duration.zero) 'end': start.add(duration).millisecondsSinceEpoch,
    },
    'assets': {
      'large_image': art != null && art.scheme == 'https' ? art.toString() : _fallbackArtwork,
      'large_text': _fit(album.isNotEmpty ? album : item.title),
    },
    'buttons': [
      {'label': 'Get Symphony', 'url': _downloadUrl},
    ],
  };
}

/// Discord takes 2 to 128 characters per text field.
String _fit(String s) {
  final t = s.trim();
  if (t.length < 2) return t.padRight(2);
  return t.length > 128 ? '${t.substring(0, 127)}…' : t;
}

/// Discord IPC opcodes.
abstract final class DiscordOp {
  static const handshake = 0;
  static const frame = 1;
  static const close = 2;
  static const ping = 3;
  static const pong = 4;
}

/// One IPC message: opcode and length (little-endian int32 each), then JSON.
Uint8List encodeDiscordFrame(int op, Object? payload) {
  final body = utf8.encode(jsonEncode(payload));
  final out = Uint8List(8 + body.length);
  ByteData.sublistView(out)
    ..setInt32(0, op, Endian.little)
    ..setInt32(4, body.length, Endian.little);
  out.setRange(8, out.length, body);
  return out;
}
