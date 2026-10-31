import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/core/services/network_status.dart';

void main() {
  late int probes;
  late bool online;
  late NetworkStatus network;

  setUp(() {
    probes = 0;
    online = true;
    network = NetworkStatus(
      probe: () async {
        probes++;
        return online;
      },
      maxAge: Duration.zero,
    );
  });

  test('starting a song after a check found the internet does not wait on another', () async {
    expect(await network.isOnline(), isTrue);
    final before = probes;

    expect(await network.isLikelyOnline(), isTrue);
    // Answered at once; one check runs behind it.
    await pumpEventQueue();
    expect(probes, before + 1);
  });

  test('a background check that finds no connection is the next answer', () async {
    expect(await network.isOnline(), isTrue);
    online = false;

    expect(await network.isLikelyOnline(), isTrue);
    await pumpEventQueue();
    expect(await network.isLikelyOnline(), isFalse);
  });

  test('after forget, it checks for real', () async {
    expect(await network.isOnline(), isTrue);
    online = false;
    network.forget();

    expect(await network.isLikelyOnline(), isFalse);
  });

  test('offline last time: it checks again before saying online', () async {
    online = false;
    expect(await network.isOnline(), isFalse);
    online = true;

    expect(await network.isLikelyOnline(), isTrue);
  });

  test('an old answer is not trusted', () async {
    network = NetworkStatus(probe: () async => online, maxAge: Duration.zero, trustOnlineFor: Duration.zero);
    expect(await network.isOnline(), isTrue);
    online = false;

    expect(await network.isLikelyOnline(), isFalse);
  });
}
