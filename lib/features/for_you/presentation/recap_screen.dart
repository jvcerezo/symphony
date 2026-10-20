import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/symphony_theme.dart';
import '../../audio_player/domain/entities/track.dart';
import '../../audio_player/presentation/controllers/audio_player_providers.dart';
import '../domain/listening_log.dart';
import '../domain/recap.dart';
import 'for_you_providers.dart';
import 'recap_format.dart';
import 'recap_share_card.dart';
import 'recap_sharing.dart';
import '../../../core/widgets/sized_network_image.dart';

/// A look back at a year or a month of listening, as full-screen slides
/// (tap the right side or swipe for the next, the left side to go back).
class RecapScreen extends ConsumerStatefulWidget {
  final int initialYear;

  /// Where finished share cards go; the system share sheet by default.
  final ShareImage share;

  const RecapScreen({super.key, required this.initialYear, this.share = shareWithSystem});

  @override
  ConsumerState<RecapScreen> createState() => _RecapScreenState();
}

class _RecapScreenState extends ConsumerState<RecapScreen> {
  final _pages = PageController();
  late int _year = widget.initialYear;

  /// Null: the whole year.
  int? _month;
  int _page = 0;
  bool _sharing = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _select(int year, int? month) {
    setState(() {
      _year = year;
      _month = month;
      _page = 0;
    });
    if (_pages.hasClients) _pages.jumpToPage(0);
  }

