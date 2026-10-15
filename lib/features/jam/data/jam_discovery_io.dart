import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';

import 'jam_discovery.dart';
import 'jam_transport.dart';

const _find = 'symphony-jam-find';
const _here = 'symphony-jam-here';
const _version = 1;

/// Android drops broadcast packets to save power unless an app holds a
/// multicast lock; held while hosting (see MainActivity).
const _androidChannel = MethodChannel('com.symphony.symphony/jam');

Future<void> _androidMulticastLock(bool hold) async {
  if (!Platform.isAndroid) return;
  try {
    await _androidChannel.invokeMethod<void>(hold ? 'acquireMulticastLock' : 'releaseMulticastLock');
  } catch (e) {
    developer.log('Multicast lock unavailable: $e', name: 'Jam');
  }
}

Map<String, Object?>? _decode(Datagram d) {
  try {
    final json = jsonDecode(utf8.decode(d.data));
    return json is Map<String, Object?> && json['v'] == _version ? json : null;
  } catch (_) {
    return null;
  }
}

Future<JamBeacon?> startJamBeacon({
  required String code,
  required int port,
  required String hostName,
  required int discoveryPort,
}) async {
  final RawDatagramSocket socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort, reuseAddress: true);
  } catch (e) {
    developer.log('Jam discovery port $discoveryPort unavailable: $e', name: 'Jam');
    return null;
  }
  await _androidMulticastLock(true);
  final reply = utf8.encode(jsonEncode({'t': _here, 'v': _version, 'code': code, 'port': port, 'name': hostName}));
  socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final d = socket.receive();
    if (d == null) return;
    final m = _decode(d);
    // Only answer for our own code: nothing to learn by scanning.
    if (m == null || m['t'] != _find || m['code'] != code) return;
    socket.send(reply, d.address, d.port);
  });
  return _IoBeacon(socket);
}

class _IoBeacon implements JamBeacon {
  _IoBeacon(this._socket);
  final RawDatagramSocket _socket;

  @override
  int get port => _socket.port;

  @override
  Future<void> close() async {
    _socket.close();
    await _androidMulticastLock(false);
  }
}

/// Where to send the question: everyone on the network. 255.255.255.255
/// alone may leave by one adapter only (Windows with several), so each
/// home network's own broadcast address is tried too (assuming /24, which
/// home and phone hotspots almost always are).
Future<List<InternetAddress>> _broadcastTargets() async {
  final targets = <String>{'255.255.255.255'};
  for (final address in await localNetworkAddresses()) {
    final parts = address.split('.');
    if (parts.length == 4) targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
  }
  return [for (final t in targets) InternetAddress(t)];
}

Future<FoundJam?> findLanJam(
  String code, {
  required Duration timeout,
  required int discoveryPort,
  List<String>? targets,
}) async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  socket.broadcastEnabled = true;
  final to = targets == null ? await _broadcastTargets() : [for (final t in targets) InternetAddress(t)];
  final question = utf8.encode(jsonEncode({'t': _find, 'v': _version, 'code': code}));
  final found = Completer<FoundJam?>();

  socket.listen((event) {
    if (event != RawSocketEvent.read || found.isCompleted) return;
    final d = socket.receive();
    if (d == null) return;
    final m = _decode(d);
    final port = m?['port'];
    if (m == null || m['t'] != _here || m['code'] != code || port is! int) return;
    found.complete((host: d.address.address, port: port, hostName: m['name'] as String? ?? ''));
  });

  void ask() {
    for (final target in to) {
      try {
        socket.send(question, target, discoveryPort);
      } catch (e) {
        // A network that refuses broadcasts; the others may still work.
        developer.log('Jam discovery send to ${target.address} failed: $e', name: 'Jam');
      }
    }
  }

  ask();
  final repeat = Timer.periodic(const Duration(milliseconds: 300), (_) => ask());
  try {
    return await found.future.timeout(timeout, onTimeout: () => null);
  } finally {
    repeat.cancel();
    socket.close();
  }
}
