import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asks for Android 13+ `POST_NOTIFICATIONS` so the media playback
/// notification (lock screen / shade controls) is actually shown.
///
/// Backed by a method channel implemented in Android's `MainActivity`, so no
/// extra plugin is needed and Windows/web builds are unaffected (the call is
/// a no-op off Android). The request is attempted at most once per process;
/// Android itself stops prompting after the user denies twice.
class NotificationPermissionService {
  NotificationPermissionService({
    MethodChannel? channel,
    bool Function()? isAndroid,
  })  : _channel = channel ?? const MethodChannel(channelName),
        _isAndroid = isAndroid ?? _defaultIsAndroid;

  static const String channelName = 'com.symphony.symphony/notifications';
  static const String requestMethod = 'requestPostNotifications';

  final MethodChannel _channel;
  final bool Function() _isAndroid;
  Future<bool>? _request;

  static bool _defaultIsAndroid() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Requests the permission the first time it is called; later calls return
  /// the first outcome. Resolves to `true` when notifications may be shown or
  /// the platform doesn't need the permission. Never throws.
  Future<bool> ensureRequested() => _request ??= _requestOnce();

  Future<bool> _requestOnce() async {
    if (!_isAndroid()) return true;
    try {
      final granted = await _channel.invokeMethod<bool>(requestMethod);
      developer.log('POST_NOTIFICATIONS granted: $granted', name: 'NotificationPermission');
      return granted ?? false;
    } catch (e) {
      // MissingPluginException in tests/other embedders, or a concurrent request.
      developer.log('POST_NOTIFICATIONS request failed: $e', name: 'NotificationPermission');
      return false;
    }
  }
}
