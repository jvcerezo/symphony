import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../playlist_import/domain/entities/spotify_playlist.dart';
import '../../domain/entities/track.dart';

class OfflineState {
  final Set<String> cachedKeys;
  final Set<String> downloadingTrackIds;
  final Set<String> downloadingPlaylistIds;

  const OfflineState({
    this.cachedKeys = const {},
    this.downloadingTrackIds = const {},
    this.downloadingPlaylistIds = const {},
  });

  OfflineState copyWith({
    Set<String>? cachedKeys,
    Set<String>? downloadingTrackIds,
    Set<String>? downloadingPlaylistIds,
  }) {
    return OfflineState(
      cachedKeys: cachedKeys ?? this.cachedKeys,
      downloadingTrackIds: downloadingTrackIds ?? this.downloadingTrackIds,
      downloadingPlaylistIds: downloadingPlaylistIds ?? this.downloadingPlaylistIds,
    );
  }

  bool isTrackDownloaded(Track track) {
    final cleanId = track.id.replaceAll('spotify:track:', '').trim();
    if (cachedKeys.contains(track.id) || cachedKeys.contains(cleanId)) return true;
    final norm = '${track.artist.toLowerCase()} - ${track.title.toLowerCase()}'.trim();
    if (cachedKeys.contains(norm)) return true;
    return false;
  }

  bool isPlaylistDownloaded(SpotifyPlaylist playlist) {
    if (playlist.tracks.isEmpty) return false;
    return playlist.tracks.every((t) => isTrackDownloaded(t));
  }

  bool isTrackDownloading(String trackId) => downloadingTrackIds.contains(trackId);
  bool isPlaylistDownloading(String playlistId) => downloadingPlaylistIds.contains(playlistId);
}

class OfflineManagerNotifier extends StateNotifier<OfflineState> {
  final http.Client _client = http.Client();

  OfflineManagerNotifier() : super(const OfflineState()) {
    refreshOfflineStatus();
  }

  String _getServerOrigin() {
    if (kIsWeb) return Uri.base.origin;
    return 'http://192.168.1.57:8080';
  }

  Future<void> refreshOfflineStatus() async {
    try {
      final origin = _getServerOrigin();
      final res = await _client.get(Uri.parse('$origin/api/offline/status')).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final vids = (data['cachedVideoIds'] as List<dynamic>? ?? []).map((e) => e.toString()).toSet();
        final keys = (data['cachedKeys'] as List<dynamic>? ?? []).map((e) => e.toString()).toSet();
        final allKeys = {...state.cachedKeys, ...vids, ...keys};
        state = state.copyWith(cachedKeys: allKeys);
      }
    } catch (_) {}
  }

  Future<bool> downloadTrack(Track track) async {
    final trackId = track.id;
    state = state.copyWith(
      downloadingTrackIds: {...state.downloadingTrackIds, trackId},
    );

    try {
      final origin = _getServerOrigin();
      final res = await _client.post(
        Uri.parse('$origin/api/offline/download'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'track': {
            'id': track.id,
            'title': track.title,
            'artist': track.artist,
            'durationMs': track.expectedDuration?.inMilliseconds ?? 200000,
          },
        }),
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final norm = '${track.artist.toLowerCase()} - ${track.title.toLowerCase()}'.trim();
        final cleanId = track.id.replaceAll('spotify:track:', '').trim();
        final updatedKeys = {...state.cachedKeys, track.id, cleanId, norm};
        state = state.copyWith(cachedKeys: updatedKeys);
        await refreshOfflineStatus();
        return true;
      }
    } catch (_) {
    } finally {
      final updatedDownloading = Set<String>.from(state.downloadingTrackIds)..remove(trackId);
      state = state.copyWith(downloadingTrackIds: updatedDownloading);
    }
    return false;
  }

  Future<bool> downloadPlaylist(SpotifyPlaylist playlist) async {
    final playlistId = playlist.id;
    state = state.copyWith(
      downloadingPlaylistIds: {...state.downloadingPlaylistIds, playlistId},
    );

    try {
      final origin = _getServerOrigin();
      final tracksPayload = playlist.tracks.map((t) => {
        'id': t.id,
        'title': t.title,
        'artist': t.artist,
        'durationMs': t.expectedDuration?.inMilliseconds ?? 200000,
      }).toList();

      final res = await _client.post(
        Uri.parse('$origin/api/offline/download'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'tracks': tracksPayload}),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        for (final t in playlist.tracks) {
          final norm = '${t.artist.toLowerCase()} - ${t.title.toLowerCase()}'.trim();
          final cleanId = t.id.replaceAll('spotify:track:', '').trim();
          state = state.copyWith(cachedKeys: {...state.cachedKeys, t.id, cleanId, norm});
        }

        Future.delayed(const Duration(seconds: 3), () => refreshOfflineStatus());
        Future.delayed(const Duration(seconds: 8), () => refreshOfflineStatus());
        return true;
      }
    } catch (_) {
    } finally {
      final updatedDownloading = Set<String>.from(state.downloadingPlaylistIds)..remove(playlistId);
      state = state.copyWith(downloadingPlaylistIds: updatedDownloading);
    }
    return false;
  }
}

final offlineProvider = StateNotifierProvider<OfflineManagerNotifier, OfflineState>((ref) {
  return OfflineManagerNotifier();
});
