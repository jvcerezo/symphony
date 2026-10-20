import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../../audio_player/domain/entities/track.dart';
import '../domain/play_event.dart';

/// An artist on Deezer.
typedef DeezerArtist = ({int id, String name});

/// Deezer's public catalog API (no account): related artists, an artist's
/// top songs, artist radio and the charts. Songs come back with clean
/// titles and lengths, which is what song matching works best with.
///
/// Every call returns an empty list when Deezer can't be reached; the
/// browser build can't reach it at all (no CORS).
class DeezerCatalog {
  DeezerCatalog({http.Client? httpClient}) : _client = httpClient ?? http.Client();

  final http.Client _client;
  final Map<String, int?> _artistIds = {};

  static const _base = 'https://api.deezer.com';

  Future<Object?> _get(String path) async {
    try {
      final res = await _client.get(Uri.parse('$_base$path')).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      // Deezer reports errors with a 200 and an "error" object.
      if (body is Map && body['error'] != null) return null;
      return body;
    } catch (e) {
      developer.log('Deezer $path failed: $e', name: 'ForYou');
      return null;
    }
  }

  List<Map<String, dynamic>> _data(Object? body) {
    if (body is! Map || body['data'] is! List) return const [];
    return (body['data'] as List).whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  /// [name]'s Deezer id: the exact name match among the first results,
  /// else the top result.
  Future<int?> artistId(String name) async {
    final key = normalizeName(name);
    if (key.isEmpty) return null;
    if (_artistIds.containsKey(key)) return _artistIds[key];
    final found = _data(await _get('/search/artist?q=${Uri.encodeQueryComponent(name)}&limit=5'));
    final exact = found.where((a) => normalizeName('${a['name']}') == key);
    final pick = exact.isNotEmpty ? exact.first : (found.isNotEmpty ? found.first : null);
    final id = (pick?['id'] as num?)?.toInt();
    // Don't remember a miss caused by a dropped connection.
    if (found.isNotEmpty) _artistIds[key] = id;
    return id;
  }

  Future<List<DeezerArtist>> relatedArtists(int artistId, {int limit = 10}) async {
    return _data(await _get('/artist/$artistId/related?limit=$limit'))
        .map((a) => (id: (a['id'] as num).toInt(), name: '${a['name']}'))
        .toList();
  }

  Future<List<Track>> topTracks(int artistId, {int limit = 10}) async =>
      _tracks(await _get('/artist/$artistId/top?limit=$limit'));

  /// A mix of the artist and similar ones, like a radio station.
  Future<List<Track>> artistRadio(int artistId, {int limit = 25}) async =>
      _tracks(await _get('/artist/$artistId/radio?limit=$limit'));

  /// Most played songs on Deezer right now.
  Future<List<Track>> chart({int limit = 50}) async => _tracks(await _get('/chart/0/tracks?limit=$limit'));

  List<Track> _tracks(Object? body) => _data(body).map(trackFromJson).whereType<Track>().toList();

  /// A Deezer track object as a [Track] (id `dz_<id>`). Matched to its
  /// YouTube upload by title, artist and length when played.
  static Track? trackFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title_short'] ?? json['title'];
    final artist = json['artist'];
    if (id == null || title == null || artist is! Map) return null;
    final album = json['album'] is Map ? json['album'] as Map : const {};
    final seconds = (json['duration'] as num?)?.toInt() ?? 0;
    final cover = album['cover_xl'] ?? album['cover_big'];
    return Track(
      id: 'dz_$id',
      title: '$title',
      artist: '${artist['name']}',
      album: album['title'] == null ? null : '${album['title']}',
      expectedDuration: seconds > 0 ? Duration(seconds: seconds) : null,
      artworkUri: cover == null ? null : Uri.tryParse('$cover'),
    );
  }

  void dispose() => _client.close();
}
