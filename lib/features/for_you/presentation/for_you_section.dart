import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/symphony_theme.dart';
import '../../../core/widgets/hover_widgets.dart';
import '../../../core/widgets/motion.dart';
import '../../audio_player/presentation/controllers/audio_player_providers.dart';
import '../../audio_player/presentation/controllers/navigation_history_provider.dart';
import '../../audio_player/presentation/widgets/spotify_playlist_card.dart';
import '../../playlist_import/domain/entities/spotify_playlist.dart';
import '../domain/recap.dart';
import 'for_you_providers.dart';
import 'recap_screen.dart';

/// Home shelf: mixes from what the user plays (On Repeat, Daily Mixes,
/// Discover Weekly, …), opened like any playlist.
class MadeForYouShelf extends ConsumerWidget {
  const MadeForYouShelf({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = ref.watch(localMixesProvider);
    final online = ref.watch(madeForYouProvider);
    final accent = ref.watch(accentThemeProvider);
    final handler = ref.read(audioHandlerProvider);
    final mixes = [...local, ...?online.valueOrNull];
    final loading = online.isLoading && mixes.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Made for you',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.4),
              ),
            ),
            IconButton(
              tooltip: 'Refresh mixes',
              onPressed: online.isLoading ? null : () => ref.read(madeForYouProvider.notifier).refresh(force: true),
              icon: const Icon(Icons.refresh_rounded, color: SymphonyTheme.textSecondary, size: 22),
            ),
          ],
        ),
        const Text(
          'Mixes from what you play, new every day',
          style: TextStyle(fontSize: 13, color: SymphonyTheme.textSecondary),
        ),
        const SizedBox(height: 16),
        if (loading)
          const _ShelfPlaceholder()
        else if (mixes.isEmpty)
          const _NoMixesYet()
        else
          SizedBox(
            height: 275,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: mixes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final mix = mixes[index];
                return SizedBox(
                  width: 185,
                  child: StaggeredEntrance(
                    index: index,
                    child: PressLift(
                      child: SpotifyPlaylistCard(
                        playlist: mix,
                        accent: accent,
                        onTap: () => _open(ref, mix),
                        onPlay: () => handler.playQueue(mix.tracks),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  static void _open(WidgetRef ref, SpotifyPlaylist mix) {
    ref.read(activePlaylistProvider.notifier).state = mix;
    ref.read(navigationHistoryProvider.notifier).record('home', mix);
  }
}

class _ShelfPlaceholder extends StatelessWidget {
  const _ShelfPlaceholder();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 275,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, __) => Container(
          width: 185,
          decoration: BoxDecoration(color: SymphonyTheme.card, borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class _NoMixesYet extends StatelessWidget {
  const _NoMixesYet();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: SymphonyTheme.card, borderRadius: BorderRadius.circular(8)),
      child: const Row(
        children: [
          Icon(Icons.auto_awesome_rounded, color: SymphonyTheme.textSecondary, size: 28),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Play a few songs and your mixes will show up here. The more you listen, the better they get.',
              style: TextStyle(color: SymphonyTheme.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Home banner leading to the user's recap, once there's listening to
/// look back on. Brings its own space below.
class RecapBanner extends ConsumerWidget {
  const RecapBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(listeningHistoryProvider);
    final years = Recap.yearsIn(log);
    if (years.isEmpty) return const SizedBox.shrink();
    final year = years.first;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: HoverBuilder(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => RecapScreen(initialYear: year)),
        ),
        builder: (context, hovered) => AnimatedScale(
          scale: hovered ? 1.01 : 1,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: SymphonyTheme.recapGradients.first,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_graph_rounded, color: Colors.white, size: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your $year Recap',
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Your top songs, artists and minutes, by year and month',
                        style: TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
