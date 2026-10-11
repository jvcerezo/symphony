import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/core/config/server_config.dart';

void main() {
  group('ServerConfig.candidateOrigins', () {
    test('native has no default servers (fully on-device)', () {
      expect(ServerConfig.candidateOrigins(isWeb: false, override: ''), isEmpty);
    });

    test('native uses a server only when SYMPHONY_SERVER is set', () {
      expect(
        ServerConfig.candidateOrigins(isWeb: false, override: 'http://10.0.0.5:9000/'),
        ['http://10.0.0.5:9000'],
      );
    });

    test('web uses only the page origin', () {
      expect(
        ServerConfig.candidateOrigins(isWeb: true, webOrigin: 'https://demo.example', override: ''),
        ['https://demo.example'],
      );
    });

    test('override is tried before the web page origin', () {
      expect(
        ServerConfig.candidateOrigins(isWeb: true, webOrigin: 'https://demo.example', override: 'http://10.0.0.5:9000'),
        ['http://10.0.0.5:9000', 'https://demo.example'],
      );
    });

    test('no duplicates when override equals the page origin', () {
      expect(
        ServerConfig.candidateOrigins(isWeb: true, webOrigin: 'https://demo.example', override: 'https://demo.example'),
        ['https://demo.example'],
      );
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
