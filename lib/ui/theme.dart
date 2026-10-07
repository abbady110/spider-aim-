import 'package:flutter/material.dart';

const spiderBackground = Color(0xFF0A1015);
const spiderSurface = Color(0xFF131D25);
const spiderTeal = Color(0xFF64E4D1);
const spiderMuted = Color(0xFF9DADB8);

ThemeData spiderTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: spiderTeal,
    brightness: Brightness.dark,
    surface: spiderSurface,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme.copyWith(primary: spiderTeal),
    scaffoldBackgroundColor: spiderBackground,
    cardTheme: const CardThemeData(
      color: spiderSurface,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: spiderBackground,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF0D151C),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    dividerColor: const Color(0xFF253540),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: spiderSurface,
      indicatorColor: Color(0xFF23463F),
    ),
  );
}
