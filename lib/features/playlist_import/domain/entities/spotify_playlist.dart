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
    final tracks = <Track>[];
    for (int i = 0; i < rawTracks.length; i++) {
      final t = rawTracks[i];
      if (t is Map) {
        final durMs = (t['durationMs'] as num?)?.toInt() ?? 0;
        final artUri = t['artworkUri']?.toString();
        tracks.add(
          Track(
            id: (t['id']?.toString()) ?? 'sp_$i',
            title: (t['title']?.toString()) ?? 'Unknown Title',
            artist: (t['artist']?.toString()) ?? 'Unknown Artist',
            album: (t['album']?.toString()) ?? '',
            expectedDuration: durMs > 0 ? Duration(milliseconds: durMs) : null,
            artworkUri: artUri != null && artUri.isNotEmpty ? Uri.tryParse(artUri) : null,
          ),
        );
      }
    }

    return SpotifyPlaylist(
      id: (json['id']?.toString()) ?? '',
      title: (json['title']?.toString()) ?? 'Saved Playlist',
      description: json['description']?.toString(),
      coverUrl: json['coverUrl']?.toString(),
      ownerName: (json['ownerName']?.toString()) ?? 'User',
      source: (json['source']?.toString()) ?? 'Spotify',
      tracks: tracks,
    );
  }
}