  void _step(int by, int count) {
    final target = (_page + by).clamp(0, count - 1);
    if (target == _page) {
      if (by > 0) Navigator.of(context).maybePop();
      return;
    }
    _pages.animateToPage(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final log = ref.watch(listeningHistoryProvider);
    final recap = _month == null ? Recap.year(log, _year) : Recap.month(log, _year, _month!);
    final slides = recap.isEmpty ? [(kind: null, widget: _EmptySlide(recap: recap))] : _slidesFor(recap);
    final shareKind = slides[_page.clamp(0, slides.length - 1)].kind;

    return Scaffold(
      backgroundColor: SymphonyTheme.obsidian,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
              child: Row(
                children: [
                  for (var i = 0; i < slides.length; i++)
                    Expanded(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i <= _page ? Colors.white : Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  if (shareKind != null)
                    IconButton(
                      tooltip: 'Share',
                      onPressed: _sharing ? null : () => _share(recap, shareKind),
                      icon: _sharing
                          ? const SizedBox.square(
                              dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.ios_share_rounded, color: Colors.white),
                    ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _PeriodButton(
                  label: recap.title,
                  onTap: () => _pickPeriod(log),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (d) => _step(d.localPosition.dx < constraints.maxWidth / 3 ? -1 : 1, slides.length),
                  child: PageView(
                    controller: _pages,
                    onPageChanged: (p) => setState(() => _page = p),
                    children: [
                      for (var i = 0; i < slides.length; i++)
                        _SlideFrame(
                            gradient: SymphonyTheme.recapGradients[i % SymphonyTheme.recapGradients.length],
                            child: slides[i].widget),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Each slide, and the share card that goes with it.
  List<({RecapCardKind? kind, Widget widget})> _slidesFor(Recap recap) => [
        (kind: RecapCardKind.minutes, widget: _MinutesSlide(recap: recap)),
        if (recap.topArtists.isNotEmpty) (kind: RecapCardKind.topArtist, widget: _TopArtistSlide(recap: recap)),
        if (recap.topSongs.isNotEmpty) (kind: RecapCardKind.topSongs, widget: _TopSongsSlide(recap: recap)),
        if (recap.topArtists.length > 1) (kind: RecapCardKind.topArtists, widget: _TopArtistsSlide(recap: recap)),
        (kind: RecapCardKind.habits, widget: _HabitsSlide(recap: recap, isYear: _month == null)),
        (
          kind: RecapCardKind.summary,
          widget: _SummarySlide(
            recap: recap,
            onPlay: recap.topSongs.isEmpty ? null : () => _playTopSongs(recap),
            onShare: _sharing ? null : () => _share(recap, RecapCardKind.summary),
          ),
        ),
      ];

  Future<void> _share(Recap recap, RecapCardKind kind) async {
    setState(() => _sharing = true);
    try {
      await shareRecapCard(recap, kind, view: View.of(context), share: widget.share);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sharing that picture did not work. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _playTopSongs(Recap recap) async {
    final tracks = recap.topSongs
        .map((s) => Track(
              id: s.trackId,
              title: s.title,
              artist: s.artist,
              artworkUri: s.artworkUrl == null ? null : Uri.tryParse(s.artworkUrl!),
            ))
        .toList();
    await ref.read(audioHandlerProvider).playQueue(tracks);
  }

  Future<void> _pickPeriod(ListeningLog log) async {
    final years = Recap.yearsIn(log);
    final choice = await showModalBottomSheet<(int, int?)>(
      context: context,
      backgroundColor: SymphonyTheme.surfaceElevated,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final y in years) ...[
                ListTile(
                  minTileHeight: 52,
                  title: Text('$y, the whole year',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  trailing: _year == y && _month == null ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                  onTap: () => Navigator.pop(context, (y, null)),
                ),
                for (var m = 12; m >= 1; m--)
                  if (log.months.containsKey(ListeningLog.monthKey(DateTime(y, m))))
                    ListTile(
                      minTileHeight: 48,
                      contentPadding: const EdgeInsets.only(left: 32, right: 16),
                      title:
                          Text('${Recap.monthName(m)} $y', style: const TextStyle(color: SymphonyTheme.textSecondary)),
                      trailing: _year == y && _month == m ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                      onTap: () => Navigator.pop(context, (y, m)),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
    if (choice != null) _select(choice.$1, choice.$2);
  }
}

class _PeriodButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PeriodButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        backgroundColor: Colors.white12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(500)),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      icon: const Icon(Icons.calendar_month_rounded, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _SlideFrame extends StatelessWidget {
  final LinearGradient gradient;
  final Widget child;

  const _SlideFrame({required this.gradient, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: child,
          ),
        ),
      ),
    );
  }
}

const _kicker = TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600);
const _headline =
    TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -0.8);

class _Art extends StatelessWidget {
  final String? url;
  final double size;
  final bool round;

  const _Art({required this.url, required this.size, this.round = false});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      color: Colors.white24,
      child: Icon(Icons.music_note_rounded, color: Colors.white70, size: size * 0.4),
    );
    final image = url == null
        ? fallback
        : SizedNetworkImage(url!, width: size, height: size, errorBuilder: (_, __, ___) => fallback);
    return ClipRRect(borderRadius: BorderRadius.circular(round ? size / 2 : 8), child: image);
  }
}

class _EmptySlide extends StatelessWidget {
  final Recap recap;

  const _EmptySlide({required this.recap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.hourglass_empty_rounded, color: Colors.white, size: 48),
        const SizedBox(height: 16),
        Text('Nothing to look back on for ${recap.title} yet',
            textAlign: TextAlign.center, style: _headline.copyWith(fontSize: 26)),
        const SizedBox(height: 12),
        const Text('Songs you play from now on count toward your recap.', textAlign: TextAlign.center, style: _kicker),
      ],
    );
  }
}

class _MinutesSlide extends StatelessWidget {
  final Recap recap;

  const _MinutesSlide({required this.recap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your ${recap.title} in music', style: _kicker),
        const SizedBox(height: 24),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatCount(recap.listened.inMinutes),
            style: _headline.copyWith(fontSize: 88, letterSpacing: -3),
          ),
        ),
        const Text('minutes of listening',
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 24),
        Text(
          '${formatCount(recap.songCount)} different songs from ${formatCount(recap.artistCount)} artists.',
          style: _kicker,
        ),
      ],
    );
  }
}

class _TopArtistSlide extends StatelessWidget {
  final Recap recap;

  const _TopArtistSlide({required this.recap});

  @override
  Widget build(BuildContext context) {
    final top = recap.topArtists.first;
    final share = recap.listened.inSeconds == 0 ? 0 : (top.listened.inSeconds * 100 / recap.listened.inSeconds).round();
    return Column(
      children: [
        const Text('Your top artist', style: _kicker),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, c) => _Art(url: top.artworkUrl, size: math.min(220, c.maxWidth * 0.7), round: true),
        ),
        const SizedBox(height: 24),
        Text(top.name, textAlign: TextAlign.center, style: _headline),
        const SizedBox(height: 12),
        Text(
          '${formatCount(top.listened.inMinutes)} minutes together, $share% of all your listening.',
          textAlign: TextAlign.center,
          style: _kicker,
        ),
      ],
    );
  }
}

class _TopSongsSlide extends StatelessWidget {
  final Recap recap;

