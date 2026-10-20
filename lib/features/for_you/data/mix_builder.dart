import 'dart:math' as math;

import '../../audio_player/domain/entities/track.dart';
import '../../playlist_import/domain/entities/spotify_playlist.dart';
import '../domain/listening_log.dart';
import '../domain/play_event.dart';
import '../domain/taste_profile.dart';
import 'deezer_catalog.dart';

/// Builds the "Made for you" playlists. Mixes from the user's own plays
/// need no network; the rest add songs from Deezer's related artists.
class MixBuilder {
  MixBuilder({required DeezerCatalog catalog, DateTime Function()? clock})
      : _catalog = catalog,
        _clock = clock ?? DateTime.now;

  final DeezerCatalog _catalog;
  final DateTime Function() _clock;

  static const owner = 'Symphony';
  static const source = 'For you';

  /// Ids of mixes built here start with this.
  static const idPrefix = 'mix_';

  static bool isMix(SpotifyPlaylist p) => p.id.startsWith(idPrefix);

  // ---- From the user's own plays ----

  /// Songs played most in the last 30 days.
  SpotifyPlaylist? onRepeat(ListeningLog log, {required DateTime now}) {
    final since = now.subtract(const Duration(days: 30));
    final counts = <String, int>{};
    final latest = <String, PlayEvent>{};
    for (final e in log.recent) {
      if (e.at.isBefore(since) || e.outcome == PlayOutcome.skipped) continue;
      counts[e.songKey] = (counts[e.songKey] ?? 0) + 1;
      latest[e.songKey] = e;
    }
    final ranked = counts.entries.where((e) => e.value >= 2).toList()..sort((a, b) => b.value.compareTo(a.value));
    final tracks = ranked.take(30).map((e) => latest[e.key]!.toTrack()).toList();
    if (tracks.length < 5) return null;
    return _mix('on_repeat', 'On Repeat', 'The songs you can\'t stop playing right now', tracks);
  }

  /// The last songs listened to, newest first.
  SpotifyPlaylist? recentlyPlayed(ListeningLog log) {
    final seen = <String>{};
    final tracks = <Track>[];
    for (final e in log.recent.reversed) {
      if (e.outcome == PlayOutcome.skipped || !seen.add(e.songKey)) continue;
      tracks.add(e.toTrack());
      if (tracks.length == 50) break;
    }
    if (tracks.length < 3) return null;
    return _mix('recent', 'Recently Played', 'Pick up where you left off', tracks);
  }

  // ---- With Deezer ----

  /// Up to [count] mixes, each around one favorite artist: songs the user
  /// already likes by them and similar artists, plus top songs from those
  /// similar artists. Refreshes daily ([now]'s date seeds the order).
  Future<List<SpotifyPlaylist>> dailyMixes(TasteProfile taste, {required DateTime now, int count = 3}) async {
    final seeds = taste.topArtists(12);
    if (seeds.isEmpty) return const [];
    final mixes = <SpotifyPlaylist>[];
    final usedSeeds = <String>{};
    final rng = math.Random(_daySeed(now));

    for (final seed in seeds) {
      if (mixes.length == count) break;
      if (usedSeeds.contains(normalizeName(seed))) continue;
      final id = await _catalog.artistId(seed);
      if (id == null) continue;
      final related =
          (await _catalog.relatedArtists(id, limit: 10)).where((a) => !taste.dislikesArtist(a.name)).toList();
      usedSeeds.add(normalizeName(seed));
      // The next mix shouldn't be about an artist already in this one.
      usedSeeds.addAll(related.map((a) => normalizeName(a.name)));

      final familiar = <Track>[
        ...taste.songsBy(seed).take(8),
        for (final a in related.where((a) => taste.knowsArtist(a.name))) ...taste.songsBy(a.name).take(3),
      ];
      final newOnes = related.where((a) => !taste.knowsArtist(a.name)).take(4).toList();
      final fresh = <Track>[
        ...(await _catalog.topTracks(id, limit: 5)),
        for (final list in await Future.wait(newOnes.map((a) => _catalog.topTracks(a.id, limit: 4)))) ...list,
      ];

      final tracks = _interleave(_dedupe(familiar..shuffle(rng)), _dedupe(fresh..shuffle(rng)))
          .where((t) => !taste.dislikesArtist(t.artist));
      final picked = _capPerArtist(_dedupe(tracks), 4).take(30).toList();
      if (picked.length < 8) continue;

      final names = [seed, ...related.take(2).map((a) => a.name)];
      mixes.add(_mix(
        'daily_${mixes.length + 1}',
        'Daily Mix ${mixes.length + 1}',
        '${names.join(', ')} and more',
        picked,
      ));
    }
    return mixes;
  }

