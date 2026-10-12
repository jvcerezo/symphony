import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../audio_player/domain/entities/track.dart';
import '../../domain/entities/spotify_playlist.dart';

/// Reads a public YouTube playlist from its web page. YouTube now renders
/// playlist entries as `lockupViewModel`s, which youtube_explode_dart 3.1
/// doesn't parse (it returns the title but no videos), so this reads the
/// page's `ytInitialData` directly. The page carries the first 100 videos.
class YouTubePlaylistPage {
  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  static Future<SpotifyPlaylist?> fetch(String playlistId, {http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final res = await c
          .get(Uri.parse('https://www.youtube.com/playlist?list=$playlistId'), headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      return parse(utf8.decode(res.bodyBytes), playlistId: playlistId);
    } finally {
      if (client == null) c.close();
    }
  }

  @visibleForTesting
  static SpotifyPlaylist? parse(String html, {required String playlistId}) {
    final m = RegExp(r'var ytInitialData = (\{.*?\});</script>', dotAll: true).firstMatch(html);
    if (m == null) return null;
    final Object? data;
    try {
      data = jsonDecode(m.group(1)!);
    } catch (_) {
      return null;
    }

    final tracks = <Track>[];
    final seen = <String>{};
    void walk(Object? node) {
      if (node is Map) {
        final lockup = node['lockupViewModel'];
        if (lockup is Map) {
          final track = _trackFrom(lockup);
          if (track != null && seen.add(track.id)) tracks.add(track);
        }
        for (final v in node.values) {
          walk(v);
        }
      } else if (node is List) {
        for (final v in node) {
          walk(v);
        }
      }
    }

    walk(data);
    if (tracks.isEmpty) return null;

    final meta = (data is Map ? data['metadata'] : null);
    final info = meta is Map ? meta['playlistMetadataRenderer'] : null;
    final title = (info is Map ? info['title'] as String? : null) ?? 'YouTube Playlist';
    final description = info is Map ? info['description'] as String? : null;

    return SpotifyPlaylist(
      id: 'yt_$playlistId',
      title: title,
      description: (description == null || description.trim().isEmpty) ? 'Imported from YouTube' : description,
      coverUrl: tracks.first.artworkUri?.toString(),
      ownerName: 'YouTube',
      source: 'YouTube',
      tracks: tracks,
    );
  }

  static Track? _trackFrom(Map lockup) {
    if (lockup['contentType'] != 'LOCKUP_CONTENT_TYPE_VIDEO') return null;
    final videoId = lockup['contentId'];
    if (videoId is! String || videoId.isEmpty) return null;

    final meta = lockup['metadata'] is Map ? lockup['metadata']['lockupMetadataViewModel'] : null;
    if (meta is! Map) return null;
    final title = meta['title'] is Map ? meta['title']['content'] as String? : null;
    if (title == null || title.isEmpty) return null;

    String? channel;
    final inner = meta['metadata'];
    final content = inner is Map ? inner['contentMetadataViewModel'] : null;
    final rows = content is Map ? content['metadataRows'] : null;
    if (rows is List && rows.isNotEmpty && rows.first is Map) {
      final parts = (rows.first as Map)['metadataParts'];
      if (parts is List && parts.isNotEmpty && parts.first is Map) {
        final text = (parts.first as Map)['text'];
        channel = text is Map ? text['content'] as String? : null;
      }
    }

    return Track(
      id: 'yt_$videoId',
      title: title,
      artist: cleanChannel(channel ?? 'YouTube'),
      expectedDuration: _badgeDuration(lockup),
      artworkUri: Uri.parse('https://i.ytimg.com/vi/$videoId/hqdefault.jpg'),
    );
  }

  /// "Ashanti - Topic" / "AshantiVEVO" → "Ashanti".
  static String cleanChannel(String channel) =>
      channel.replaceAll(RegExp(r'\s*-\s*Topic$'), '').replaceAll(RegExp(r'VEVO$'), '').trim();

  /// The "3:48" length badge on the thumbnail.
  static Duration? _badgeDuration(Map lockup) {
    String? text;
    void walk(Object? node) {
      if (text != null) return;
      if (node is Map) {
        final badge = node['thumbnailBadgeViewModel'];
        if (badge is Map && badge['text'] is String) {
          text = badge['text'] as String;
          return;
        }
        for (final v in node.values) {
          walk(v);
        }
      } else if (node is List) {
        for (final v in node) {
          walk(v);
        }
      }
    }

    walk(lockup['contentImage']);
    return parseClock(text);
  }

  /// "3:48" or "1:02:03" → Duration; null for anything else.
  static Duration? parseClock(String? text) {
    if (text == null || !RegExp(r'^\d+(:\d{2}){1,2}$').hasMatch(text.trim())) return null;
    final parts = text.trim().split(':').map(int.parse).toList();
    var seconds = 0;
    for (final p in parts) {
      seconds = seconds * 60 + p;
    }
    return Duration(seconds: seconds);
  }
}
