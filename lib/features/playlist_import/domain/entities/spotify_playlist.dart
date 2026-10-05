import '../../../audio_player/domain/entities/track.dart';

class SpotifyPlaylist {
  final String id;
  final String title;
  final String? description;
  final String? coverUrl;
  final String? ownerName;
  final String source;
  final List<Track> tracks;

  const SpotifyPlaylist({
    required this.id,
    required this.title,
    this.description,
    this.coverUrl,
    this.ownerName,
    this.source = 'Spotify',
    required this.tracks,
  });

  int get trackCount => tracks.length;

  Duration get totalDuration {
    return tracks.fold<Duration>(
      Duration.zero,
      (prev, t) => prev + (t.expectedDuration ?? Duration.zero),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'coverUrl': coverUrl,
      'ownerName': ownerName,
      'source': source,
      'tracks': tracks.map((t) => {
        'id': t.id,
        'title': t.title,
        'artist': t.artist,
        'album': t.album,
        'durationMs': t.expectedDuration?.inMilliseconds ?? 0,
        'artworkUri': t.artworkUri?.toString(),
      }).toList(),
    };
  }

  factory SpotifyPlaylist.fromJson(Map<String, dynamic> json) {
    final rawTracks = json['tracks'] as List<dynamic>? ?? [];
    final tracks = rawTracks.map((t) {
      final durMs = t['durationMs'] as int? ?? 0;
      final artUri = t['artworkUri'] as String?;
      return Track(
        id: t['id'] as String? ?? 'sp_0',
        title: t['title'] as String? ?? 'Unknown Title',
        artist: t['artist'] as String? ?? 'Unknown Artist',
        album: t['album'] as String? ?? '',
        expectedDuration: durMs > 0 ? Duration(milliseconds: durMs) : null,
        artworkUri: artUri != null ? Uri.tryParse(artUri) : null,
      );
    }).toList();

    return SpotifyPlaylist(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Saved Playlist',
      description: json['description'] as String?,
      coverUrl: json['coverUrl'] as String?,
      ownerName: json['ownerName'] as String? ?? 'User',
      source: json['source'] as String? ?? 'Spotify',
      tracks: tracks,
    );
  }
}

