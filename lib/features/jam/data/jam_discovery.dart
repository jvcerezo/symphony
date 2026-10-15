import 'jam_discovery_stub.dart' if (dart.library.io) 'jam_discovery_io.dart' as impl;

/// UDP port hosts listen on for "who has this Jam code?" broadcasts.
const jamDiscoveryPort = 47853;

/// A host that answered for the code.
typedef FoundJam = ({String host, int port, String hostName});

/// Answers guests looking for this Jam's code while hosting.
abstract interface class JamBeacon {
  /// The UDP port it listens on ([jamDiscoveryPort] unless a test chose).
  int get port;

  Future<void> close();
}

/// Starts answering for [code] with the Jam's TCP [port]. Null when the
/// discovery port can't be opened (another app on it); the Jam still runs,
/// guests just can't find it by code.
Future<JamBeacon?> startJamBeacon({
  required String code,
  required int port,
  required String hostName,
  int discoveryPort = jamDiscoveryPort,
}) =>
    impl.startJamBeacon(code: code, port: port, hostName: hostName, discoveryPort: discoveryPort);

/// Looks for a host with [code] on the local network: broadcasts the
/// question a few times and takes the first host that answers. Null when
/// none does within [timeout]. [targets] replaces the broadcast addresses
/// (tests).
Future<FoundJam?> findLanJam(
  String code, {
  Duration timeout = const Duration(seconds: 3),
  int discoveryPort = jamDiscoveryPort,
  List<String>? targets,
}) =>
    impl.findLanJam(code, timeout: timeout, discoveryPort: discoveryPort, targets: targets);
