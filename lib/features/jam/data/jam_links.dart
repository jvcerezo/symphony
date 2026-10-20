import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/jam_invite.dart';

/// Jam invite links that open the app: `symphony://jam/<code>` (Android;
/// see `MainActivity`). Delivers the code of each one, the link the app
/// was started with included.
class JamLinks {
  JamLinks({MethodChannel? channel, bool? supported, DateTime Function()? clock})
      : _channel = channel ?? const MethodChannel('com.symphony.symphony/links'),
        _supported = supported ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
        _clock = clock ?? DateTime.now;

  final MethodChannel _channel;
  final bool _supported;
  final DateTime Function() _clock;

  String? _lastCode;
  DateTime? _lastAt;

  /// One link can arrive twice (at start and from the activity); the
  /// second is dropped.
  static const _repeatWindow = Duration(seconds: 10);

  void listen(void Function(String code) onCode) {
    if (!_supported) return;
    void handle(Object? raw) {
      final uri = raw is String ? Uri.tryParse(raw) : null;
      final code = uri == null ? null : JamInvite.codeFrom(uri);
      if (code == null) return;
      final now = _clock();
      if (code == _lastCode && _lastAt != null && now.difference(_lastAt!) < _repeatWindow) return;
      _lastCode = code;
      _lastAt = now;
      onCode(code);
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'link') handle(call.arguments);
    });
    _channel.invokeMethod<String>('initialLink').then(handle).catchError((Object e) {
      developer.log('No start link: $e', name: 'Jam');
    });
  }
}
