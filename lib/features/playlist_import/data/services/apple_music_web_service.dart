import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../audio_player/domain/entities/track.dart';
import '../../domain/entities/playlist_summary.dart';
import '../../domain/entities/spotify_playlist.dart';

/// Reads Apple Music's public web pages (no account or API key): playlist
/// search results and full playlists. music.apple.com renders its data
/// into a `serialized-server-data` script tag, which is parsed here.
/// Native builds only; browsers block these requests (CORS).
class AppleMusicWebService {
  static const _base = 'https://music.apple.com/us';
  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36',
    'Accept': 'text/html',
  };

  final http.Client _client;

  AppleMusicWebService({http.Client? client}) : _client = client ?? http.Client();

  /// Playlists matching [term], Apple's own editorial ones first.
  Future<List<PlaylistSummary>> searchPlaylists(String term, {int limit = 6}) async {
    final html = await _get('$_base/search?term=${Uri.encodeQueryComponent(term)}');
    return parseSearchPlaylists(html, limit: limit);
  }

  /// Loads a playlist from a music.apple.com playlist link.
  Future<SpotifyPlaylist> importPlaylist(String url) async {
    if (!isPlaylistUrl(url)) {
      throw const FormatException('That Apple Music link is not a playlist. Copy the link from a playlist page.');
    }
    final html = await _get(url.trim());
    final playlist = parsePlaylist(html, url: url.trim());
    if (playlist == null || playlist.tracks.isEmpty) {
      throw const FormatException("Couldn't read that Apple Music playlist. Make sure it's public.");
    }
    return playlist;
  }

  static bool isPlaylistUrl(String url) => RegExp(r'music\.apple\.com/.*/playlist/.*pl\.[A-Za-z0-9.-]+').hasMatch(url);

  Future<String> _get(String url) async {
    try {
      final res = await _client.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) throw http.ClientException('HTTP ${res.statusCode}', Uri.parse(url));
      return utf8.decode(res.bodyBytes);
    } catch (e) {
      developer.log('Apple Music request failed: $e', name: 'AppleMusic');
      rethrow;
    }
  }

  /// The page's embedded data, or null when the page doesn't have it.
  @visibleForTesting
  static Object? serverData(String html) {
    final m = RegExp(r'<script[^>]*id="serialized-server-data"[^>]*>(.*?)</script>', dotAll: true).firstMatch(html);
    if (m == null) return null;
    try {
      return jsonDecode(m.group(1)!);
    } catch (_) {
      return null;
    }
  }

  /// Artwork URL at [size] from Apple's `{w}x{h}…{f}` template.
  static String? artworkUrl(Object? artwork, {int size = 600}) {
    final url = artwork is Map ? (artwork['dictionary'] is Map ? artwork['dictionary']['url'] : null) : null;
    if (url is! String) return null;
    return url.replaceAll('{w}', '$size').replaceAll('{h}', '$size').replaceAll('{f}', 'jpg');
  }

  static String? _kind(Map item) {
    final cd = item['contentDescriptor'];
    return cd is Map ? cd['kind'] as String? : null;
  }

  static void _walk(Object? node, void Function(Map node) visit) {
    if (node is Map) {
      visit(node);
      for (final v in node.values) {
        _walk(v, visit);
      }
    } else if (node is List) {
      for (final v in node) {
        _walk(v, visit);
      }
    }
  }

  @visibleForTesting
  static List<PlaylistSummary> parseSearchPlaylists(String html, {int limit = 6}) {
    final data = serverData(html);
    final seen = <String>{};
    final found = <PlaylistSummary>[];
    _walk(data, (node) {
      if (_kind(node) != 'playlist' || node['title'] is! String) return;
      final cd = node['contentDescriptor'] as Map;
      final id = (cd['identifiers'] is Map ? cd['identifiers']['storeAdamID'] : null) as String?;
      final url = cd['url'] as String?;
      if (id == null || url == null || !seen.add(id)) return;
      // "Playlist · Apple Music Chill" → "Apple Music Chill"
      final subtitle = (node['subtitle'] as String?)?.split('·').last.trim();
      found.add(PlaylistSummary(
        source: PlaylistSource.appleMusic,
        id: id,
        title: node['title'] as String,
        subtitle: subtitle,
        coverUrl: artworkUrl(node['artwork']),
        link: url,
      ));
    });
    // Apple's editorial playlists ("Apple Music Chill") before user ones.
    final editorial = found.where((p) => p.subtitle?.startsWith('Apple Music') ?? false);
    final others = found.where((p) => !(p.subtitle?.startsWith('Apple Music') ?? false));
    return [...editorial, ...others].take(limit).toList();
  }

  @visibleForTesting
  static SpotifyPlaylist? parsePlaylist(String html, {required String url}) {
    final data = serverData(html);
    Map? header;
    List? items;
    _walk(data, (node) {
      final id = node['id'];
      if (id is! String || node['items'] is! List) return;
      if (header == null && id.startsWith('playlist-detail-header-section')) {
        final list = node['items'] as List;
        if (list.isNotEmpty && list.first is Map) header = list.first as Map;
      } else if (items == null && id.startsWith('track-list - ')) {
        items = node['items'] as List;
      }
    });
    final head = header;
    if (head == null || items == null) return null;

    final playlistId = RegExp(r'pl\.[A-Za-z0-9.-]+').firstMatch(url)?.group(0) ?? url;
    final title = head['title'] as String? ?? 'Apple Music Playlist';
    final curator = (head['subtitleLinks'] is List && (head['subtitleLinks'] as List).isNotEmpty)
        ? ((head['subtitleLinks'] as List).first as Map)['title'] as String?
        : null;

    final tracks = <Track>[];
    for (final item in items!) {
      if (item is! Map || _kind(item) != 'song' || item['title'] is! String) continue;
      final album = (item['tertiaryLinks'] is List && (item['tertiaryLinks'] as List).isNotEmpty)
          ? ((item['tertiaryLinks'] as List).first as Map)['title'] as String?
          : null;
      final ms = (item['duration'] as num?)?.toInt() ?? 0;
      final art = artworkUrl(item['artwork']);
      final cd = item['contentDescriptor'] as Map;
      final songId = cd['identifiers'] is Map ? cd['identifiers']['storeAdamID'] : null;
      tracks.add(Track(
        id: 'am_${songId ?? tracks.length}',
        title: item['title'] as String,
        artist: item['artistName'] as String? ?? 'Unknown Artist',
        album: album,
        expectedDuration: ms > 0 ? Duration(milliseconds: ms) : null,
        artworkUri: art == null ? null : Uri.tryParse(art),
      ));
    }

    return SpotifyPlaylist(
      id: 'am_$playlistId',
      title: title,
      description: curator == null ? null : 'Playlist by $curator',
      coverUrl: artworkUrl(head['artwork'], size: 1000),
      ownerName: curator ?? 'Apple Music',
      source: 'Apple Music',
      tracks: tracks,
    );
  }

  void dispose() => _client.close();
}
