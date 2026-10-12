import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../metadata_search/data/services/artwork_resolver_service.dart';
import '../domain/lyrics.dart';

/// Thrown when lyrics couldn't be looked up (network or server trouble),
/// as opposed to a song that simply has none.
class LyricsLookupException implements Exception {
  final String message;
  const LyricsLookupException(this.message);

  @override
  String toString() => 'LyricsLookupException: $message';
}

/// Looks up lyrics on LRCLIB (lrclib.net): a free public lyrics database
/// with time-synced lyrics and no API key. Runs on the device, like the
/// iTunes/Deezer metadata search.
class LyricsService {
  static const _base = 'https://lrclib.net/api';

  final http.Client _client;
  final Map<String, Lyrics?> _cache = {};

  LyricsService({http.Client? client}) : _client = client ?? http.Client();

  /// LRCLIB asks clients to identify themselves. Browsers don't allow
  /// setting User-Agent, so only native builds send it.
  static Map<String, String> get _headers =>
      kIsWeb ? const {} : const {'User-Agent': 'Symphony (https://github.com/jvcerezo/symphony)'};

  /// Lead artist without featured guests: "The Weeknd ft. Daft Punk" and
  /// "Drake, 21 Savage" → the first name. Duos like "Simon & Garfunkel"
  /// stay whole, since that's how they're credited.
  static String primaryArtist(String artist) {
    final parts = artist.split(RegExp(r'\s+(?:ft\.?|feat\.?|featuring)\s+|\s*,\s*', caseSensitive: false));
    return parts.first.trim();
  }

  /// Lyrics for a song, or null when LRCLIB has none.
  /// Throws [LyricsLookupException] when the lookup itself fails.
  Future<Lyrics?> fetch({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    final cleanTitle = ArtworkResolverService.cleanTrackTitle(title);
    final cleanArtist = primaryArtist(artist);
    final key = '${cleanArtist.toLowerCase()}|${cleanTitle.toLowerCase()}';
    if (_cache.containsKey(key)) return _cache[key];

    final seconds = duration?.inSeconds ?? 0;
    Lyrics? found;

    // 1. Exact lookup: needs the length, and matches LRCLIB's own records.
    if (seconds > 0) {
      final json = await _getJson(Uri.parse('$_base/get').replace(queryParameters: {
        'track_name': cleanTitle,
        'artist_name': cleanArtist,
        if (album != null && album.isNotEmpty) 'album_name': album,
        'duration': '$seconds',
      }));
      if (json is Map) found = _fromRecord(json);
    }

    // 2. Search: pick the record closest in length, preferring synced lyrics.
    if (found == null || !found.hasText) {
      final json = await _getJson(Uri.parse('$_base/search').replace(queryParameters: {
        'track_name': cleanTitle,
        'artist_name': cleanArtist,
      }));
      if (json is List) {
        found = pickBest(json.whereType<Map>().toList(), seconds > 0 ? seconds : null) ?? found;
      }
    }

    final result = (found != null && (found.hasText || found.instrumental)) ? found : null;
    _cache[key] = result;
    return result;
  }

  /// Best search result for a song [expectedSeconds] long: synced before
  /// plain, within 5 s of that length when any result is. The length can be
  /// off (a placeholder before the stream loads), so a song with no result
  /// near it still gets the best result of any length.
  @visibleForTesting
  static Lyrics? pickBest(List<Map> records, int? expectedSeconds) {
    Lyrics? best(bool Function(int? dur) accept) {
      Lyrics? pick;
      for (final r in records) {
        final lyrics = _fromRecord(r);
        if (!lyrics.hasText || !accept((r['duration'] as num?)?.round())) continue;
        if (pick == null || (lyrics.isSynced && !pick.isSynced)) pick = lyrics;
      }
      return pick;
    }

    if (expectedSeconds != null) {
      final close = best((dur) => dur != null && (dur - expectedSeconds).abs() <= 5);
      if (close != null) return close;
    }
    return best((_) => true);
  }

  static Lyrics _fromRecord(Map r) {
    final synced = r['syncedLyrics'];
    final plain = r['plainLyrics'];
    return Lyrics(
      lines: synced is String && synced.isNotEmpty ? Lyrics.parseLrc(synced) : const [],
      plainText: plain is String && plain.trim().isNotEmpty ? plain : null,
      instrumental: r['instrumental'] == true,
    );
  }

  /// Decoded JSON, or null for 404 (not found).
  Future<Object?> _getJson(Uri uri) async {
    final http.Response res;
    try {
      res = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
    } catch (e) {
      developer.log('Lyrics request failed: $e', name: 'Lyrics');
      throw LyricsLookupException('Could not reach the lyrics service');
    }
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw LyricsLookupException('Lyrics service returned ${res.statusCode}');
    }
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw const LyricsLookupException('Lyrics service sent an unreadable reply');
    }
  }

  void dispose() => _client.close();
}
