import 'listening_log.dart';
import 'play_event.dart';

/// A ranked song in a recap.
class RecapSong {
  final String title;
  final String artist;
  final String trackId;
  final String? artworkUrl;
  final int plays;
  final Duration listened;

  const RecapSong({
    required this.title,
    required this.artist,
    required this.trackId,
    this.artworkUrl,
    required this.plays,
    required this.listened,
  });
}

/// A ranked artist in a recap.
class RecapArtist {
  final String name;
  final int plays;
  final Duration listened;

  /// Cover of their most-heard song, to picture them by.
  final String? artworkUrl;

  const RecapArtist({required this.name, required this.plays, required this.listened, this.artworkUrl});
}

/// A look back over a year or a month, from [ListeningLog.months].
class Recap {
  final String title;
  final Duration listened;
  final int plays;
  final List<RecapSong> topSongs;
  final List<RecapArtist> topArtists;
  final int songCount;
  final int artistCount;

  /// Hour of the day with the most listening (0–23), null when none.
  final int? peakHour;

  /// Days with any listening, and the longest run of them in a row.
  final int activeDays;
  final int longestStreak;

  /// For a year: listening per month (12 entries, January first).
  final List<Duration> byMonth;

  const Recap({
    required this.title,
    required this.listened,
    required this.plays,
    required this.topSongs,
    required this.topArtists,
    required this.songCount,
    required this.artistCount,
    required this.peakHour,
    required this.activeDays,
    required this.longestStreak,
    required this.byMonth,
  });

  bool get isEmpty => listened == Duration.zero;

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String monthName(int month) => _monthNames[month - 1];

  factory Recap.year(ListeningLog log, int year) {
    final months = <int, MonthStats>{};
    for (var m = 1; m <= 12; m++) {
      final stats = log.months[ListeningLog.monthKey(DateTime(year, m))];
      if (stats != null) months[m] = stats;
    }
    return Recap._build('$year', months, year);
  }

  factory Recap.month(ListeningLog log, int year, int month) {
    final stats = log.months[ListeningLog.monthKey(DateTime(year, month))];
    return Recap._build('${monthName(month)} $year', {if (stats != null) month: stats}, year);
  }

  /// Years with any listening, newest first.
  static List<int> yearsIn(ListeningLog log) {
    final years = log.months.keys.map((k) => int.tryParse(k.split('-').first)).whereType<int>().toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    return years;
  }

  factory Recap._build(String title, Map<int, MonthStats> months, int year) {
    final songs = <String, RecapSong>{};
    final artists = <String, ({String name, int plays, Duration listened, Duration best, String? art})>{};
    final byHour = List.filled(24, Duration.zero);
    final byMonth = List.filled(12, Duration.zero);
    final activeDates = <DateTime>[];

    for (final entry in months.entries) {
      final m = entry.value;
      byMonth[entry.key - 1] = m.listened;
      for (var h = 0; h < 24; h++) {
        byHour[h] += m.byHour[h];
      }
      activeDates.addAll(m.days.map((d) => DateTime(year, entry.key, d)));
      for (final s in m.songs.entries) {
        final t = s.value;
        final prev = songs[s.key];
        songs[s.key] = RecapSong(
          title: t.title,
          artist: t.artist,
          trackId: t.trackId,
          artworkUrl: prev?.artworkUrl ?? t.artworkUrl,
          plays: (prev?.plays ?? 0) + t.plays,
          listened: (prev?.listened ?? Duration.zero) + t.listened,
        );
      }
    }

    for (final s in songs.values) {
      final lead = leadArtistOf(s.artist);
      final key = normalizeName(lead);
      final prev = artists[key];
      final better = prev == null || s.listened > prev.best;
      artists[key] = (
        name: prev?.name ?? lead,
        plays: (prev?.plays ?? 0) + s.plays,
        listened: (prev?.listened ?? Duration.zero) + s.listened,
        best: better ? s.listened : prev.best,
        art: better ? (s.artworkUrl ?? prev?.art) : prev.art,
      );
    }

    final topSongs = songs.values.where((s) => s.plays > 0).toList()
      ..sort((a, b) => b.plays != a.plays ? b.plays.compareTo(a.plays) : b.listened.compareTo(a.listened));
    final topArtists = artists.values
        .map((a) => RecapArtist(name: a.name, plays: a.plays, listened: a.listened, artworkUrl: a.art))
        .toList()
      ..sort((a, b) => b.listened.compareTo(a.listened));

    int? peakHour;
    for (var h = 0; h < 24; h++) {
      if (byHour[h] > Duration.zero && (peakHour == null || byHour[h] > byHour[peakHour])) peakHour = h;
    }

    activeDates.sort();
    var longest = 0;
    var run = 0;
    DateTime? last;
    for (final d in activeDates) {
      // Calendar days apart, safe across daylight-saving changes.
      final gap = last == null
          ? null
          : DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(last.year, last.month, last.day)).inDays;
      run = gap == 1 ? run + 1 : 1;
      if (run > longest) longest = run;
      last = d;
    }

    return Recap(
      title: title,
      listened: byMonth.fold(Duration.zero, (sum, d) => sum + d),
      plays: songs.values.fold(0, (sum, s) => sum + s.plays),
      topSongs: topSongs.take(10).toList(),
      topArtists: topArtists.take(10).toList(),
      songCount: songs.length,
      artistCount: artists.length,
      peakHour: peakHour,
      activeDays: activeDates.length,
      longestStreak: longest,
      byMonth: byMonth,
    );
  }
}
