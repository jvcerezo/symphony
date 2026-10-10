import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../playlist_import/domain/entities/spotify_playlist.dart';
import '../../data/services/offline/offline_download_service.dart';
import '../../domain/entities/track.dart';
import '../../../../core/config/server_config.dart';
import 'audio_player_providers.dart';

class DownloadProgress {
  final String title;
  final int current;
  final int total;
  final bool isCompleted;
  final String? currentTrackTitle;
  final bool isError;
  final String? errorMessage;

  const DownloadProgress({
    required this.title,
    required this.current,
    required this.total,
    this.isCompleted = false,
    this.currentTrackTitle,
    this.isError = false,
    this.errorMessage,
  });

  int get remaining => (total - current).clamp(0, total);
  double get percentage => total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;
}

class OfflineState {
  final Set<String> cachedKeys;
  final Set<String> downloadingTrackIds;
  final Set<String> downloadingPlaylistIds;
  final DownloadProgress? activeProgress;

  const OfflineState({
    this.cachedKeys = const {},
    this.downloadingTrackIds = const {},
    this.downloadingPlaylistIds = const {},
    this.activeProgress,
  });

  OfflineState copyWith({
    Set<String>? cachedKeys,
    Set<String>? downloadingTrackIds,
    Set<String>? downloadingPlaylistIds,
    DownloadProgress? Function()? activeProgress,
  }) {
    return OfflineState(
      cachedKeys: cachedKeys ?? this.cachedKeys,
      downloadingTrackIds: downloadingTrackIds ?? this.downloadingTrackIds,
      downloadingPlaylistIds: downloadingPlaylistIds ?? this.downloadingPlaylistIds,
      activeProgress: activeProgress != null ? activeProgress() : this.activeProgress,
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

/// Downloads for offline playback.
///
/// Native (Android/Windows/…): when [deviceDownloads] is supplied, audio is
/// saved to on-device storage and `cachedKeys` reflects the local index, so
/// "downloaded" means playable with no network. Web: the server-side cache
/// (`/api/offline/*`) is used as before.
class OfflineManagerNotifier extends StateNotifier<OfflineState> {
  final http.Client _client;
  final OfflineDownloadService? _deviceDownloads;

  OfflineManagerNotifier({
    OfflineDownloadService? deviceDownloads,
    http.Client? client,
  })  : _deviceDownloads = deviceDownloads,
        _client = client ?? http.Client(),
        super(const OfflineState()) {
    refreshOfflineStatus();
  }

  bool get _useDevice => _deviceDownloads?.isSupported ?? false;

  /// Bytes used by on-device downloads (0 on web / server-cache mode).
  Future<int> deviceStorageBytes() async => _useDevice ? _deviceDownloads!.totalBytes() : 0;

  @override
  void dispose() {
    _deviceDownloads?.dispose();
    _client.close();
    super.dispose();
  }

  static Set<String> _keysFor(Track t) => {
        t.id,
        t.id.replaceAll('spotify:track:', '').trim(),
        '${t.artist.toLowerCase()} - ${t.title.toLowerCase()}'.trim(),
      };

  /// Downloads one track via the device store or the server cache. Returns
  /// false on a non-200 server reply; throws on transport/storage errors.
  Future<bool> _downloadOne(Track t, Duration serverTimeout) async {
    if (_useDevice) {
      await _deviceDownloads!.download(t);
      return true;
    }
    final res = await _client.post(
      Uri.parse('${_getServerOrigin()}/api/offline/download'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'track': {
          'id': t.id,
          'title': t.title,
          'artist': t.artist,
          'durationMs': t.expectedDuration?.inMilliseconds ?? 200000,
        },
      }),
    ).timeout(serverTimeout);
    return res.statusCode == 200;
  }

  /// Removes a single on-device download. Returns bytes freed (0 on web).
  Future<int> removeDownloadedTrack(Track track) async {
    if (!_useDevice) return 0;
    final freed = await _deviceDownloads!.remove(track);
    state = state.copyWith(cachedKeys: Set<String>.from(state.cachedKeys)..removeAll(_keysFor(track)));
    await refreshOfflineStatus();
    return freed;
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  String _getServerOrigin() => ServerConfig.primaryOrigin();

  void dismissProgress() {
    state = state.copyWith(activeProgress: () => null);
  }

  Future<void> refreshOfflineStatus() async {
    if (_useDevice) {
      try {
        final entries = await _deviceDownloads!.entries();
        if (!mounted) return;
        state = state.copyWith(cachedKeys: {for (final e in entries) ...e.matchKeys});
      } catch (_) {}
      return;
    }

    final candidateOrigins = ServerConfig.candidateOrigins();

    for (final origin in candidateOrigins) {
      try {
        final res = await _client.get(Uri.parse('$origin/api/offline/status')).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final vids = (data['cachedVideoIds'] as List<dynamic>? ?? []).map((e) => e.toString()).toSet();
          final keys = (data['cachedKeys'] as List<dynamic>? ?? []).map((e) => e.toString()).toSet();
          final allKeys = {...state.cachedKeys, ...vids, ...keys};
          state = state.copyWith(cachedKeys: allKeys);
          break;
        }
      } catch (_) {}
    }
  }

  Future<bool> downloadTrack(Track track) async {
    final trackId = track.id;
    state = state.copyWith(
      downloadingTrackIds: {...state.downloadingTrackIds, trackId},
      activeProgress: () => DownloadProgress(
        title: track.title,
        current: 0,
        total: 1,
        currentTrackTitle: track.title,
      ),
    );

    try {
      if (await _downloadOne(track, const Duration(seconds: 45))) {
        final norm = '${track.artist.toLowerCase()} - ${track.title.toLowerCase()}'.trim();
        final cleanId = track.id.replaceAll('spotify:track:', '').trim();
        final updatedKeys = {...state.cachedKeys, track.id, cleanId, norm};
        state = state.copyWith(
          cachedKeys: updatedKeys,
          activeProgress: () => DownloadProgress(
            title: track.title,
            current: 1,
            total: 1,
            isCompleted: true,
            currentTrackTitle: track.title,
          ),
        );
        await refreshOfflineStatus();
        Future.delayed(const Duration(milliseconds: 3000), () {
          if (state.activeProgress?.isCompleted == true && state.activeProgress?.title == track.title) {
            dismissProgress();
          }
        });
        return true;
      }
    } catch (e) {
      state = state.copyWith(
        activeProgress: () => DownloadProgress(
          title: track.title,
          current: 0,
          total: 1,
          isError: true,
          errorMessage: 'Download failed: $e',
        ),
      );
      Future.delayed(const Duration(milliseconds: 4000), () => dismissProgress());
    } finally {
      final updatedDownloading = Set<String>.from(state.downloadingTrackIds)..remove(trackId);
      state = state.copyWith(downloadingTrackIds: updatedDownloading);
    }
    return false;
  }

  Future<bool> downloadPlaylist(SpotifyPlaylist playlist) async {
    final playlistId = playlist.id;
    final tracks = playlist.tracks;
    if (tracks.isEmpty) return false;

    state = state.copyWith(
      downloadingPlaylistIds: {...state.downloadingPlaylistIds, playlistId},
      activeProgress: () => DownloadProgress(
        title: playlist.title,
        current: 0,
        total: tracks.length,
        currentTrackTitle: tracks.first.title,
      ),
    );

    int completedCount = 0;

    try {
      for (int i = 0; i < tracks.length; i++) {
        final t = tracks[i];
        state = state.copyWith(
          activeProgress: () => DownloadProgress(
            title: playlist.title,
            current: completedCount,
            total: tracks.length,
            currentTrackTitle: t.title,
          ),
        );

        try {
          if (await _downloadOne(t, const Duration(seconds: 40))) {
            completedCount++;
            final norm = '${t.artist.toLowerCase()} - ${t.title.toLowerCase()}'.trim();
            final cleanId = t.id.replaceAll('spotify:track:', '').trim();
            state = state.copyWith(
              cachedKeys: {...state.cachedKeys, t.id, cleanId, norm},
              activeProgress: () => DownloadProgress(
                title: playlist.title,
                current: completedCount,
                total: tracks.length,
                currentTrackTitle: t.title,
              ),
            );
          }
        } catch (_) {}
      }

      state = state.copyWith(
        activeProgress: () => DownloadProgress(
          title: playlist.title,
          current: completedCount,
          total: tracks.length,
          isCompleted: true,
        ),
      );

      await refreshOfflineStatus();
      Future.delayed(const Duration(milliseconds: 4000), () {
        if (state.activeProgress?.isCompleted == true && state.activeProgress?.title == playlist.title) {
          dismissProgress();
        }
      });
      return completedCount > 0;
    } catch (e) {
      state = state.copyWith(
        activeProgress: () => DownloadProgress(
          title: playlist.title,
          current: completedCount,
          total: tracks.length,
          isError: true,
          errorMessage: 'Error during playlist download: $e',
        ),
      );
      Future.delayed(const Duration(milliseconds: 4000), () => dismissProgress());
    } finally {
      final updatedDownloading = Set<String>.from(state.downloadingPlaylistIds)..remove(playlistId);
      state = state.copyWith(downloadingPlaylistIds: updatedDownloading);
    }
    return false;
  }

  Future<String?> removeDownloadedPlaylist(SpotifyPlaylist playlist) async {
    final playlistId = playlist.id;
    final tracks = playlist.tracks;
    if (tracks.isEmpty) return null;

    if (_useDevice) {
      try {
        var freed = 0;
        for (final t in tracks) {
          freed += await _deviceDownloads!.remove(t);
        }
        state = state.copyWith(
          cachedKeys: Set<String>.from(state.cachedKeys)..removeAll(tracks.expand(_keysFor)),
        );
        await refreshOfflineStatus();
        return _formatBytes(freed);
      } catch (_) {
        return null;
      }
    }

    try {
      final origin = _getServerOrigin();
      final tracksPayload = tracks.map((t) => {
        'id': t.id,
        'title': t.title,
        'artist': t.artist,
      }).toList();

      final res = await _client.post(
        Uri.parse('$origin/api/offline/delete-playlist'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'playlistId': playlistId,
          'tracks': tracksPayload,
        }),
      ).timeout(const Duration(seconds: 15));

      // Remove keys from local cachedKeys set
      final keysToRemove = <String>{};
      for (final t in tracks) {
        keysToRemove.add(t.id);
        keysToRemove.add(t.id.replaceAll('spotify:track:', '').trim());
        keysToRemove.add('${t.artist.toLowerCase()} - ${t.title.toLowerCase()}'.trim());
      }
      final updatedKeys = Set<String>.from(state.cachedKeys)..removeAll(keysToRemove);
      state = state.copyWith(cachedKeys: updatedKeys);

      String freedFormatted = 'offline storage';
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        freedFormatted = data['freedFormatted'] as String? ?? 'offline storage';
      }

      await refreshOfflineStatus();
      return freedFormatted;
    } catch (_) {
      return null;
    }
  }
}

final offlineProvider = StateNotifierProvider<OfflineManagerNotifier, OfflineState>((ref) {
  return OfflineManagerNotifier(
    deviceDownloads: kIsWeb
        ? null
        : OfflineDownloadService(
            // Share the player's resolver (and its in-memory cache).
            resolve: (track) => ref.read(audioHandlerProvider).streamResolver.resolveBestAudioStream(track),
          ),
  );
});
