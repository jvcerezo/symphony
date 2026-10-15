import 'jam_discovery.dart';

Future<JamBeacon?> startJamBeacon({
  required String code,
  required int port,
  required String hostName,
  required int discoveryPort,
}) async =>
    null;

Future<FoundJam?> findLanJam(
  String code, {
  required Duration timeout,
  required int discoveryPort,
  List<String>? targets,
}) async =>
    null;
