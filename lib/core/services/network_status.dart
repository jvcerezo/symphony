import 'dart:async';

import 'network_status_stub.dart' if (dart.library.io) 'network_status_io.dart' as impl;

/// Whether this device can reach the internet right now, answered within a
/// few seconds, so playback can go straight to what's on the device when it
/// can't instead of waiting on lookups that will fail.
///
/// An answer is reused for [maxAge]; concurrent questions share one check.
class NetworkStatus {
  NetworkStatus({
    Future<bool> Function()? probe,
    Future<bool> Function()? meteredProbe,
    this.maxAge = const Duration(seconds: 10),
    this.trustOnlineFor = const Duration(minutes: 2),
  })  : _probe = probe ?? impl.canReachInternet,
        _meteredProbe = meteredProbe ?? impl.isMeteredConnection;

  final Future<bool> Function() _probe;
  final Future<bool> Function() _meteredProbe;

  /// Whether the connection costs the user data, as on mobile data or a
  /// metered hotspot (Android says so); false when unknown. Downloads the
  /// user isn't waiting on hold back then: they use data and keep the
  /// phone's radio, and so the phone, working.
  Future<bool> isMetered() => _meteredProbe().catchError((Object _) => false);
  final Duration maxAge;

  /// How long a check that found the internet lets [isLikelyOnline] answer
  /// at once, without waiting on another one.
  final Duration trustOnlineFor;

  bool? _last;
  DateTime? _checkedAt;
  Future<bool>? _inFlight;

  /// Like [isOnline], but answers at once when a check found the internet in
  /// the last [trustOnlineFor], checking again in the background. For
  /// starting a song: waiting on a connection to YouTube before every lookup
  /// added a round trip (seconds, on a weak signal) to each one. A lookup
  /// that fails offline is handled like any failure, and [forget] makes the
  /// next answer a real check.
  Future<bool> isLikelyOnline() {
    final checkedAt = _checkedAt;
    if (_last == true && checkedAt != null && DateTime.now().difference(checkedAt) < trustOnlineFor) {
      if (DateTime.now().difference(checkedAt) >= maxAge) unawaited(isOnline());
      return Future.value(true);
    }
    return isOnline();
  }

  /// Drops the last answer, e.g. after a lookup failed: the next question
  /// checks again.
  void forget() {
    _last = null;
    _checkedAt = null;
  }

  Future<bool> isOnline() {
    final last = _last;
    final checkedAt = _checkedAt;
    if (last != null && checkedAt != null && DateTime.now().difference(checkedAt) < maxAge) {
      return Future.value(last);
    }
    return _inFlight ??= _probe().catchError((Object _) => false).then((online) {
      _last = online;
      _checkedAt = DateTime.now();
      _inFlight = null;
      return online;
    });
  }
}
