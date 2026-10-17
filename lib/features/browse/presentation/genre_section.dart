import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/symphony_theme.dart';
import '../../../core/widgets/hover_widgets.dart';
import '../../audio_player/presentation/controllers/audio_player_providers.dart';
import '../../audio_player/presentation/controllers/navigation_history_provider.dart';
import '../../playlist_import/domain/entities/playlist_summary.dart';
import '../data/genre_catalog.dart';
import 'genre_providers.dart';
import '../../../core/widgets/motion.dart';

/// A genre's page: current playlists for it from Spotify, Apple Music and
/// YouTube, each loading on its own. Tapping one opens it (without adding
/// it to the library; the heart on the playlist page saves it).
class GenreSection extends ConsumerWidget {
  final Genre genre;
  final bool isDesktop;

  const GenreSection({super.key, required this.genre, required this.isDesktop});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pad = isDesktop ? 32.0 : 16.0;
    return ListView(
      padding: EdgeInsets.fromLTRB(0, 0, 0, isDesktop ? 40 : 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(pad, isDesktop ? 20 : 12, pad, 28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [genre.gradient.last.withValues(alpha: 0.85), SymphonyTheme.panel],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                tooltip: 'Back to Home',
                style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.35)),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => ref.read(activeGenreProvider.notifier).state = null,
              ),
              SizedBox(height: isDesktop ? 28 : 20),
              Row(
                children: [
                  Icon(genre.icon, color: Colors.white, size: isDesktop ? 44 : 34),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      genre.title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isDesktop ? 40 : 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Current playlists from Spotify, Apple Music and YouTube',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
        for (final source in PlaylistSource.values)
          _SourceShelf(genre: genre, source: source, horizontalPadding: pad),
      ],
    );
  }
}

class _SourceShelf extends ConsumerWidget {
  final Genre genre;
  final PlaylistSource source;
  final double horizontalPadding;

  const _SourceShelf({required this.genre, required this.source, required this.horizontalPadding});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (genre, source);
    final async = ref.watch(genrePlaylistsProvider(key));

    Widget message(String text, {bool retry = false}) => Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Row(
            children: [
              Expanded(child: Text(text, style: const TextStyle(color: SymphonyTheme.textSecondary, fontSize: 13))),
              if (retry)
                TextButton(
                  onPressed: () => ref.invalidate(genrePlaylistsProvider(key)),
                  child: const Text('Try again'),
                ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 12),
            child: Text(
              'From ${source.label}',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: -0.3),
            ),
          ),
          async.when(
            loading: () => SizedBox(
              height: 252,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                itemCount: 4,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, __) => const _CardSkeleton(),
              ),
            ),
            error: (_, __) => message("Couldn't load playlists from ${source.label}.", retry: true),
            data: (playlists) => playlists.isEmpty
                ? message('No ${genre.title} playlists found on ${source.label}.')
                : SizedBox(
                    height: 252,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                      itemCount: playlists.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 14),
                      itemBuilder: (_, i) => StaggeredEntrance(index: i, child: PressLift(child: _SummaryCard(summary: playlists[i]))),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends ConsumerStatefulWidget {
  final PlaylistSummary summary;

  const _SummaryCard({required this.summary});

  @override
  ConsumerState<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends ConsumerState<_SummaryCard> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final playlist = await ref.read(openedPlaylistProvider(widget.summary).future);
      if (!mounted) return;
      ref.read(activePlaylistProvider.notifier).state = playlist;
      ref.read(navigationHistoryProvider.notifier).record('home', playlist);
    } catch (e) {
      ref.invalidate(openedPlaylistProvider(widget.summary));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: SymphonyTheme.cardHover,
          content: Text("Couldn't open \"${widget.summary.title}\". Try again in a moment."),
        ));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    return SizedBox(
      width: 170,
      child: HoverBuilder(
        onTap: _open,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: hovered ? SymphonyTheme.cardHover : SymphonyTheme.card,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: s.coverUrl == null
                          ? const _CoverFallback()
                          : Image.network(
                              s.coverUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const _CoverFallback(),
                            ),
                    ),
                    if (_opening)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                s.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, height: 1.2),
              ),
              const SizedBox(height: 4),
              Text(
                [s.subtitle, if (s.trackCount != null) '${s.trackCount} songs'].whereType<String>().join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: SymphonyTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SymphonyTheme.cardActive,
      child: const Icon(Icons.queue_music_rounded, color: SymphonyTheme.textSecondary, size: 40),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width) => Container(
          width: width,
          height: 12,
          decoration: BoxDecoration(color: SymphonyTheme.cardHover, borderRadius: BorderRadius.circular(4)),
        );
    return Container(
      width: 170,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: SymphonyTheme.card, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(color: SymphonyTheme.cardHover, borderRadius: BorderRadius.circular(6)),
            ),
          ),
          const SizedBox(height: 12),
          bar(120),
          const SizedBox(height: 8),
          bar(80),
        ],
      ),
    );
  }
}
