import 'network_status_stub.dart' if (dart.library.io) 'network_status_io.dart' as impl;

/// Whether this device can reach the internet right now, answered within a
/// few seconds, so playback can go straight to what's on the device when it
/// can't instead of waiting on lookups that will fail.
///
/// An answer is reused for [maxAge]; concurrent questions share one check.
class NetworkStatus {
  NetworkStatus({Future<bool> Function()? probe, this.maxAge = const Duration(seconds: 10)})
      : _probe = probe ?? impl.canReachInternet;

  final Future<bool> Function() _probe;
  final Duration maxAge;

  bool? _last;
  DateTime? _checkedAt;
  Future<bool>? _inFlight;

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
