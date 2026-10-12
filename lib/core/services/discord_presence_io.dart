import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'discord_activity.dart';

_DiscordPresence? _presence;

/// Windows only: shows "Listening to Symphony" with the current song on the
/// user's Discord profile, through the Discord app's local pipe. Does
/// nothing when Discord isn't running, and picks it up when it starts.
Future<void> initDiscordPresence({required AudioHandler handler, required bool enabled}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
  if (discordClientId.isEmpty || _presence != null) return;
  _presence = _DiscordPresence(handler, enabled: enabled)..start();
}

/// Turns the Discord status on or off (off clears it right away).
void setDiscordPresenceEnabled(bool value) => _presence?.enabled = value;

class _DiscordPresence {
  final AudioHandler _handler;
  bool _enabled;

  _DiscordPresence(this._handler, {required bool enabled}) : _enabled = enabled;

  static const _replyTimeout = Duration(seconds: 5);
  static const _retryAfter = Duration(seconds: 30);

  RandomAccessFile? _pipe;
  Future<void> _ops = Future.value();
  Timer? _pending;
  Timer? _retry;
  int _nonce = 0;

  // What Discord shows now, so unchanged updates aren't resent (Discord
  // allows about 5 per 20 seconds).
  String? _shownKey;
  int? _shownStart;

  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    _schedule();
  }

  void start() {
    _handler.mediaItem.listen((_) => _schedule());
    _handler.playbackState.listen((_) => _schedule());
  }

  /// At most one update per 1.5 seconds; one queued call at a time.
  void _schedule() {
    if (_pending?.isActive ?? false) return;
    _pending = Timer(const Duration(milliseconds: 1500), () => _ops = _ops.then((_) => _sync()));
  }

  Future<void> _sync() async {
    final item = _handler.mediaItem.value;
    final state = _handler.playbackState.value;
    final now = DateTime.now();
    final activity = _enabled
        ? buildListeningActivity(item: item, playing: state.playing, position: state.position, now: now)
        : null;
    final key = activity == null ? null : '${item!.id}|${item.duration}';
    final start = (activity?['timestamps'] as Map?)?['start'] as int?;
    // A seek moves the start time; small drift isn't worth an update.
    if (key == _shownKey && (start == null || (start - _shownStart!).abs() < 3000)) return;
    if (activity == null && _pipe == null) {
      // Nothing to show and nothing shown: don't connect just to clear.
      _shownKey = null;
      return;
    }

    if (!await _connect()) {
      _retryLater();
      return;
    }
    try {
      final reply = await _request('SET_ACTIVITY', {'pid': pid, 'activity': activity});
      // A refused activity would be refused again; keep it as shown.
      if (reply['evt'] == 'ERROR') developer.log('Discord refused the status: ${reply['data']}', name: 'Discord');
      _shownKey = key;
      _shownStart = start;
    } catch (e) {
      developer.log('Discord connection lost: $e', name: 'Discord');
      await _disconnect();
      _retryLater();
    }
  }

  void _retryLater() {
    if (_retry?.isActive ?? false) return;
    _retry = Timer(_retryAfter, _schedule);
  }

  /// Discord listens on the first free of discord-ipc-0 to -9.
  Future<bool> _connect() async {
    if (_pipe != null) return true;
    for (var i = 0; i < 10; i++) {
      final RandomAccessFile f;
      try {
        // Dart reads \\.\ as a network path; \\?\ reaches the pipe.
        f = await File('\\\\?\\pipe\\discord-ipc-$i').open(mode: FileMode.append);
      } on FileSystemException {
        continue;
      }
      try {
        await f.writeFrom(encodeDiscordFrame(DiscordOp.handshake, {'v': 1, 'client_id': discordClientId}));
        final (op, data) = await _readFrame(f).timeout(_replyTimeout);
        if (op == DiscordOp.frame && data['evt'] == 'READY') {
          _pipe = f;
          return true;
        }
        developer.log('Discord refused the connection: $data', name: 'Discord');
      } catch (e) {
        developer.log('Discord handshake failed: $e', name: 'Discord');
      }
      await _close(f);
    }
    return false;
  }

  Future<Map<String, dynamic>> _request(String cmd, Map<String, Object?> args) async {
    final pipe = _pipe!;
    final nonce = '${++_nonce}';
    await pipe.writeFrom(encodeDiscordFrame(DiscordOp.frame, {'cmd': cmd, 'args': args, 'nonce': nonce}));
    // The pipe handle is synchronous, so replies are read only after a
    // request is sent; a read left waiting would block every write.
    while (true) {
      final (op, data) = await _readFrame(pipe).timeout(_replyTimeout);
      switch (op) {
        case DiscordOp.ping:
          await pipe.writeFrom(encodeDiscordFrame(DiscordOp.pong, data));
        case DiscordOp.close:
          throw StateError('Discord closed the connection: ${data['message']}');
        case DiscordOp.frame when data['nonce'] == nonce:
          return data;
      }
    }
  }

  Future<void> _disconnect() async {
    final pipe = _pipe;
    _pipe = null;
    // Discord clears the status when the pipe closes.
    _shownKey = null;
    if (pipe != null) await _close(pipe);
  }

  static Future<void> _close(RandomAccessFile f) async {
    try {
      await f.close();
    } catch (_) {
      // A timed-out read is still pending on it; the handle is dropped.
    }
  }

  static Future<(int, Map<String, dynamic>)> _readFrame(RandomAccessFile f) async {
    final head = ByteData.sublistView(await _readExactly(f, 8));
    final body = await _readExactly(f, head.getInt32(4, Endian.little));
    final json = jsonDecode(utf8.decode(body));
    return (head.getInt32(0, Endian.little), json is Map<String, dynamic> ? json : <String, dynamic>{});
  }

  static Future<Uint8List> _readExactly(RandomAccessFile f, int length) async {
    final out = BytesBuilder(copy: false);
    while (out.length < length) {
      final chunk = await f.read(length - out.length);
      if (chunk.isEmpty) throw const FileSystemException('Discord closed the pipe');
      out.add(chunk);
    }
    return out.takeBytes();
  }
}
