import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/data/services/symphony_audio_handler.dart';
import 'package:symphony/features/jam/data/jam_discovery.dart';
import 'package:symphony/features/jam/data/jam_transport.dart';
import 'package:symphony/features/jam/presentation/jam_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Real UDP over loopback; the beacon takes a free port so tests can run
  // next to a real Symphony.
  late JamBeacon beacon;

  setUp(() async {
    beacon = (await startJamBeacon(code: '0420', port: 41234, hostName: 'Jet', discoveryPort: 0))!;
  });
  tearDown(() => beacon.close());

  Future<FoundJam?> find(String code) =>
      findLanJam(code, discoveryPort: beacon.port, targets: ['127.0.0.1'], timeout: const Duration(milliseconds: 800));

  test('the host answers for its code with where to connect', () async {
    final found = await find('0420');
    expect(found, (host: '127.0.0.1', port: 41234, hostName: 'Jet'));
  });

  test('nobody answers for another code', () async {
    expect(await find('9999'), isNull);
  });

  group('JamController', () {
    late SymphonyAudioHandler handler;
    setUp(() => handler = SymphonyAudioHandler());
    tearDown(() => handler.release());

    test('joining a code nobody hosts explains what to check', () async {
      final jam = JamController(handler: handler, displayName: () => 'Ana', find: (_) async => null);
      await jam.join(code: '0420');
      final s = jam.state as JamIdle;
      expect(s.error, contains('No Jam with code 0420 on this Wi-Fi'));
    });

    test('hosting starts the beacon, and ending the Jam stops it', () async {
      final calls = <String>[];
      final jam = JamController(
        handler: handler,
        displayName: () => 'Jet',
        bind: () => bindLanJamServer(loopbackOnly: true),
        beacon: ({required code, required port, required hostName}) async {
          calls.add('beacon $code $hostName');
          return _Beacon(calls);
        },
      );
      await jam.host();
      final s = jam.state as JamHosting;
      expect(calls, ['beacon ${s.code} Jet']);
      expect(s.discoverable, isTrue);

      await jam.leave();
      expect(calls.last, 'beacon closed');
    });

    test('a Jam that cannot be found by code says so', () async {
      final jam = JamController(
        handler: handler,
        displayName: () => 'Jet',
        bind: () => bindLanJamServer(loopbackOnly: true),
        beacon: ({required code, required port, required hostName}) async => null,
      );
      await jam.host();
      expect((jam.state as JamHosting).discoverable, isFalse);
      await jam.leave();
    });
  });
}

class _Beacon implements JamBeacon {
  _Beacon(this.calls);
  final List<String> calls;
  @override
  int get port => 0;
  @override
  Future<void> close() async => calls.add('beacon closed');
}
