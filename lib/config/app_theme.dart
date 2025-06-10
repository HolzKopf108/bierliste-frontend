import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get light => ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF7F7F7), // helles Grau
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFE0E0E0), // etwas dunkler als Scaffold
          foregroundColor: Colors.black87,
          elevation: 1,
        ),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF388E3C),     // Grün
          secondary: Color(0xFF8BC34A),   // Hellgrün
          surface: Color(0xFFE0E0E0),
          onPrimary: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFF388E3C), // Primary-Grün
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
        ),
        cardColor: Colors.white,
        useMaterial3: true,
      );

  static ThemeData get dark => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF1F1F1F),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF2A2A2A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF66BB6A), // neues Grün
        secondary: Color(0xFF388E3C), // satteres Grün
        surface: Color(0xFF2A2A2A),
        onPrimary: Colors.black,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF66BB6A),
          foregroundColor: Colors.black,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        ),
      ),
      cardColor: const Color(0xFF2D2D2D),
      useMaterial3: true,
    );
}
