import 'jam_transport.dart';

const lanJamSupported = false;

Future<JamServer> bindLanJamServer({int port = 0, bool loopbackOnly = false}) =>
    Future.error(UnsupportedError('Hosting a Jam is not available here'));

Future<JamConnection> connectLanJam(String host, int port, {Duration timeout = const Duration(seconds: 5)}) =>
    Future.error(UnsupportedError('Joining a Jam is not available here'));

Future<List<String>> localNetworkAddresses() async => const [];

Future<bool> onlineJamExists(String code, {required String relay}) async => false;

Future<JamServer> hostOnlineJam(String code, {required String relay, void Function()? onLost}) =>
    Future.error(UnsupportedError('Hosting a Jam is not available here'));

Future<JamConnection> joinOnlineJam(String code, {required String relay}) =>
    Future.error(UnsupportedError('Joining a Jam is not available here'));
