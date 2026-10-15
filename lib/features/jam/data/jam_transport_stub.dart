import 'jam_transport.dart';

const lanJamSupported = false;

Future<JamServer> bindLanJamServer({int port = 0, bool loopbackOnly = false}) =>
    Future.error(UnsupportedError('Hosting a Jam is not available here'));

Future<JamConnection> connectLanJam(String host, int port, {Duration timeout = const Duration(seconds: 5)}) =>
    Future.error(UnsupportedError('Joining a Jam is not available here'));

Future<List<String>> localNetworkAddresses() async => const [];
