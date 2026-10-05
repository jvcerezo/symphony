import '../../../audio_player/domain/entities/track.dart';

class SpotifyPlaylist {
  final String id;
  final String title;
  final String? description;
  final String? coverUrl;
  final String? ownerName;
  final List<Track> tracks;

  const SpotifyPlaylist({
    required this.id,
    required this.title,
    this.description,
    this.coverUrl,
    this.ownerName,
    required this.tracks,
  });

  int get trackCount => tracks.length;

  Duration get totalDuration {
    return tracks.fold<Duration>(
      Duration.zero,
      (prev, t) => prev + (t.expectedDuration ?? Duration.zero),
    );
  }
}
