import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/core/config/server_config.dart';

void main() {
  group('ServerConfig.candidateOrigins', () {
    test('native release: production then localhost, no LAN host', () {
      expect(
        ServerConfig.candidateOrigins(isWeb: false, isDebug: false, override: ''),
        [
          ServerConfig.productionOrigin,
          'http://localhost:8080',
          'http://127.0.0.1:8080',
        ],
      );
    });

    test('native debug: LAN dev host after production', () {
      expect(
        ServerConfig.candidateOrigins(isWeb: false, isDebug: true, override: ''),
        [
          ServerConfig.productionOrigin,
          ServerConfig.lanDevOrigin,
          'http://localhost:8080',
          'http://127.0.0.1:8080',
        ],
      );
    });

    test('preferLocal puts local hosts first and LAN last', () {
      expect(
        ServerConfig.candidateOrigins(preferLocal: true, isWeb: false, isDebug: true, override: ''),
        [
          'http://127.0.0.1:8080',
          'http://localhost:8080',
          ServerConfig.productionOrigin,
          ServerConfig.lanDevOrigin,
        ],
      );
    });

    test('web uses only the page origin', () {
      expect(
        ServerConfig.candidateOrigins(isWeb: true, isDebug: true, webOrigin: 'https://demo.example', override: ''),
        ['https://demo.example'],
      );
    });

    test('SYMPHONY_SERVER override is tried first and normalized', () {
      final native = ServerConfig.candidateOrigins(isWeb: false, isDebug: false, override: 'http://10.0.0.5:9000/');
      expect(native.first, 'http://10.0.0.5:9000');
      expect(native, contains(ServerConfig.productionOrigin));

      final web = ServerConfig.candidateOrigins(isWeb: true, webOrigin: 'https://demo.example', override: 'http://10.0.0.5:9000');
      expect(web, ['http://10.0.0.5:9000', 'https://demo.example']);
    });

    test('no duplicates when override equals a default origin', () {
      final origins = ServerConfig.candidateOrigins(
        isWeb: false,
        isDebug: false,
        override: ServerConfig.productionOrigin,
      );
      expect(origins.where((o) => o == ServerConfig.productionOrigin).length, 1);
    });
  });

  group('ServerConfig.primaryOrigin', () {
    test('defaults to production on native', () {
      expect(ServerConfig.primaryOrigin(isWeb: false, override: ''), ServerConfig.productionOrigin);
    });

    test('uses the page origin on web', () {
      expect(ServerConfig.primaryOrigin(isWeb: true, webOrigin: 'https://demo.example', override: ''), 'https://demo.example');
    });

    test('override wins', () {
      expect(ServerConfig.primaryOrigin(isWeb: true, webOrigin: 'https://demo.example', override: 'https://staging.example'), 'https://staging.example');
    });
  });

  group('ServerConfig.isSymphonyHost', () {
    test('recognizes our hosts and rejects third parties', () {
      expect(ServerConfig.isSymphonyHost('symphony.jettimothycerezo.dev', override: ''), isTrue);
      expect(ServerConfig.isSymphonyHost('localhost', override: ''), isTrue);
      expect(ServerConfig.isSymphonyHost('192.168.1.57', override: ''), isTrue);
      expect(ServerConfig.isSymphonyHost('rr3---sn.googlevideo.com', override: ''), isFalse);
    });

    test('recognizes the override host', () {
      expect(ServerConfig.isSymphonyHost('staging.example', override: 'https://staging.example'), isTrue);
      expect(ServerConfig.isSymphonyHost('staging.example', override: ''), isFalse);
    });
  });
}
