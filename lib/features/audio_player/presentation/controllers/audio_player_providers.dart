import 'dart:convert';
import 'dart:developer' as developer;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/curated_playlists.dart';
import '../../../../core/theme/symphony_theme.dart';
import '../../../metadata_search/data/services/artwork_resolver_service.dart';
import '../../../metadata_search/data/services/search_service.dart';
import '../../../playlist_import/data/services/spotify_embed_scraper_service.dart';
import '../../../playlist_import/data/services/universal_playlist_importer_service.dart';
import '../../../playlist_import/domain/entities/spotify_playlist.dart';
import '../../../settings/presentation/controllers/personalization_provider.dart';
import '../../data/services/symphony_audio_handler.dart';
import '../../domain/entities/track.dart';

/// Symphony Brand & User Accent Theme Provider (Defaults to signature Symphony Violet #8B5CF6)
final accentThemeProvider = StateProvider<SymphonyAccent>((ref) => SymphonyTheme.violet);

/// Global provider for the Symphony AudioHandler instance
final audioHandlerProvider = Provider<SymphonyAudioHandler>((ref) {
  throw UnimplementedError('audioHandlerProvider must be overridden with the initialized instance');
});

/// Stream provider for reactive playback state changes (playing, buffering, position)
final playbackStateStreamProvider = StreamProvider<PlaybackState>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.playbackState;
});

/// Stream provider for current active media item (title, artist, artwork)
final currentMediaItemStreamProvider = StreamProvider<MediaItem?>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.mediaItem;
});

/// Stream provider for current queue index
final currentQueueIndexStreamProvider = StreamProvider<int>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.currentIndexStream;
});

/// Stream provider for active queue tracks
final currentQueueListStreamProvider = StreamProvider<List<Track>>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.playlistQueueStream;
});

