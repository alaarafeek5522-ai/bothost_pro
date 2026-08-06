import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primary = Color(0xFF6C63FF);
  static const Color secondary = Color(0xFF00BFA6);
  static const Color dark = Color(0xFF1A1A2E);
  static const Color card = Color(0xFF16213E);
  static const Color error = Color(0xFFE94560);
  
  // Terminal colors
  static const Color terminalBg = Color(0xFF0D1117);
  static const Color terminalGreen = Color(0xFF3FB950);
  static const Color terminalYellow = Color(0xFFD29922);
  static const Color terminalRed = Color(0xFFF85149);
  static const Color terminalBlue = Color(0xFF58A6FF);

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: dark,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: secondary,
      surface: card,
      error: error,
    ),
    textTheme: GoogleFonts.cairoTextTheme(ThemeData.dark().textTheme),
    appBarTheme: const AppBarTheme(
      backgroundColor: dark,
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardTheme(
      color: card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
