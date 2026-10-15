import 'dart:async';
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