/// Provider for the shared high-resolution ArtworkResolverService instance
final artworkResolverProvider = Provider<ArtworkResolverService>((ref) {
  final service = ArtworkResolverService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for the unauthenticated Spotify Embed Scraper
final spotifyScraperProvider = Provider<SpotifyEmbedScraperService>((ref) {
  final resolver = ref.watch(artworkResolverProvider);
  final service = SpotifyEmbedScraperService(artworkResolver: resolver);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for multi-source playlist importing (Spotify, YouTube, Deezer, Apple Music, Smart Mix)
final universalPlaylistImporterProvider = Provider<UniversalPlaylistImporterService>((ref) {
  final resolver = ref.watch(artworkResolverProvider);
  final spotify = ref.watch(spotifyScraperProvider);
  final service = UniversalPlaylistImporterService(
    artworkResolver: resolver,
    spotifyScraper: spotify,
  );
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for unauthenticated iTunes / Deezer search
final searchServiceProvider = Provider<SearchService>((ref) {
  final service = SearchService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// StateNotifier for managing imported Spotify playlists with offline persistence unique to each user/instance
class ImportedPlaylistsNotifier extends StateNotifier<List<SpotifyPlaylist>> {
  static const _localPlaylistsKey = 'symphony_user_playlists';
  final http.Client _httpClient = http.Client();
  String? _instanceId;

  ImportedPlaylistsNotifier() : super(CuratedPlaylists.all) {
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    // 1. Immediately load from local SharedPreferences for fast offline rendering
    await _loadFromLocalPrefs();

    // 2. Retrieve persistent instance ID
    try {
      _instanceId = await PersonalizationNotifier.getOrCreateInstanceId();
    } catch (_) {}

    // 3. Background sync with instance-isolated server cache
    if (_instanceId != null && _instanceId!.isNotEmpty) {
      await _syncWithServer();
    }
  }

  Future<void> _loadFromLocalPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_localPlaylistsKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final list = jsonDecode(jsonStr);
        if (list is List) {
          final loaded = <SpotifyPlaylist>[];
          for (final item in list) {
            if (item is Map) {
              try {
                loaded.add(SpotifyPlaylist.fromJson(Map<String, dynamic>.from(item)));
              } catch (e) {
                developer.log('Error parsing cached playlist: $e', name: 'PlaylistStore');
              }
            }
          }
          if (loaded.isNotEmpty) {
            final currentAdded = state.where((p) => !CuratedPlaylists.all.any((c) => c.id == p.id)).toList();
            final merged = <SpotifyPlaylist>[...currentAdded];
            for (final p in loaded) {
              if (!merged.any((existing) => existing.id == p.id)) {
                merged.add(p);
              }
            }
            final existingIds = merged.map((p) => p.id).toSet();
            final missingCurated = CuratedPlaylists.all.where((c) => !existingIds.contains(c.id)).toList();
            state = [...merged, ...missingCurated];
            return;
          }
        }
      }
      if (state.isEmpty) {
        state = CuratedPlaylists.all;
      }
      await _saveToLocalPrefs();
    } catch (e, st) {
      developer.log('Error loading playlists from local prefs: $e', error: e, stackTrace: st, name: 'PlaylistStore');
    }
  }

  List<String> _getCandidateServerOrigins() {
    final origins = <String>[];
    if (kIsWeb) {
      try {
        final origin = Uri.base.origin;
        if (origin.isNotEmpty && !origin.startsWith('null')) {
          origins.add(origin);
        }
      } catch (_) {}
    } else {
      origins.addAll([
        'https://symphony.jettimothycerezo.dev',
        'http://192.168.1.57:8080',
        'http://localhost:8080',
        'http://127.0.0.1:8080',
      ]);
    }
    return origins;
  }

  Future<void> _syncWithServer() async {
    final instId = _instanceId;
    if (instId == null || instId.isEmpty) return;

    final origins = _getCandidateServerOrigins();
    for (final origin in origins) {
      try {
        final uri = Uri.parse('$origin/api/playlists?instanceId=$instId');
        final res = await _httpClient.get(uri).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          if (decoded is List && decoded.isNotEmpty) {
            final serverPlaylists = <SpotifyPlaylist>[];
            for (final item in decoded) {
              if (item is Map) {
                try {
                  serverPlaylists.add(SpotifyPlaylist.fromJson(Map<String, dynamic>.from(item)));
                } catch (_) {}
              }
            }
            if (serverPlaylists.isNotEmpty) {
              final merged = <SpotifyPlaylist>[...state];
              bool modified = false;
              for (final sp in serverPlaylists) {
                final idx = merged.indexWhere((p) => p.id == sp.id);
                if (idx == -1) {
                  merged.insert(0, sp);
                  modified = true;
                }
              }
              if (modified) {
                state = merged;
                await _saveToLocalPrefs();
              }
              return;
            }
          }
          final customPlaylists = state.where((p) => !CuratedPlaylists.all.any((c) => c.id == p.id)).toList();
          if (customPlaylists.isNotEmpty) {
            await _saveToServer(customPlaylists);
          }
          return;
        }
      } catch (e) {
        developer.log('Server sync failed on $origin: $e', name: 'PlaylistStore');
      }
    }
  }

  Future<void> _saveToServer(List<SpotifyPlaylist> playlists) async {
    final instId = _instanceId ?? await PersonalizationNotifier.getOrCreateInstanceId();
    final origins = _getCandidateServerOrigins();
    final body = jsonEncode(playlists.map((p) => p.toJson()).toList());

    for (final origin in origins) {
      try {
        final uri = Uri.parse('$origin/api/playlists?instanceId=$instId');
        final res = await _httpClient.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body,
        ).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          developer.log('Successfully backed up ${playlists.length} playlists to instance $instId on server $origin', name: 'PlaylistStore');
          break;
        }
      } catch (e) {
        developer.log('Failed to backup playlists to server $origin: $e', name: 'PlaylistStore');
      }
    }
  }

  Future<void> _saveToLocalPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listJson = state.map((p) => p.toJson()).toList();
      await prefs.setString(_localPlaylistsKey, jsonEncode(listJson));
    } catch (e) {
      developer.log('Error saving playlists to local prefs: $e', name: 'PlaylistStore');
    }
  }

  Future<void> addPlaylist(SpotifyPlaylist playlist) async {
    state = [
      playlist,
      ...state.where((p) => p.id != playlist.id),
    ];
    await _saveToLocalPrefs();

    final customPlaylists = state.where((p) => !CuratedPlaylists.all.any((c) => c.id == p.id)).toList();
    _saveToServer(customPlaylists);
  }

  Future<void> removePlaylist(String playlistId) async {
    state = state.where((p) => p.id != playlistId).toList();
    await _saveToLocalPrefs();

    final customPlaylists = state.where((p) => !CuratedPlaylists.all.any((c) => c.id == p.id)).toList();
    _saveToServer(customPlaylists);
  }

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }
}

final importedPlaylistsProvider =
    StateNotifierProvider<ImportedPlaylistsNotifier, List<SpotifyPlaylist>>((ref) {
  return ImportedPlaylistsNotifier();
});

/// StateProvider holding the currently viewed Spotify Playlist
final activePlaylistProvider = StateProvider<SpotifyPlaylist?>((ref) => null);

/// Active navigation tab: 'home' | 'search' | 'library'
final activeNavTabProvider = StateProvider<String>((ref) => 'home');

/// Active search query string
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Async provider for live search results
final searchResultsProvider = FutureProvider<List<Track>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) return [];

  final searchService = ref.watch(searchServiceProvider);
  return searchService.searchTracks(query);
});
