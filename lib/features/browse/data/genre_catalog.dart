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

/// Spotify ids checked against open.spotify.com/embed on 2026-10-12
/// (the ones added since, on 2026-10-23).
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
      id: 'opm',
      title: 'OPM & Pinoy Hits',
      gradient: [Color(0xFF0038A8), Color(0xFFCE1126)],
      icon: Icons.wb_sunny_rounded,
      spotifyPlaylistIds: ['37i9dQZEVXbNBz9cRCSFkY'], // Top 50 - Philippines
      query: 'OPM',
    ),
    Genre(
      id: 'kpop',
      title: 'K-Pop',
      gradient: [Color(0xFFD81B60), Color(0xFFFF80AB)],
      icon: Icons.auto_awesome_rounded,
      spotifyPlaylistIds: ['37i9dQZF1DX9tPFwDMOaN1'], // K-Pop ON! (온)
      query: 'k-pop',
    ),
    Genre(
      id: 'throwback',
      title: 'Throwbacks',
      gradient: [Color(0xFF5D4037), Color(0xFFFFB300)],
      icon: Icons.history_rounded,
      spotifyPlaylistIds: [
        '37i9dQZF1DX5Ejj0EkURtP', // All Out 2010s
        '37i9dQZF1DX4o1oenSJRJd', // All Out 2000s
        '37i9dQZF1DXbTxeAdrVG2l', // All Out 90s
        '37i9dQZF1DX4UtSsGT1Sbe', // All Out 80s
      ],
      query: 'throwback hits',
    ),
    Genre(
      id: 'love',
      title: 'Love Songs',
      gradient: [Color(0xFFAD1457), Color(0xFFF06292)],
      icon: Icons.favorite_rounded,
      spotifyPlaylistIds: ['37i9dQZF1DX50QitC6Oqtn'], // Love Pop
      query: 'love songs',
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
      spotifyPlaylistIds: ['37i9dQZF1DWXRqgorJj26U', '37i9dQZF1DX1rVvRgjX59F'], // Rock Classics, 90s Rock Anthems
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
    Genre(
      id: 'sad',
      title: 'Sad Songs',
      gradient: [Color(0xFF263238), Color(0xFF546E7A)],
      icon: Icons.water_drop_rounded,
      spotifyPlaylistIds: ['37i9dQZF1DX7qK8ma5wgG1'], // Sad Songs
      query: 'sad songs',
    ),
    Genre(
      id: 'dance',
      title: 'Dance & EDM',
      gradient: [Color(0xFF00838F), Color(0xFF00E5FF)],
      icon: Icons.celebration_rounded,
      spotifyPlaylistIds: ['37i9dQZF1DX4dyzvuaRJ0n', '37i9dQZF1DXaXB8fQg7xif'], // mint, Dance Party
      query: 'edm',
    ),
    Genre(
      id: 'latin',
      title: 'Latin',
      gradient: [Color(0xFFE65100), Color(0xFFFFCA28)],
      icon: Icons.local_fire_department_rounded,
      spotifyPlaylistIds: ['37i9dQZF1DX10zKzsJ2jva'], // Viva Latino
      query: 'latin hits',
    ),
    Genre(
      id: 'indie',
      title: 'Indie & Alternative',
      gradient: [Color(0xFF33691E), Color(0xFF9CCC65)],
      icon: Icons.graphic_eq_rounded,
      spotifyPlaylistIds: ['37i9dQZF1DXdbXrPNafg9d', '37i9dQZF1DXdwmD5Q7Gxah'], // All New Indie, Lorem
      query: 'indie',
    ),
    Genre(
      id: 'country',
      title: 'Country',
      gradient: [Color(0xFF6D4C41), Color(0xFFD7A86E)],
      icon: Icons.landscape_rounded,
      spotifyPlaylistIds: ['37i9dQZF1DX1lVhptIYRda'], // Hot Country
      query: 'country hits',
    ),
    Genre(
      id: 'jazz',
      title: 'Jazz',
      gradient: [Color(0xFF3E2723), Color(0xFFA1887F)],
      icon: Icons.piano_rounded,
      spotifyPlaylistIds: ['37i9dQZF1DXbITWG1ZJKYt', '37i9dQZF1DX0SM0LYsmbMT'], // Jazz Classics, Jazz Vibes
      query: 'jazz',
    ),
    Genre(
      id: 'classical',
      title: 'Classical',
      gradient: [Color(0xFF37474F), Color(0xFFB0BEC5)],
      icon: Icons.queue_music_rounded,
      spotifyPlaylistIds: ['37i9dQZF1DWWEJlAGA9gs0'], // Classical Essentials
      query: 'classical music',
    ),
    Genre(
      id: 'sleep',
      title: 'Sleep',
      gradient: [Color(0xFF1A237E), Color(0xFF5C6BC0)],
      icon: Icons.bedtime_rounded,
      spotifyPlaylistIds: ['37i9dQZF1DWZd79rJ6a7lp'], // Sleep
      query: 'sleep music',
    ),
    Genre(
      id: 'metal',
      title: 'Metal',
      gradient: [Color(0xFF212121), Color(0xFF757575)],
      icon: Icons.flash_on_rounded,
      spotifyPlaylistIds: ['37i9dQZF1DWTcqUzwhNmKv'], // Kickass Metal
      query: 'metal',
    ),
    Genre(
      id: 'anime',
      title: 'Anime',
      gradient: [Color(0xFF6A1B9A), Color(0xFF4FC3F7)],
      icon: Icons.animation_rounded,
      spotifyPlaylistIds: ['37i9dQZF1DWT8aqnwgRt92'], // Anime Now
      query: 'anime songs',
    ),
  ];
}
