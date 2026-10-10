import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/curated_playlists.dart';
import '../../../../core/layout/breakpoints.dart';
import '../../../metadata_search/presentation/views/search_view.dart';
import '../../../playlist_import/domain/entities/spotify_playlist.dart';
import '../controllers/audio_player_providers.dart';
import '../controllers/navigation_history_provider.dart';
import '../desktop/desktop_shell.dart';
import '../mobile/mobile_shell.dart';
import 'sections/home_section.dart';
import 'sections/library_section.dart';
import 'sections/playlist_section.dart';

/// Root player screen (thin router).
///
/// Owns navigation-history recording, track pre-warming and the Home filter
/// selection, picks the active tab's content, and hands it to
/// [DesktopShell] or [MobileShell] depending on [Breakpoints].
class SymphonyPlayerScreen extends ConsumerStatefulWidget {
  final bool isWebDemoMode;
  const SymphonyPlayerScreen({super.key, this.isWebDemoMode = false});

  @override
  ConsumerState<SymphonyPlayerScreen> createState() => _SymphonyPlayerScreenState();
}

class _SymphonyPlayerScreenState extends ConsumerState<SymphonyPlayerScreen> {
  String _homeFilter = 'all'; // 'all' | 'music' | 'downloaded'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDefaultPlaylist());
  }

  Future<void> _initDefaultPlaylist() async {
    final active = ref.read(activePlaylistProvider);
    ref.read(navigationHistoryProvider.notifier).record('home', active);

    // Proactively pre-warm top starter tracks so pressing Play starts in < 300ms
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (!isTest) {
      try {
        final handler = ref.read(audioHandlerProvider);
        final topTracks = CuratedPlaylists.todaysTopHits.tracks.take(4).toList();
        handler.preloadTracks(topTracks, count: 4);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(activeNavTabProvider, (prev, next) {
      if (prev != next) {
        final p = ref.read(activePlaylistProvider);
        ref.read(navigationHistoryProvider.notifier).record(next, p);
      }
    });

    ref.listen<SpotifyPlaylist?>(activePlaylistProvider, (prev, next) {
      if (prev?.id != next?.id) {
        final tab = ref.read(activeNavTabProvider);
        ref.read(navigationHistoryProvider.notifier).record(tab, next);

        // Pre-warm top tracks of the selected playlist
        final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
        if (!isTest && next != null && next.tracks.isNotEmpty) {
          try {
            final handler = ref.read(audioHandlerProvider);
            handler.preloadTracks(next.tracks, count: 2);
          } catch (_) {}
        }
      }
    });

    final activePlaylist = ref.watch(activePlaylistProvider);
    final activeTab = ref.watch(activeNavTabProvider);
    final mediaItemAsync = ref.watch(currentMediaItemStreamProvider);
    final playbackStateAsync = ref.watch(playbackStateStreamProvider);

    final mediaItem = mediaItemAsync.asData?.value;
    final playbackState = playbackStateAsync.asData?.value;
    final isPlaying = playbackState?.playing ?? false;
    final isBuffering = playbackState?.processingState == AudioProcessingState.buffering ||
        playbackState?.processingState == AudioProcessingState.loading;

    final isDesktop = Breakpoints.isDesktop(context);
    final content = _buildCurrentTabContent(activeTab, activePlaylist, mediaItem, isPlaying, isBuffering, isDesktop);

    if (isDesktop) {
      return DesktopShell(content: content);
    }
    return MobileShell(activeTab: activeTab, content: content);
  }

  Widget _buildCurrentTabContent(
    String activeTab,
    SpotifyPlaylist? activePlaylist,
    MediaItem? mediaItem,
    bool isPlaying,
    bool isBuffering,
    bool isDesktop,
  ) {
    if (activeTab == 'search') {
      return const SearchView();
    }

    if (activeTab == 'library') {
      return LibrarySection(isDesktop: isDesktop);
    }

    // Default 'home' tab
    if (activePlaylist == null) {
      return HomeSection(
        isDesktop: isDesktop,
        mediaItem: mediaItem,
        isPlaying: isPlaying,
        isBuffering: isBuffering,
        homeFilter: _homeFilter,
        onHomeFilterChanged: (value) => setState(() => _homeFilter = value),
      );
    }

    return PlaylistSection(
      playlist: activePlaylist,
      mediaItem: mediaItem,
      isPlaying: isPlaying,
      isBuffering: isBuffering,
      isDesktop: isDesktop,
    );
  }
}
