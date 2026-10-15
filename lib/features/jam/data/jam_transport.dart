import 'jam_transport_stub.dart' if (dart.library.io) 'jam_transport_io.dart' as impl;

/// One open link between a Jam host and a guest, carrying text frames.
///
/// The Jam services only see this, so the same protocol runs over a socket
/// on the local network or, later, through a relay.
abstract interface class JamConnection {
  /// Incoming frames; done when the other side or the network closes it.
  Stream<String> get messages;

  /// Sends [message]; quietly dropped once the connection is closing.
  void send(String message);

  Future<void> close();
}

/// Accepts guests' connections on the host.
abstract interface class JamServer {
  Stream<JamConnection> get connections;

  /// The TCP port guests connect to.
  int get port;

  Future<void> close();
}

/// Path of the Jam WebSocket on a hosting device.
const jamSocketPath = '/jam';

/// Whether this platform can host or join a Jam on the local network.
/// False on web: a browser can't listen for connections, and an `https`
/// page may not open a `ws://` socket to a LAN address.
bool get lanJamSupported => impl.lanJamSupported;

/// Starts listening for guests on every IPv4 interface ([port] 0 picks a
/// free one). [loopbackOnly] is for tests.
Future<JamServer> bindLanJamServer({int port = 0, bool loopbackOnly = false}) =>
    impl.bindLanJamServer(port: port, loopbackOnly: loopbackOnly);

/// Connects to a host at [host]:[port].
Future<JamConnection> connectLanJam(String host, int port, {Duration timeout = const Duration(seconds: 5)}) =>
    impl.connectLanJam(host, port, timeout: timeout);

/// This device's addresses on the local network, for guests to type in.
Future<List<String>> localNetworkAddresses() => impl.localNetworkAddresses();
