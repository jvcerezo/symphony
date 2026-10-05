import 'package:flutter/material.dart';

class SymphonyTheme {
  // Brand Colors - Symphony Signature Palette
  static const Color obsidian = Color(0xFF090A0F);
  static const Color midnight = Color(0xFF10131B);
  static const Color surface = Color(0xFF161A26);
  static const Color card = Color(0xFF1E2333);
  static const Color cardHover = Color(0xFF282F45);
  static const Color divider = Color(0xFF23283B);

  // Vibrant Brand Accents (Symphony Electric Violet & Cyber Cyan)
  static const Color primary = Color(0xFF8B5CF6); // Electric Violet
  static const Color primaryLight = Color(0xFFA78BFA);
  static const Color primaryDark = Color(0xFF6D28D9);
  static const Color secondary = Color(0xFF06B6D4); // Electric Cyan
  static const Color accentPink = Color(0xFFEC4899);

  // Text Colors
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Gradients
  static const LinearGradient brandGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF3B1E78), Color(0xFF0D111A)],
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
    sliderTheme: SliderThemeData(
      activeTrackColor: primaryLight,
      inactiveTrackColor: Colors.white12,
      thumbColor: Colors.white,
      trackHeight: 4.0,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
    ),
  );
}
