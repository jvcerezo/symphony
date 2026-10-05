import 'package:flutter/material.dart';

class SymphonyTheme {
  // Spotify Benchmark Core Palette
  static const Color obsidian = Color(0xFF000000); // Spotify Canvas pure black
  static const Color panel = Color(0xFF121212);    // Spotify Panel / Card surface
  static const Color midnight = Color(0xFF121212);
  static const Color surface = Color(0xFF121212);
  static const Color surfaceElevated = Color(0xFF181818);
  static const Color card = Color(0xFF181818);
  static const Color cardHover = Color(0xFF282828);
  static const Color cardActive = Color(0xFF333333);
  static const Color divider = Color(0xFF242424);
  static const Color dividerLight = Color(0xFF2A2A2A);

  // Vibrant Accents (Spotify Green & Symphony Electric Glow)
  static const Color spotifyGreen = Color(0xFF1ED760); // Official Spotify Bright Green
  static const Color spotifyGreenDark = Color(0xFF1DB954);
  static const Color primary = Color(0xFF1ED760); // Spotify Green as benchmark
  static const Color primaryLight = Color(0xFF3BE477);
  static const Color primaryDark = Color(0xFF1AA34A);
  static const Color electricViolet = Color(0xFF8B5CF6);
  static const Color secondary = Color(0xFF1ED760);
  static const Color accentCyan = Color(0xFF06B6D4);
  static const Color accentPink = Color(0xFFEC4899);

  // Typography Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB3B3B3); // Spotify Light Gray
  static const Color textMuted = Color(0xFF727272);     // Spotify Caption Gray

  // Gradients
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF1ED760), Color(0xFF1DB954)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF5038A0), Color(0xFF121212)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: obsidian,
    primaryColor: spotifyGreen,
    colorScheme: const ColorScheme.dark(
      primary: spotifyGreen,
      secondary: secondary,
      surface: surface,
    ),
    fontFamily: 'Segoe UI',
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Colors.white,
      inactiveTrackColor: Color(0xFF4D4D4D),
      thumbColor: Colors.white,
      trackHeight: 4.0,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6.0),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 12.0),
    ),
  );
}
