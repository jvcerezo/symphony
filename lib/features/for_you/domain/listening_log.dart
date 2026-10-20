import 'play_event.dart';

/// A song's totals within a month.
class SongTally {
  final String title;
  final String artist;
  final String? artworkUrl;
  final String trackId;
  int plays;
  Duration listened;

  SongTally({
    required this.title,
    required this.artist,
    required this.trackId,
    this.artworkUrl,
    this.plays = 0,
    this.listened = Duration.zero,
  });

  Map<String, dynamic> toJson() => {
        't': title,
        'a': artist,
        'id': trackId,
        if (artworkUrl != null) 'art': artworkUrl,
        'p': plays,
        'ms': listened.inMilliseconds,
      };

  static SongTally fromJson(Map<String, dynamic> json) => SongTally(
        title: json['t'] as String,
        artist: json['a'] as String,
        trackId: json['id'] as String,
        artworkUrl: json['art'] as String?,
        plays: (json['p'] as num).toInt(),
        listened: Duration(milliseconds: (json['ms'] as num).toInt()),
      );
}

/// What was listened to in one calendar month. Kept for good (unlike the
/// raw plays), so a year can be looked back on.
class MonthStats {
  /// Song key → totals.
  final Map<String, SongTally> songs;

  /// Listening time per hour of the day (0–23).
  final List<Duration> byHour;

  /// Days of the month with any listening.
  final Set<int> days;

  MonthStats({Map<String, SongTally>? songs, List<Duration>? byHour, Set<int>? days})
      : songs = songs ?? {},
        byHour = byHour ?? List.filled(24, Duration.zero),
        days = days ?? {};

  Duration get listened => songs.values.fold(Duration.zero, (sum, s) => sum + s.listened);

  /// Keeps the file small: only the most-heard songs of a month are kept.
  static const maxSongs = 300;

  void add(PlayEvent e) {
    if (e.listened <= Duration.zero) return;
    final tally = songs.putIfAbsent(
      e.songKey,
      () => SongTally(title: e.title, artist: e.artist, trackId: e.trackId, artworkUrl: e.artworkUrl),
    );
    // A skip is time listened, not a play.
    if (e.outcome != PlayOutcome.skipped) tally.plays++;
    tally.listened += e.listened;
    byHour[e.at.hour] += e.listened;
    days.add(e.at.day);
    if (songs.length > maxSongs) {
      final least = songs.entries.reduce((a, b) => a.value.listened <= b.value.listened ? a : b);
      songs.remove(least.key);
    }
  }

  Map<String, dynamic> toJson() => {
        'songs': {for (final e in songs.entries) e.key: e.value.toJson()},
        'hours': byHour.map((d) => d.inMilliseconds).toList(),
        'days': days.toList()..sort(),
      };

  static MonthStats fromJson(Map<String, dynamic> json) {
    final songs = <String, SongTally>{};
    final rawSongs = json['songs'];
    if (rawSongs is Map) {
      for (final e in rawSongs.entries) {
        try {
          songs['${e.key}'] = SongTally.fromJson(Map<String, dynamic>.from(e.value as Map));
        } catch (_) {}
      }
    }
    final hours = List.filled(24, Duration.zero);
    final rawHours = json['hours'];
    if (rawHours is List) {
      for (var i = 0; i < rawHours.length && i < 24; i++) {
        hours[i] = Duration(milliseconds: (rawHours[i] as num).toInt());
      }
    }
    final rawDays = json['days'];
    return MonthStats(
      songs: songs,
      byHour: hours,
      days: rawDays is List ? rawDays.map((d) => (d as num).toInt()).toSet() : {},
    );
  }
}

/// Everything this device remembers about what was played: recent plays
/// one by one (for recommendations) and monthly totals (for recaps).
class ListeningLog {
  /// Most recent last.
  final List<PlayEvent> recent;

  /// "2026-10" → that month's totals.
  final Map<String, MonthStats> months;

  ListeningLog({List<PlayEvent>? recent, Map<String, MonthStats>? months})
      : recent = recent ?? [],
        months = months ?? {};

  static const keepRecentFor = Duration(days: 120);
  static const maxRecent = 3000;

  static String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  bool get isEmpty => recent.isEmpty && months.isEmpty;

  void add(PlayEvent e) {
    recent.add(e);
    months.putIfAbsent(monthKey(e.at), MonthStats.new).add(e);
    _prune(e.at);
  }

  void _prune(DateTime now) {
    final cutoff = now.subtract(keepRecentFor);
    recent.removeWhere((e) => e.at.isBefore(cutoff));
    if (recent.length > maxRecent) recent.removeRange(0, recent.length - maxRecent);
  }

  Map<String, dynamic> toJson() => {
        'v': 1,
        'recent': recent.map((e) => e.toJson()).toList(),
        'months': {for (final e in months.entries) e.key: e.value.toJson()},
      };

  static ListeningLog fromJson(Map<String, dynamic> json) {
    final recent = <PlayEvent>[];
    final rawRecent = json['recent'];
    if (rawRecent is List) {
      for (final r in rawRecent) {
        if (r is Map) {
          final e = PlayEvent.fromJson(Map<String, dynamic>.from(r));
          if (e != null) recent.add(e);
        }
      }
    }
    final months = <String, MonthStats>{};
    final rawMonths = json['months'];
    if (rawMonths is Map) {
      for (final e in rawMonths.entries) {
        if (e.value is Map) months['${e.key}'] = MonthStats.fromJson(Map<String, dynamic>.from(e.value as Map));
      }
    }
    return ListeningLog(recent: recent, months: months);
  }
}
