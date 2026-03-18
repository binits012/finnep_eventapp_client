import 'package:flutter/material.dart';

const Color _backgroundLight = Color(0xFFFFFFFF);
const Color _foregroundLight = Color(0xFF171717);
const Color _surfaceLight = Color(0xFFFFFFFF);
const Color _backgroundDark = Color(0xFF0A0A0A);
const Color _foregroundDark = Color(0xFFF9FAFB);
const Color _surfaceDark = Color(0xFF1F2937);
const Color _accent = Color(0xFF6366F1);

ThemeData get appThemeLight => ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: _accent,
        surface: _surfaceLight,
        onSurface: _foregroundLight,
        onPrimary: Colors.white,
      ),
      scaffoldBackgroundColor: _backgroundLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: _backgroundLight,
        foregroundColor: _foregroundLight,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: _surfaceLight,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _accent, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );

ThemeData get appThemeDark => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: _accent,
        surface: _surfaceDark,
        onSurface: _foregroundDark,
        onPrimary: Colors.white,
      ),
      scaffoldBackgroundColor: _backgroundDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: _backgroundDark,
        foregroundColor: _foregroundDark,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: _surfaceDark,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _accent, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
