import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/symphony_theme.dart';
import '../../../../playlist_import/domain/entities/spotify_playlist.dart';
import '../../controllers/audio_player_providers.dart';
import '../../controllers/offline_provider.dart';
import '../../desktop/desktop_playlist_hero.dart';
import '../../mobile/mobile_playlist_hero.dart';
import '../../widgets/spotify_track_row.dart';

/// Playlist detail: hero header (desktop or mobile variant) + track list.
class PlaylistSection extends ConsumerWidget {
  final SpotifyPlaylist playlist;
  final MediaItem? mediaItem;
  final bool isPlaying;
  final bool isBuffering;
  final bool isDesktop;

  const PlaylistSection({
    super.key,
    required this.playlist,
    required this.mediaItem,
    required this.isPlaying,
    required this.isBuffering,
    required this.isDesktop,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.read(audioHandlerProvider);
    final offlineState = ref.watch(offlineProvider);
    final offlineNotifier = ref.read(offlineProvider.notifier);
    final accent = ref.watch(accentThemeProvider);

    final isPlaylistActive = playlist.tracks.any((t) => t.title == mediaItem?.title && t.artist == mediaItem?.artist);
    final isThisPlaying = isPlaylistActive && isPlaying;
    final isPlaylistDownloaded = offlineState.isPlaylistDownloaded(playlist);
    final isPlaylistDownloading = offlineState.isPlaylistDownloading(playlist.id);

    return CustomScrollView(
      slivers: [
        // Top Bar & Hero Header
        SliverToBoxAdapter(
          child: isDesktop
              ? DesktopPlaylistHero(
                  playlist: playlist,
                  accent: accent,
                  isThisPlaying: isThisPlaying,
                  isPlaylistActive: isPlaylistActive,
                  isPlaylistDownloaded: isPlaylistDownloaded,
                  isPlaylistDownloading: isPlaylistDownloading,
                  handler: handler,
                  offlineNotifier: offlineNotifier,
                )
              : MobilePlaylistHero(
                  playlist: playlist,
                  accent: accent,
                  isThisPlaying: isThisPlaying,
                  isPlaylistActive: isPlaylistActive,
                  isPlaylistDownloaded: isPlaylistDownloaded,
                  isPlaylistDownloading: isPlaylistDownloading,
                  handler: handler,
                  offlineNotifier: offlineNotifier,
                ),
        ),

        // Track Table Header (Desktop Only)
        if (isDesktop)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 32,
                    child: Text(
                      '#',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: SymphonyTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const SizedBox(width: 40),
                  const SizedBox(width: 14),
                  const Expanded(
                    flex: 4,
                    child: Text(
                      'Title',
                      style: TextStyle(color: SymphonyTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    flex: 3,
                    child: Text(
                      'Album',
                      style: TextStyle(color: SymphonyTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 48),
                  const SizedBox(
                    width: 44,
                    child: Icon(Icons.access_time_outlined, size: 16, color: SymphonyTheme.textSecondary),
                  ),
                  const SizedBox(width: 32),
                ],
              ),
            ),
          ),

        if (isDesktop)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.0),
              child: Divider(color: SymphonyTheme.divider, height: 1),
            ),
          ),

        // Track List Rows
        SliverPadding(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 24 : 8,
            vertical: 8,
          ),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, index) {
                final track = playlist.tracks[index];
                final isCurrent = mediaItem?.title == track.title && mediaItem?.artist == track.artist;
                final isDownloaded = offlineState.isTrackDownloaded(track);
                final isDownloading = offlineState.isTrackDownloading(track.id);

                return SpotifyTrackRow(
                  index: index,
                  track: track,
                  isPlaying: isPlaying && !isBuffering,
                  isBuffering: isCurrent && isBuffering,
                  isCurrent: isCurrent,
                  isDownloaded: isDownloaded,
                  isDownloading: isDownloading,
                  onDownload: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.showSnackBar(
                      SnackBar(
                        backgroundColor: SymphonyTheme.card,
                        content: Text('Downloading "${track.title}" for offline playback...'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                    final ok = await offlineNotifier.downloadTrack(track);
                    if (ok && context.mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          backgroundColor: SymphonyTheme.card,
                          content: Text('Saved "${track.title}" offline!'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  onTap: () async {
                    try {
                      if (isCurrent) {
                        if (isPlaying) {
                          await handler.pause();
                        } else {
                          await handler.play();
                        }
                      } else {
                        await handler.playQueue(playlist.tracks, startIndex: index);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: SymphonyTheme.card,
                            content: Text('Playback error: $e', style: const TextStyle(color: Colors.redAccent)),
                          ),
                        );
                      }
                    }
                  },
                );
              },
              childCount: playlist.tracks.length,
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: SizedBox(height: isDesktop ? 40 : 110),
        ),
      ],
    );
  }
}
