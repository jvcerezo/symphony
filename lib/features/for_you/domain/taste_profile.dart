import 'dart:math' as math;

import '../../audio_player/domain/entities/track.dart';
import 'listening_log.dart';
import 'play_event.dart';

/// What the user likes, from what they played: plays heard through count
/// up, quick skips count down, and recent plays count more than old ones
/// (a play's weight halves every [halfLife]).
class TasteProfile {
  /// Normalized lead artist → score; the display name is in [artistNames].
  final Map<String, double> artistScores;
  final Map<String, String> artistNames;

  /// Song key → score, and the song itself.
  final Map<String, double> songScores;
  final Map<String, Track> songs;

  /// Every song key ever heard or skipped, so discovery can avoid them.
  final Set<String> heard;

  const TasteProfile({
    required this.artistScores,
    required this.artistNames,
    required this.songScores,
    required this.songs,
    required this.heard,
  });

  static const halfLife = Duration(days: 30);

  static double weightOf(PlayOutcome o) => switch (o) {
        PlayOutcome.completed => 1.0,
        PlayOutcome.partial => 0.4,
        PlayOutcome.skipped => -0.6,
      };

  /// [seedTracks] (e.g. imported playlists) give a starting point before
  /// anything was played; each counts a little, like an old play.
  factory TasteProfile.from(ListeningLog log, {required DateTime now, Iterable<Track> seedTracks = const []}) {
    final artistScores = <String, double>{};
    final artistNames = <String, String>{};
    final songScores = <String, double>{};
    final songs = <String, Track>{};
    final heard = <String>{};

    void credit(String artist, String songKey, Track track, double w) {
      final lead = leadArtistOf(artist);
      final key = normalizeName(lead);
      if (key.isEmpty) return;
      artistScores[key] = (artistScores[key] ?? 0) + w;
      artistNames.putIfAbsent(key, () => lead);
      songScores[songKey] = (songScores[songKey] ?? 0) + w;
      songs.putIfAbsent(songKey, () => track);
    }

    for (final t in seedTracks) {
      final key = songKeyOf(t.title, t.artist);
      credit(t.artist, key, t, 0.15);
    }
    for (final e in log.recent) {
      final ageDays = now.difference(e.at).inHours / 24;
      final decay = math.pow(0.5, ageDays / halfLife.inDays).toDouble();
      heard.add(e.songKey);
      credit(e.artist, e.songKey, e.toTrack(), weightOf(e.outcome) * decay);
    }
    // Songs from months whose single plays are gone still count as heard.
    for (final m in log.months.values) {
      for (final s in m.songs.entries) {
        heard.add(s.key);
      }
    }

    return TasteProfile(
      artistScores: artistScores,
      artistNames: artistNames,
      songScores: songScores,
      songs: songs,
      heard: heard,
    );
  }

  bool get isEmpty => artistScores.values.every((s) => s <= 0);

  /// Best-liked artists first (display names), only those liked on balance.
  List<String> topArtists([int count = 10]) {
    final ranked = artistScores.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    return ranked.take(count).map((e) => artistNames[e.key]!).toList();
  }

  /// Best-liked songs first.
  List<Track> topSongs([int count = 30]) {
    final ranked = songScores.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    return ranked.take(count).map((e) => songs[e.key]!).toList();
  }

  /// The user's liked songs by [artist].
  List<Track> songsBy(String artist) {
    final key = normalizeName(leadArtistOf(artist));
    final ranked = songScores.entries
        .where((e) => e.value > 0 && normalizeName(leadArtistOf(songs[e.key]!.artist)) == key)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.map((e) => songs[e.key]!).toList();
  }

  bool knowsArtist(String artist) => (artistScores[normalizeName(leadArtistOf(artist))] ?? 0) != 0;

  /// Skipped more than liked: keep out of recommendations.
  bool dislikesArtist(String artist) => (artistScores[normalizeName(leadArtistOf(artist))] ?? 0) < -0.5;
}
