import 'dart:math';

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

/// The relay that carries online Jams (devices on different networks).
/// It only passes Jam messages along: which song, play/pause and position,
/// never audio. Override with `--dart-define=SYMPHONY_JAM_RELAY=wss://…`.
const jamRelayUrl = String.fromEnvironment(
  'SYMPHONY_JAM_RELAY',
  defaultValue: 'wss://symphony-jam.workers.dev',
);

/// Online Jam codes: 6 characters with no look-alikes (no 0/O, 1/I/L), so
/// they can be read out loud. Wi-Fi Jams keep their 4 digits.
const onlineJamCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// A new random online Jam code.
String newOnlineJamCode([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(6, (_) => onlineJamCodeAlphabet[r.nextInt(onlineJamCodeAlphabet.length)]).join();
}

/// Whether [code] (already upper-cased) is an online Jam code.
bool isOnlineJamCode(String code) => RegExp('^[$onlineJamCodeAlphabet]{6}\$').hasMatch(code);

/// Whether a Jam with [code] is running on the relay.
Future<bool> onlineJamExists(String code, {String relay = jamRelayUrl}) => impl.onlineJamExists(code, relay: relay);

/// Hosts an online Jam under [code]. [onLost] runs if the relay connection
/// drops while hosting.
Future<JamServer> hostOnlineJam(String code, {String relay = jamRelayUrl, void Function()? onLost}) =>
    impl.hostOnlineJam(code, relay: relay, onLost: onLost);

/// Joins the online Jam with [code] through the relay.
Future<JamConnection> joinOnlineJam(String code, {String relay = jamRelayUrl}) =>
    impl.joinOnlineJam(code, relay: relay);
