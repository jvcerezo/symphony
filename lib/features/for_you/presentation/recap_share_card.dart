import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/config/links.dart';
import '../../../core/theme/symphony_theme.dart';
import '../domain/recap.dart';
import 'recap_format.dart';

/// Which part of a recap a share card shows.
enum RecapCardKind { minutes, topArtist, topSongs, topArtists, habits, summary }

/// A story-sized (9:16) picture of part of a recap, to post or send.
/// Every card ends with where to get Symphony.
///
/// Drawn off screen (see `renderWidgetToPng`), so artwork comes in
/// [images] already decoded, keyed by URL; missing ones get a placeholder.
class RecapShareCard extends StatelessWidget {
  final Recap recap;
  final RecapCardKind kind;
  final Map<String, ui.Image> images;

  const RecapShareCard({super.key, required this.recap, required this.kind, this.images = const {}});

  static const size = Size(360, 640);

  /// The artwork [kind] shows, to load before drawing.
  static List<String> artworkFor(Recap recap, RecapCardKind kind) => switch (kind) {
        RecapCardKind.topArtist => [recap.topArtists.firstOrNull?.artworkUrl].whereType<String>().toList(),
        RecapCardKind.topSongs => recap.topSongs.take(5).map((s) => s.artworkUrl).whereType<String>().toList(),
        RecapCardKind.topArtists => recap.topArtists.take(5).map((a) => a.artworkUrl).whereType<String>().toList(),
        RecapCardKind.summary => [recap.topSongs.firstOrNull?.artworkUrl].whereType<String>().toList(),
        RecapCardKind.minutes || RecapCardKind.habits => const [],
      };

  @override
  Widget build(BuildContext context) {
    final gradient = SymphonyTheme.recapGradients[kind.index % SymphonyTheme.recapGradients.length];
    return SizedBox.fromSize(
      size: size,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: gradient),
        child: DefaultTextStyle(
          style: const TextStyle(
            fontFamily: 'Segoe UI',
            color: Colors.white,
            decoration: TextDecoration.none,
            fontSize: 14,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MY ${recap.title.toUpperCase()} ON SYMPHONY',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: Colors.white70)),
                const SizedBox(height: 20),
                Expanded(child: _body()),
                const Divider(color: Colors.white38, height: 24),
                const Row(
                  children: [
                    Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Listen free on Symphony',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(SymphonyLinks.siteShort, style: TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _art(String? url, double side, {bool round = false}) {
    final image = url == null ? null : images[url];
    return ClipRRect(
      borderRadius: BorderRadius.circular(round ? side / 2 : 8),
      child: SizedBox.square(
        dimension: side,
        child: image == null
            ? ColoredBox(
                color: Colors.white24,
                child: Icon(Icons.music_note_rounded, color: Colors.white70, size: side * 0.4),
              )
            : RawImage(image: image, fit: BoxFit.cover),
      ),
    );
  }

  static const _big = TextStyle(fontWeight: FontWeight.w900, height: 1.05, letterSpacing: -1);

  Widget _body() {
    switch (kind) {
      case RecapCardKind.minutes:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(formatCount(recap.listened.inMinutes), style: _big.copyWith(fontSize: 96)),
            ),
            const Text('minutes of music', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Text('${formatCount(recap.songCount)} songs from ${formatCount(recap.artistCount)} artists',
                style: const TextStyle(fontSize: 16, color: Colors.white70)),
          ],
        );
      case RecapCardKind.topArtist:
        final top = recap.topArtists.first;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('My top artist', style: TextStyle(fontSize: 18, color: Colors.white70)),
            const SizedBox(height: 20),
            _art(top.artworkUrl, 200, round: true),
            const SizedBox(height: 22),
            Text(top.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: _big.copyWith(fontSize: 38)),
            const SizedBox(height: 8),
            Text('${formatCount(top.listened.inMinutes)} minutes together',
                style: const TextStyle(fontSize: 16, color: Colors.white70)),
          ],
        );
      case RecapCardKind.topSongs:
        return _ranked(
          'My top songs',
          [
            for (final s in recap.topSongs.take(5)) (title: s.title, sub: s.artist, art: s.artworkUrl, round: false),
          ],
        );
      case RecapCardKind.topArtists:
        return _ranked(
          'My top artists',
          [
            for (final a in recap.topArtists.take(5))
              (title: a.name, sub: '${formatCount(a.listened.inMinutes)} minutes', art: a.artworkUrl, round: true),
          ],
        );
      case RecapCardKind.habits:
        final hour = recap.peakHour;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (hour != null) ...[
              Text('I\'m ${listenerKind(hour)}', style: _big.copyWith(fontSize: 44)),
              const SizedBox(height: 10),
              Text('Most of my listening happens around ${formatHour(hour)}.',
                  style: const TextStyle(fontSize: 17, color: Colors.white70)),
              const SizedBox(height: 36),
            ],
            Text(formatCount(recap.longestStreak), style: _big.copyWith(fontSize: 72)),
            const Text('days in a row with music', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            Text('${formatCount(recap.activeDays)} days with music in all',
                style: const TextStyle(fontSize: 16, color: Colors.white70)),
          ],
        );
      case RecapCardKind.summary:
        final song = recap.topSongs.firstOrNull;
        final artist = recap.topArtists.firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: _art(song?.artworkUrl, 190)),
            const SizedBox(height: 22),
            _stat('Minutes listened', formatCount(recap.listened.inMinutes)),
            if (artist != null) _stat('Top artist', artist.name),
            if (song != null) _stat('Top song', song.title),
            _stat('Songs played', formatCount(recap.songCount)),
          ],
        );
    }
  }

  Widget _stat(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _ranked(String heading, List<({String title, String sub, String? art, bool round})> rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: _big.copyWith(fontSize: 34)),
          const SizedBox(height: 22),
          for (final (i, r) in rows.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  SizedBox(width: 30, child: Text('${i + 1}', style: _big.copyWith(fontSize: 24))),
                  _art(r.art, 54, round: r.round),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        Text(r.sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
}
