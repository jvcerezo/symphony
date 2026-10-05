import 'package:flutter/material.dart';

class SymphonyAccent {
  final String id;
  final String name;
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;
  final LinearGradient gradient;

  const SymphonyAccent({
    required this.id,
    required this.name,
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.gradient,
  });
}

class SymphonyTheme {
  // Modern Dark Bento Canvas (Neutral Ergonomic Foundation)
  static const Color obsidian = Color(0xFF000000); // Canvas pure black
  static const Color panel = Color(0xFF121212);    // Panel / Card surface
  static const Color midnight = Color(0xFF121212);
  static const Color surface = Color(0xFF121212);
  static const Color surfaceElevated = Color(0xFF181818);
  static const Color card = Color(0xFF181818);
  static const Color cardHover = Color(0xFF282828);
  static const Color cardActive = Color(0xFF333333);
  static const Color divider = Color(0xFF242424);
  static const Color dividerLight = Color(0xFF2A2A2A);

  // Symphony Signature Accents
  static const SymphonyAccent violet = SymphonyAccent(
    id: 'violet',
    name: 'Symphony Violet (Default)',
    primary: Color(0xFF8B5CF6),
    primaryLight: Color(0xFFA78BFA),
    primaryDark: Color(0xFF7C3AED),
    gradient: LinearGradient(
      colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  static const SymphonyAccent emerald = SymphonyAccent(
    id: 'emerald',
    name: 'Emerald Glow',
    primary: Color(0xFF10B981),
    primaryLight: Color(0xFF34D399),
    primaryDark: Color(0xFF059669),
    gradient: LinearGradient(
      colors: [Color(0xFF10B981), Color(0xFF059669)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  static const SymphonyAccent cyan = SymphonyAccent(
    id: 'cyan',
    name: 'Cyber Cyan',
    primary: Color(0xFF06B6D4),
    primaryLight: Color(0xFF22D3EE),
    primaryDark: Color(0xFF0891B2),
    gradient: LinearGradient(
      colors: [Color(0xFF06B6D4), Color(0xFF0284C7)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  static const SymphonyAccent amber = SymphonyAccent(
    id: 'amber',
    name: 'Sunset Amber',
    primary: Color(0xFFF59E0B),
    primaryLight: Color(0xFFFBBF24),
    primaryDark: Color(0xFFD97706),
    gradient: LinearGradient(
      colors: [Color(0xFFF59E0B), Color(0xFFEA580C)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  static const SymphonyAccent rose = SymphonyAccent(
    id: 'rose',
    name: 'Rose Quartz',
    primary: Color(0xFFEC4899),
    primaryLight: Color(0xFFF472B6),
    primaryDark: Color(0xFFDB2777),
    gradient: LinearGradient(
      colors: [Color(0xFFEC4899), Color(0xFFE11D48)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  static const SymphonyAccent green = SymphonyAccent(
    id: 'green',
    name: 'Classic Green',
    primary: Color(0xFF1ED760),
    primaryLight: Color(0xFF3BE477),
    primaryDark: Color(0xFF1DB954),
    gradient: LinearGradient(
      colors: [Color(0xFF1ED760), Color(0xFF1DB954)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  static const List<SymphonyAccent> allAccents = [
    violet,
    emerald,
    cyan,
    amber,
    rose,
    green,
  ];

  static const List<SymphonyAccent> accents = allAccents;

  // Default Primary Brand Color (Symphony Electric Violet)
  static const Color primary = Color(0xFF8B5CF6);
  static const Color primaryLight = Color(0xFFA78BFA);
  static const Color primaryDark = Color(0xFF7C3AED);
  static const Color secondary = Color(0xFF8B5CF6);
  static const Color spotifyGreen = Color(0xFF1ED760);

  // Typography Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB3B3B3);
  static const Color textMuted = Color(0xFF727272);

  // Gradients
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF4C1D95), Color(0xFF121212)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: obsidian,
    primaryColor: primary,
    colorScheme: const ColorScheme.dark(
      primary: primary,
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
