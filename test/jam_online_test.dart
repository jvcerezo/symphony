import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/data/services/symphony_audio_handler.dart';
import 'package:symphony/features/jam/data/jam_transport.dart';
import 'package:symphony/features/jam/presentation/jam_providers.dart';

import 'fake_jam_relay.dart';

/// Real sockets: the test binding otherwise answers every HTTP request with
/// a 400, which would hide the local relay.
class _RealNetwork extends HttpOverrides {}

Future<T> real<T>(Future<T> Function() body) => HttpOverrides.runWithHttpOverrides(body, _RealNetwork());

Future<void> until(bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('online Jam codes', () {
    test('are 6 characters without look-alikes', () {
      for (var i = 0; i < 200; i++) {
        final code = newOnlineJamCode();
        expect(isOnlineJamCode(code), isTrue, reason: code);
        expect(code, isNot(matches(RegExp('[01ILO]'))));
      }
    });

    test('are told apart from Wi-Fi codes', () {
      expect(isOnlineJamCode('K7P2QX'), isTrue);
      expect(isOnlineJamCode('0420'), isFalse);
      expect(isOnlineJamCode('K7P2Q'), isFalse);
      expect(isOnlineJamCode('K7P2QO'), isFalse);
    });
  });

  group('JamController online', () {
    late FakeJamRelay relay;
    late SymphonyAudioHandler hostHandler;
    late SymphonyAudioHandler guestHandler;
    final controllers = <JamController>[];

    setUp(() async {
      relay = await FakeJamRelay.start();
      hostHandler = SymphonyAudioHandler();
      guestHandler = SymphonyAudioHandler();
    });

    tearDown(() async {
      for (final c in controllers) {
        await c.leave();
      }
      controllers.clear();
      hostHandler.release();
      guestHandler.release();
      await relay.close();
    });

    JamController controller(SymphonyAudioHandler handler, String name, {String? relayUrl}) {
      final url = relayUrl ?? relay.url;
      final jam = JamController(
        handler: handler,
        displayName: () => name,
        hostOnline: (code, onLost) => real(() => hostOnlineJam(code, relay: url, onLost: onLost)),
        joinOnline: (code) => real(() => joinOnlineJam(code, relay: url)),
        onlineExists: (code) => real(() => onlineJamExists(code, relay: url)),
      );
      controllers.add(jam);
      return jam;
    }

    test('a host online gets a 6-character code that a guest anywhere can join', () async {
      final host = controller(hostHandler, 'Jet');
      await host.host(online: true);
      final hosting = host.state as JamHosting;
      expect(hosting.online, isTrue);
      expect(isOnlineJamCode(hosting.code), isTrue);

      final guest = controller(guestHandler, 'Ana');
      // Typed in lower case; codes are not case-sensitive.
      await guest.join(code: hosting.code.toLowerCase());
      final joined = guest.state as JamJoined;
      expect(joined.hostName, 'Jet');

      await until(() => (host.state as JamHosting).members.length == 2);
      expect((host.state as JamHosting).members.last.name, 'Ana');
    });

    test('joining a code nobody hosts says so', () async {
      final guest = controller(guestHandler, 'Ana');
      await guest.join(code: 'K7P2QX');
      expect((guest.state as JamIdle).error, 'No online Jam with code K7P2QX. Check the code with the host.');
    });

    test('a host whose relay connection drops ends the Jam and says why', () async {
      final host = controller(hostHandler, 'Jet');
      await host.host(online: true);
      final code = (host.state as JamHosting).code;
      await until(() => relay.hasHost(code));
      await relay.dropHost(code);
      await until(() => host.state is JamIdle);
      expect((host.state as JamIdle).endReason, 'relay_lost');
    });

    test('without internet, hosting and joining explain the problem', () async {
      final dead = await FakeJamRelay.start();
      final offline = dead.url;
      await dead.close();
      final host = controller(hostHandler, 'Jet', relayUrl: offline);
      await host.host(online: true);
      expect((host.state as JamIdle).error, contains('Could not start an online Jam'));

      final guest = controller(guestHandler, 'Ana', relayUrl: offline);
      await guest.join(code: 'K7P2QX');
      expect((guest.state as JamIdle).error, contains('Could not reach the online Jam service'));
    });
  });
}
