import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color canvasColor = Color(0xFF141518);
  static const Color surfaceColor = Color(0xFF1F2125);
  static const Color primaryAccent = Color(0xFFD4A373);
  static const Color secondaryColor = Color(0xFF8D949D);
  static const Color textColor = Color(0xFFE5E7EB);
  static const Color honorColor = Color(0xFF4A7C59);
  static const Color dangerColor = Color(0xFFA93C3C);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: canvasColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryAccent,
        surface: surfaceColor,
        onSurface: textColor,
        error: dangerColor,
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.newsreader(
            fontSize: 40,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.5,
            color: textColor),
        displayMedium: GoogleFonts.newsreader(
            fontSize: 28,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.5,
            color: textColor),
        bodyLarge:
            GoogleFonts.inter(fontSize: 16, height: 1.6, color: textColor),
        bodyMedium:
            GoogleFonts.inter(fontSize: 14, height: 1.5, color: textColor),
        labelSmall: GoogleFonts.jetBrainsMono(
            fontSize: 11, letterSpacing: 0.5, color: secondaryColor),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: Colors.transparent,
        backgroundColor: surfaceColor,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
            (Set<WidgetState> states) {
          final color = states.contains(WidgetState.selected)
              ? primaryAccent
              : secondaryColor;
          return GoogleFonts.jetBrainsMono(
              fontSize: 11, color: color, fontWeight: FontWeight.w500);
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
            (Set<WidgetState> states) {
          final color = states.contains(WidgetState.selected)
              ? primaryAccent
              : secondaryColor;
          return IconThemeData(color: color, size: 24);
        }),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF9F8F6),
      colorScheme: const ColorScheme.light(
        primary: primaryAccent,
        surface: Color(0xFFF3F1ED),
        onSurface: Color(0xFF141518),
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.newsreader(
            fontSize: 40,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.5,
            color: canvasColor),
        displayMedium: GoogleFonts.newsreader(
            fontSize: 28,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.5,
            color: canvasColor),
        bodyLarge:
            GoogleFonts.inter(fontSize: 16, height: 1.6, color: canvasColor),
        bodyMedium:
            GoogleFonts.inter(fontSize: 14, height: 1.5, color: canvasColor),
        labelSmall: GoogleFonts.jetBrainsMono(
            fontSize: 11, letterSpacing: 0.5, color: secondaryColor),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: Colors.transparent,
        backgroundColor: const Color(0xFFF3F1ED),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
            (Set<WidgetState> states) {
          final color = states.contains(WidgetState.selected)
              ? primaryAccent
              : secondaryColor;
          return GoogleFonts.jetBrainsMono(
              fontSize: 11, color: color, fontWeight: FontWeight.w500);
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
            (Set<WidgetState> states) {
          final color = states.contains(WidgetState.selected)
              ? primaryAccent
              : secondaryColor;
          return IconThemeData(color: color, size: 24);
        }),
      ),
    );
  }
}
