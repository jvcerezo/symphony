/// Estimates how far the host's clock is from this device's.
///
/// Each ping/pong gives a sample: the host's time `hostT` was read somewhere
/// between sending (`t0`) and receiving (`t1`), so the best guess is the
/// middle, `offset = hostT - (t0 + t1) / 2`. The sample with the shortest
/// round trip has the least room for error, so that one wins. Only the most
/// recent [window] samples count, so a clock that drifts is followed.
class ClockSync {
  ClockSync({this.window = 12});

  final int window;
  final List<({int offset, int rtt})> _samples = [];

  void addSample({required int t0, required int hostT, required int t1}) {
    final rtt = t1 - t0;
    if (rtt < 0) return; // The local clock jumped; useless.
    _samples.add((offset: hostT - (t0 + rtt ~/ 2), rtt: rtt));
    if (_samples.length > window) _samples.removeAt(0);
  }

  bool get isReady => _samples.isNotEmpty;

  ({int offset, int rtt})? get _best {
    if (_samples.isEmpty) return null;
    var best = _samples.first;
    for (final s in _samples) {
      if (s.rtt < best.rtt) best = s;
    }
    return best;
  }

  /// Host time minus local time, in ms. Zero until a sample arrives.
  int get offsetMs => _best?.offset ?? 0;

  /// Round trip of the sample in use, in ms.
  int? get rttMs => _best?.rtt;

  int hostNow(int localNowMs) => localNowMs + offsetMs;

  void reset() => _samples.clear();
}
