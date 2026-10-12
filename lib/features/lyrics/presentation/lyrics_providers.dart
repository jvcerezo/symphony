import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/lyrics_service.dart';
import '../domain/lyrics.dart';

final lyricsServiceProvider = Provider<LyricsService>((ref) {
  final service = LyricsService();
  ref.onDispose(service.dispose);
  return service;
});

/// Which song to look up. Equal by title and artist only, so the length
/// being corrected once the stream loads doesn't start a second lookup.
class LyricsQuery {
  final String title;
  final String artist;
  final String? album;
  final Duration? duration;

  const LyricsQuery({required this.title, required this.artist, this.album, this.duration});

  @override
  bool operator ==(Object other) => other is LyricsQuery && other.title == title && other.artist == artist;

  @override
  int get hashCode => Object.hash(title, artist);
}

/// Lyrics for a song; null when none exist. Errors mean the lookup failed.
final lyricsProvider = FutureProvider.autoDispose.family<Lyrics?, LyricsQuery>((ref, q) {
  return ref.watch(lyricsServiceProvider).fetch(
        title: q.title,
        artist: q.artist,
        album: q.album,
        duration: q.duration,
      );
});
