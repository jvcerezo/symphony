import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A local stand-in for the Cloudflare Jam relay (jam_relay/src/room.js),
/// speaking the same protocol, so tests can run online Jams on loopback.
class FakeJamRelay {
  FakeJamRelay._(this._server) {
    _server.listen(_onRequest);
  }

  static Future<FakeJamRelay> start() async => FakeJamRelay._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final _hosts = <String, WebSocket>{};
  final _guests = <String, Map<String, WebSocket>>{};
  var _nextId = 1;

  String get url => 'ws://127.0.0.1:${_server.port}';

  /// Whether [code]'s host has connected (the client can see the upgrade
  /// finish slightly before this side does).
  bool hasHost(String code) => _hosts.containsKey(code);

  /// Drops the host of [code], as if the relay went away.
  Future<void> dropHost(String code) async => _hosts[code]?.close(1011, 'relay restart');

  Future<void> _onRequest(HttpRequest request) async {
    final parts = request.uri.pathSegments;
    if (parts.length < 2 || parts[0] != 'rooms') return _status(request, 404);
    final code = parts[1];
    final role = parts.length > 2 ? parts[2] : null;
    final host = _hosts[code];

    if (!WebSocketTransformer.isUpgradeRequest(request)) return _status(request, host != null ? 200 : 404);
    if (role == 'host') {
      if (host != null) return _status(request, 409);
      final ws = await WebSocketTransformer.upgrade(request);
      _hosts[code] = ws;
      final guests = _guests[code] = {};
      ws.listen((raw) {
        if (raw is! String) return;
        final envelope = jsonDecode(raw) as Map<String, dynamic>;
        final target = guests[envelope['to']];
        if (target == null) return;
        if (envelope['close'] == true) {
          target.close(1000, 'removed by host');
        } else if (envelope['d'] is String) {
          target.add(envelope['d']);
        }
      }, onDone: () {
        _hosts.remove(code);
        for (final g in guests.values) {
          g.close(1001, 'host left');
        }
        guests.clear();
      });
      return;
    }
    if (role == 'guest') {
      if (host == null) return _status(request, 404);
      final ws = await WebSocketTransformer.upgrade(request);
      final id = 'g${_nextId++}';
      _guests[code]![id] = ws;
      host.add(jsonEncode({'e': 'open', 'id': id}));
      ws.listen(
        (raw) {
          if (raw is String) _hosts[code]?.add(jsonEncode({'e': 'msg', 'id': id, 'd': raw}));
        },
        onDone: () {
          if (_guests[code]?.remove(id) != null) _hosts[code]?.add(jsonEncode({'e': 'close', 'id': id}));
        },
      );
      return;
    }
    return _status(request, 404);
  }

  Future<void> _status(HttpRequest request, int status) async {
    request.response.statusCode = status;
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}
