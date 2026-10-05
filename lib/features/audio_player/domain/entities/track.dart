import 'package:audio_service/audio_service.dart';

class Track {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final Duration? expectedDuration;
  final Uri? artworkUri;
  final Uri? streamUri;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.expectedDuration,
    this.artworkUri,
    this.streamUri,
  });

  MediaItem toMediaItem({Duration? actualDuration}) {
    return MediaItem(
      id: id,
      title: title,
      artist: artist,
      album: album ?? '',
      duration: actualDuration ?? expectedDuration ?? const Duration(minutes: 3),
      artUri: artworkUri,
    );
  }

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    Duration? expectedDuration,
    Uri? artworkUri,
    Uri? streamUri,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      expectedDuration: expectedDuration ?? this.expectedDuration,
      artworkUri: artworkUri ?? this.artworkUri,
      streamUri: streamUri ?? this.streamUri,
    );
  }

  @override
  String toString() => 'Track(id: $id, title: "$title", artist: "$artist", hasStream: ${streamUri != null})';
}
