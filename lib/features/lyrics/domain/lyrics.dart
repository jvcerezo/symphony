/// One timed line of synced lyrics.
class LyricLine {
  final Duration time;
  final String text;

  const LyricLine(this.time, this.text);

  @override
  String toString() => 'LyricLine($time, "$text")';
}

/// Lyrics for one song: time-synced lines when available, otherwise plain
/// text. [instrumental] marks songs known to have no words.
class Lyrics {
  final List<LyricLine> lines;
  final String? plainText;
  final bool instrumental;

  const Lyrics({this.lines = const [], this.plainText, this.instrumental = false});

  bool get isSynced => lines.isNotEmpty;
  bool get hasText => isSynced || (plainText?.trim().isNotEmpty ?? false);

  /// Index of the line being sung at [position], or -1 before the first.
  int lineIndexAt(Duration position) {
    int lo = 0, hi = lines.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].time <= position) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  static final _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  static final _offsetTag = RegExp(r'^\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false);

  /// Parses LRC text. Lines may carry several timestamps
  /// (`[00:12.30][01:40.00]chorus`); metadata tags are skipped and an
  /// `[offset:+/-ms]` tag shifts every line.
  static List<LyricLine> parseLrc(String lrc) {
    var offsetMs = 0;
    final result = <LyricLine>[];
    for (final raw in lrc.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final offset = _offsetTag.firstMatch(line);
      if (offset != null) {
        offsetMs = int.tryParse(offset.group(1)!) ?? 0;
        continue;
      }
      final stamps = <Duration>[];
      var rest = line;
      while (true) {
        final m = _timeTag.matchAsPrefix(rest);
        if (m == null) break;
        final minutes = int.parse(m.group(1)!);
        final seconds = int.parse(m.group(2)!);
        final frac = m.group(3);
        // "5" = 500 ms, "50" = 500 ms, "500" = 500 ms.
        final ms = frac == null ? 0 : int.parse(frac.padRight(3, '0'));
        stamps.add(Duration(minutes: minutes, seconds: seconds, milliseconds: ms));
        rest = rest.substring(m.end);
      }
      if (stamps.isEmpty) continue;
      final text = rest.trim();
      for (final t in stamps) {
        // A positive offset means lyrics should appear earlier.
        final shifted = t - Duration(milliseconds: offsetMs);
        result.add(LyricLine(shifted.isNegative ? Duration.zero : shifted, text));
      }
    }
    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }
}
