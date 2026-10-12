import 'package:flutter/material.dart';

/// A Browse genre: how to find its playlists on each source.
class Genre {
  final String id;
  final String title;
  final List<Color> gradient;
  final IconData icon;

  /// Spotify's own editorial playlists for the genre. Spotify can't be
  /// searched without an account, but it keeps these updated, and their
  /// songs are read live when opened.
  final List<String> spotifyPlaylistIds;

  /// Search terms for Apple Music and YouTube, which are searched live.
  final String query;

  const Genre({
    required this.id,
    required this.title,
    required this.gradient,
    required this.icon,
    required this.spotifyPlaylistIds,
    required this.query,
  });

  @override
  bool operator ==(Object other) => other is Genre && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Spotify ids checked against open.spotify.com/embed on 2026-10-12.
abstract final class GenreCatalog {
  static const all = [
    Genre(
      id: 'pop',
      title: 'Pop & Top Hits',
      gradient: [Color(0xFF8D137B), Color(0xFFE1306C)],
      icon: Icons.music_note_rounded,
      spotifyPlaylistIds: ['37i9dQZF1DXcBWIGoYBM5M', '37i9dQZF1DWUa8ZRTfalHk'], // Today's Top Hits, Pop Rising
      query: 'pop hits',
    ),
    Genre(
      id: 'chill',
      title: 'Chill & Lo-Fi',
      gradient: [Color(0xFF1E3264), Color(0xFF2E77D0)],
      icon: Icons.nightlife_rounded,
      spotifyPlaylistIds: ['37i9dQZF1DWWQRwui0ExPn', '37i9dQZF1DX4WYpdgoIcn6'], // lofi beats, Chill Hits
      query: 'lofi',
    ),
    Genre(
      id: 'rock',
      title: 'Rock Classics',
      gradient: [Color(0xFF8B0000), Color(0xFFE91E63)],
      icon: Icons.electric_bolt_rounded,
      spotifyPlaylistIds: ['37i9dQZF1DWXRqgorJj26U'], // Rock Classics
      query: 'classic rock',
    ),
    Genre(
      id: 'rnb',
      title: 'R&B & Night Grooves',
      gradient: [Color(0xFF4A148C), Color(0xFF7B1FA2)],
      icon: Icons.dark_mode_rounded,
      spotifyPlaylistIds: ['37i9dQZF1DX4SBhb3fqCJd', '37i9dQZF1DX2UgsUIg75Vg'], // RNB X, Chilled R&B
      query: 'r&b',
    ),
    Genre(
      id: 'hiphop',
      title: 'Hip-Hop & Rap',
      gradient: [Color(0xFFBA5D00), Color(0xFFFF9800)],
      icon: Icons.album_rounded,
      spotifyPlaylistIds: ['37i9dQZF1DX0XUsuxWHRQd'], // RapCaviar
      query: 'hip hop',
    ),
    Genre(
      id: 'focus',
      title: 'Focus & Study',
      gradient: [Color(0xFF0D7377), Color(0xFF14FFEC)],
      icon: Icons.headphones_rounded,
      spotifyPlaylistIds: ['37i9dQZF1DWZeKCadgRdKQ', '37i9dQZF1DX4sWSpwq3LiO'], // Deep Focus, Peaceful Piano
      query: 'study focus',
    ),
    Genre(
      id: 'workout',
      title: 'Workout & Energy',
      gradient: [Color(0xFFBF360C), Color(0xFFFF5722)],
      icon: Icons.fitness_center_rounded,
      spotifyPlaylistIds: ['37i9dQZF1DX76Wlfdnj7AP', '37i9dQZF1DX70RN3TfWWJh'], // Beast Mode, Workout
      query: 'workout',
    ),
    Genre(
      id: 'acoustic',
      title: 'Acoustic & Peace',
      gradient: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
      icon: Icons.spa_rounded,
      spotifyPlaylistIds: ['37i9dQZF1DX4E3UdUs7fUx', '37i9dQZF1DX6ziVCJnEm59'], // Afternoon Acoustic, Coffeehouse
      query: 'acoustic',
    ),
  ];
}
