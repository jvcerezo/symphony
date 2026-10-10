import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/core/services/notification_permission_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(NotificationPermissionService.channelName);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('NotificationPermissionService', () {
    test('is a no-op returning true off Android', () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return false;
      });
      final service = NotificationPermissionService(isAndroid: () => false);

      expect(await service.ensureRequested(), isTrue);
      expect(calls, 0);
    });

    test('asks the platform once and memoizes the outcome', () async {
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        return true;
      });
      final service = NotificationPermissionService(isAndroid: () => true);

      final results = await Future.wait([service.ensureRequested(), service.ensureRequested()]);
      expect(results, [true, true]);
      expect(await service.ensureRequested(), isTrue);
      expect(methods, [NotificationPermissionService.requestMethod]);
    });

    test('reports a denial', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => false);
      final service = NotificationPermissionService(isAndroid: () => true);

      expect(await service.ensureRequested(), isFalse);
    });

    test('never throws when the channel is missing or errors', () async {
      final missing = NotificationPermissionService(isAndroid: () => true);
      expect(await missing.ensureRequested(), isFalse);

      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'in_progress');
      });
      final failing = NotificationPermissionService(isAndroid: () => true);
      expect(await failing.ensureRequested(), isFalse);
    });
  });
}