  /// New-to-you songs from artists similar to the user's favorites. Same
  /// songs all week; a new set each Monday.
  Future<SpotifyPlaylist?> discoverWeekly(TasteProfile taste, {required DateTime now}) async {
    final seeds = taste.topArtists(6);
    if (seeds.isEmpty) return null;
    final rng = math.Random(_weekSeed(now));

    final ids = (await Future.wait(seeds.map(_catalog.artistId))).whereType<int>().toList();
    final relatedLists = await Future.wait(ids.map((id) => _catalog.relatedArtists(id, limit: 8)));

    // Round-robin over the seeds so one favorite doesn't take over.
    final candidates = <DeezerArtist>[];
    final seen = <String>{};
    for (var i = 0; i < 8; i++) {
      for (final list in relatedLists) {
        if (i >= list.length) continue;
        final a = list[i];
        final key = normalizeName(a.name);
        if (taste.knowsArtist(a.name) || !seen.add(key)) continue;
        candidates.add(a);
      }
    }
    if (candidates.isEmpty) return null;
    candidates.shuffle(rng);

    final tops = await Future.wait(candidates.take(16).map((a) => _catalog.topTracks(a.id, limit: 5)));
    final tracks = <Track>[];
    for (final list in tops) {
      // A related artist's top songs can be duets with someone the user knows.
      final unheard = list
          .where((t) => !taste.heard.contains(songKeyOf(t.title, t.artist)) && !taste.knowsArtist(t.artist))
          .toList()
        ..shuffle(rng);
      tracks.addAll(unheard.take(2));
    }
    final picked = _capPerArtist(_dedupe(tracks..shuffle(rng)), 2).take(30).toList();
    if (picked.length < 8) return null;
    return _mix('discover', 'Discover Weekly', 'New music picked for you. Fresh every Monday.', picked);
  }

  /// What's most played right now; also what a new user starts from.
  Future<SpotifyPlaylist?> topHits() async {
    final tracks = await _catalog.chart(limit: 50);
    if (tracks.isEmpty) return null;
    return _mix('top_hits', 'Top Hits Right Now', 'The most played songs this week', tracks);
  }

  /// Songs to keep playing after [seed] when the queue runs out: [seed]'s
  /// artist radio, without anything in [exclude] (song keys) or by an
  /// artist the user keeps skipping.
  Future<List<Track>> radioAfter(Track seed,
      {Set<String> exclude = const {}, TasteProfile? taste, int count = 20}) async {
    final id = await _catalog.artistId(leadArtistOf(seed.artist));
    if (id == null) return const [];
    var pool = await _catalog.artistRadio(id, limit: 40);
    if (pool.isEmpty) {
      final related = await _catalog.relatedArtists(id, limit: 5);
      pool = [for (final list in await Future.wait(related.map((a) => _catalog.topTracks(a.id, limit: 4)))) ...list];
    }
    final skip = {...exclude, songKeyOf(seed.title, seed.artist)};
    final picked =
        pool.where((t) => !skip.contains(songKeyOf(t.title, t.artist)) && !(taste?.dislikesArtist(t.artist) ?? false));
    return _capPerArtist(_dedupe(picked), 3).take(count).toList();
  }

  // ---- Helpers ----

  /// Ids carry the day they were built, so a mix saved to the library
  /// stays apart from the next day's mix of the same name.
  SpotifyPlaylist _mix(String key, String title, String description, List<Track> tracks) => SpotifyPlaylist(
        id: '$idPrefix${key}_${_daySeed(_clock())}',
        title: title,
        description: description,
        coverUrl: tracks.map((t) => t.artworkUri).whereType<Uri>().firstOrNull?.toString(),
        ownerName: owner,
        source: source,
        tracks: tracks,
      );

  static List<Track> _dedupe(Iterable<Track> tracks) {
    final seen = <String>{};
    return tracks.where((t) => seen.add(songKeyOf(t.title, t.artist))).toList();
  }

  static Iterable<Track> _capPerArtist(Iterable<Track> tracks, int cap) {
    final counts = <String, int>{};
    return tracks.where((t) {
      final key = normalizeName(leadArtistOf(t.artist));
      counts[key] = (counts[key] ?? 0) + 1;
      return counts[key]! <= cap;
    });
  }

  /// a1, b1, a2, b2, … then whatever is left.
  static List<Track> _interleave(List<Track> a, List<Track> b) {
    final out = <Track>[];
    for (var i = 0; i < math.max(a.length, b.length); i++) {
      if (i < a.length) out.add(a[i]);
      if (i < b.length) out.add(b[i]);
    }
    return out;
  }

  static int _daySeed(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  /// The Monday starting [d]'s week.
  static DateTime weekStart(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));

  static int _weekSeed(DateTime d) => _daySeed(weekStart(d));
}
