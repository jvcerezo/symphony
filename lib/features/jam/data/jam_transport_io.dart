import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'jam_transport.dart';

const lanJamSupported = true;

/// Keeps idle sockets open and notices a vanished peer (Wi-Fi dropped)
/// within a few intervals instead of waiting for TCP to give up.
const _pingInterval = Duration(seconds: 5);

Future<JamServer> bindLanJamServer({int port = 0, bool loopbackOnly = false}) async {
  final server = await HttpServer.bind(
    loopbackOnly ? InternetAddress.loopbackIPv4 : InternetAddress.anyIPv4,
    port,
  );
  return _IoJamServer(server);
}

Future<JamConnection> connectLanJam(String host, int port, {Duration timeout = const Duration(seconds: 5)}) async {
  final uri = Uri(scheme: 'ws', host: host, port: port, path: jamSocketPath);
  final socket = await WebSocket.connect(uri.toString()).timeout(timeout);
  socket.pingInterval = _pingInterval;
  return _IoJamConnection(socket);
}

Future<List<String>> localNetworkAddresses() async {
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    final addresses = [
      for (final i in interfaces)
        for (final a in i.addresses)
          if (!a.isLoopback && !a.isLinkLocal) a.address,
    ];
    // Home networks first: they are almost always the one guests share.
    addresses.sort((a, b) => _rank(a).compareTo(_rank(b)));
    return addresses;
  } catch (e) {
    developer.log('Could not list network addresses: $e', name: 'Jam');
    return const [];
  }
}

int _rank(String address) {
  if (address.startsWith('192.168.')) return 0;
  if (address.startsWith('10.')) return 1;
  if (address.startsWith('172.')) return 2;
  return 3;
}

class _IoJamServer implements JamServer {
  _IoJamServer(this._server) {
    _server.listen(_onRequest, onError: (Object e) => developer.log('Jam server error: $e', name: 'Jam'));
  }

  final HttpServer _server;
  final _connections = StreamController<JamConnection>.broadcast();

  Future<void> _onRequest(HttpRequest request) async {
    if (request.uri.path != jamSocketPath || !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.pingInterval = _pingInterval;
      _connections.add(_IoJamConnection(socket));
    } catch (e) {
      developer.log('Jam upgrade failed: $e', name: 'Jam');
    }
  }

  @override
  Stream<JamConnection> get connections => _connections.stream;

  @override
  int get port => _server.port;

  @override
  Future<void> close() async {
    await _server.close(force: true);
    await _connections.close();
  }
}

class _IoJamConnection implements JamConnection {
  _IoJamConnection(this._socket)
      : messages = _socket.where((m) => m is String).cast<String>().handleError(
              (Object e) => developer.log('Jam socket error: $e', name: 'Jam'),
            );

  final WebSocket _socket;

  @override
  final Stream<String> messages;

  @override
  void send(String message) {
    if (_socket.readyState != WebSocket.open) return;
    try {
      _socket.add(message);
    } on StateError {
      // The other side is closing; its messages stream ends shortly.
    }
  }

  @override
  Future<void> close() => _socket.close();
}

/// Relay sockets carry little traffic between Jam heartbeats; pings keep
/// them (and any proxy in between) awake.
const _relayPingInterval = Duration(seconds: 20);

Uri _relayUri(String relay, String path, {bool http = false}) {
  final base = Uri.parse(relay);
  final scheme = http ? (base.scheme == 'ws' ? 'http' : 'https') : base.scheme;
  return base.replace(scheme: scheme, path: '${base.path}/rooms/$path');
}

Future<bool> onlineJamExists(String code, {required String relay}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client.getUrl(_relayUri(relay, code, http: true));
    final response = await request.close().timeout(const Duration(seconds: 8));
    await response.drain<void>();
    return response.statusCode == HttpStatus.ok;
  } finally {
    client.close(force: true);
  }
}

Future<JamServer> hostOnlineJam(String code, {required String relay, void Function()? onLost}) async {
  final socket = await WebSocket.connect(_relayUri(relay, '$code/host').toString()).timeout(const Duration(seconds: 10));
  socket.pingInterval = _relayPingInterval;
  return _RelayJamServer(socket, onLost);
}

Future<JamConnection> joinOnlineJam(String code, {required String relay}) async {
  final socket = await WebSocket.connect(_relayUri(relay, '$code/guest').toString()).timeout(const Duration(seconds: 10));
  socket.pingInterval = _relayPingInterval;
  return _IoJamConnection(socket);
}

/// The host's single socket to the relay, split into one [JamConnection]
/// per guest. The relay announces guests with `{e: open|msg|close, id, d}`
/// and takes `{to, d}` or `{to, close: true}` back.
class _RelayJamServer implements JamServer {
  _RelayJamServer(this._socket, this._onLost) {
    _socket.listen(
      _onFrame,
      onDone: _onDone,
      onError: (Object e) => developer.log('Jam relay error: $e', name: 'Jam'),
      cancelOnError: false,
    );
  }

  final WebSocket _socket;
  final void Function()? _onLost;
  final _guests = <String, _RelayGuestConnection>{};
  final _connections = StreamController<JamConnection>.broadcast();
  bool _closing = false;

  void _onFrame(dynamic raw) {
    if (raw is! String) return;
    final Object? frame;
    try {
      frame = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (frame is! Map || frame['id'] is! String) return;
    final id = frame['id'] as String;
    switch (frame['e']) {
      case 'open':
        final guest = _RelayGuestConnection(this, id);
        _guests[id] = guest;
        _connections.add(guest);
      case 'msg':
        final data = frame['d'];
        if (data is String) _guests[id]?._receive(data);
      case 'close':
        _guests.remove(id)?._end();
    }
  }

  void _onDone() {
    for (final guest in _guests.values) {
      guest._end();
    }
    _guests.clear();
    if (!_closing) {
      developer.log('Lost the Jam relay (${_socket.closeCode})', name: 'Jam');
      _onLost?.call();
    }
  }

  void _send(Map<String, Object> envelope) {
    if (_socket.readyState != WebSocket.open) return;
    try {
      _socket.add(jsonEncode(envelope));
    } on StateError {
      // Closing; onDone follows.
    }
  }

  @override
  Stream<JamConnection> get connections => _connections.stream;

  /// Online Jams have no local port.
  @override
  int get port => 0;

  @override
  Future<void> close() async {
    _closing = true;
    await _socket.close();
    await _connections.close();
  }
}

class _RelayGuestConnection implements JamConnection {
  _RelayGuestConnection(this._server, this._id);

  final _RelayJamServer _server;
  final String _id;
  final _incoming = StreamController<String>();

  void _receive(String message) {
    if (!_incoming.isClosed) _incoming.add(message);
  }

  void _end() {
    if (!_incoming.isClosed) _incoming.close();
  }

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  void send(String message) {
    if (!_incoming.isClosed) _server._send({'to': _id, 'd': message});
  }

  @override
  Future<void> close() async {
    if (_incoming.isClosed) return;
    _server._send({'to': _id, 'close': true});
    _server._guests.remove(_id);
    _end();
  }
}