  const _TopSongsSlide({required this.recap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Your top songs', style: _kicker),
        const SizedBox(height: 20),
        for (final (i, s) in recap.topSongs.take(5).indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text('${i + 1}', style: _headline.copyWith(fontSize: 26)),
                ),
                _Art(url: s.artworkUrl, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                      Text('${s.artist} · ${s.plays} ${s.plays == 1 ? 'play' : 'plays'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TopArtistsSlide extends StatelessWidget {
  final Recap recap;

  const _TopArtistsSlide({required this.recap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Your top artists', style: _kicker),
        const SizedBox(height: 20),
        for (final (i, a) in recap.topArtists.take(5).indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                SizedBox(width: 34, child: Text('${i + 1}', style: _headline.copyWith(fontSize: 26))),
                _Art(url: a.artworkUrl, size: 56, round: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                      Text('${formatCount(a.listened.inMinutes)} minutes',
                          style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _HabitsSlide extends StatelessWidget {
  final Recap recap;
  final bool isYear;

  const _HabitsSlide({required this.recap, required this.isYear});

  @override
  Widget build(BuildContext context) {
    final hour = recap.peakHour;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('How you listen', style: _kicker),
        const SizedBox(height: 16),
        if (hour != null) ...[
          Text('You\'re ${listenerKind(hour)}', style: _headline),
          const SizedBox(height: 8),
          Text('You listen most around ${formatHour(hour)}.', style: _kicker),
          const SizedBox(height: 28),
        ],
        Row(
          children: [
            Expanded(
                child: _Stat(
                    value: formatCount(recap.activeDays),
                    label: recap.activeDays == 1 ? 'day with music' : 'days with music')),
            Expanded(child: _Stat(value: formatCount(recap.longestStreak), label: 'days in a row, your best streak')),
          ],
        ),
        if (isYear) ...[
          const SizedBox(height: 28),
          const Text('Minutes by month', style: _kicker),
          const SizedBox(height: 12),
          _MonthBars(byMonth: recap.byMonth),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;

  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: _headline.copyWith(fontSize: 44)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}

class _MonthBars extends StatelessWidget {
  final List<Duration> byMonth;

  const _MonthBars({required this.byMonth});

  @override
  Widget build(BuildContext context) {
    final most = byMonth.fold(0, (m, d) => math.max(m, d.inSeconds));
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var m = 0; m < 12; m++)
            Expanded(
              child: Tooltip(
                message: '${Recap.monthName(m + 1)}: ${formatCount(byMonth[m].inMinutes)} min',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: most == 0 ? 2 : math.max(2, 96 * byMonth[m].inSeconds / most),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: byMonth[m].inSeconds == most && most > 0 ? Colors.white : Colors.white54,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(Recap.monthName(m + 1)[0], style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummarySlide extends StatelessWidget {
  final Recap recap;
  final VoidCallback? onPlay;
  final VoidCallback? onShare;

  const _SummarySlide({required this.recap, required this.onPlay, required this.onShare});

  @override
  Widget build(BuildContext context) {
    final topArtist = recap.topArtists.isEmpty ? null : recap.topArtists.first;
    final topSong = recap.topSongs.isEmpty ? null : recap.topSongs.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${recap.title}, wrapped up', style: _kicker),
        const SizedBox(height: 20),
        if (topSong != null) Center(child: _Art(url: topSong.artworkUrl, size: 140)),
        const SizedBox(height: 24),
        Wrap(
          runSpacing: 18,
          children: [
            _SummaryRow(label: 'Minutes listened', value: formatCount(recap.listened.inMinutes)),
            if (topArtist != null) _SummaryRow(label: 'Top artist', value: topArtist.name),
            if (topSong != null) _SummaryRow(label: 'Top song', value: '${topSong.title} · ${topSong.artist}'),
            _SummaryRow(label: 'Songs played', value: formatCount(recap.songCount)),
          ],
        ),
        if (onPlay != null) ...[
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
              label:
                  const Text('Play your top songs', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(0, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(500)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onShare,
            icon: const Icon(Icons.ios_share_rounded, color: Colors.white),
            label: const Text('Share your recap', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 56),
              side: const BorderSide(color: Colors.white70),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(500)),
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text(value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
