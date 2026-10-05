import 'package:audio_service/audio_service.dart';

class Track {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final Duration? expectedDuration;
  final Uri? artworkUri;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.expectedDuration,
    this.artworkUri,
  });

  MediaItem toMediaItem({required Duration actualDuration}) {
    return MediaItem(
      id: id,
      title: title,
      artist: artist,
      album: album ?? '',
      duration: actualDuration,
      artUri: artworkUri,
    );
  }

  @override
  String toString() => 'Track(id: $id, title: "$title", artist: "$artist")';
}
