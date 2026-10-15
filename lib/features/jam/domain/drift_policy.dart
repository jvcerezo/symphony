/// Decides when a guest is far enough off the host to seek.
///
/// Small drift is left alone: a seek is audible and itself lands a little
/// late, so seeking for tiny errors only makes things worse. After a seek
/// the guest waits [cooldown] before judging again, so it doesn't jump back
/// and forth while the player settles.
class DriftPolicy {
  const DriftPolicy({
    this.threshold = const Duration(milliseconds: 300),
    this.cooldown = const Duration(seconds: 3),
  });

  final Duration threshold;
  final Duration cooldown;

  /// Where to seek to, or null to leave playback alone. [lead] is added to
  /// the target to make up for the time a seek takes to be heard.
  Duration? correction({
    required Duration actual,
    required Duration expected,
    required DateTime now,
    DateTime? lastSeekAt,
    Duration lead = Duration.zero,
  }) {
    if (lastSeekAt != null && now.difference(lastSeekAt) < cooldown) return null;
    if ((actual - expected).abs() <= threshold) return null;
    final target = expected + lead;
    return target.isNegative ? Duration.zero : target;
  }
}
