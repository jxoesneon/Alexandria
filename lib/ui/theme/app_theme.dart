import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF6366F1); // Indigo accent
  static const Color canvasColor = Color(0xFF0B0F19); // Deep void background
  static const Color surfaceColor = Color(0xFF1E293B); // Nebula glass surface
  static const Color secondaryColor = Color(0xFF64748B); // Slate accent
  static const Color textColor = Color(0xFFFFFFFF); // Primary text
  static const Color honorColor = Color(0xFF22C55E); // Success / positive
  static const Color dangerColor = Color(0xFFEF4444); // Error / destructive

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: canvasColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        surface: surfaceColor,
        onSurface: textColor,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
      ),
    );
  }
}
