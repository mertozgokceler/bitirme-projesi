import 'package:flutter/material.dart';

ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,

  colorScheme: const ColorScheme.light(
    primary: Color(0xFF6750A4),
    onPrimary: Colors.white,

    secondary: Color(0xFF8E7CC3),
    onSecondary: Colors.white,

    background: Color(0xFFF6F7FB),
    onBackground: Color(0xFF1C1C1E),

    surface: Color(0xFFFBFBFD),
    onSurface: Color(0xFF1C1C1E),

    outline: Color(0xFFE3E5EA),
    error: Color(0xFFB3261E),
    onError: Colors.white,
  ),

  scaffoldBackgroundColor: const Color(0xFFF6F7FB),

  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFFF6F7FB),
    foregroundColor: Color(0xFF1C1C1E),
    elevation: 0,
    centerTitle: true,
  ),

  dividerTheme: const DividerThemeData(
    color: Color(0xFFE3E5EA),
    thickness: 1,
  ),

  cardTheme: CardTheme(
    color: const Color(0xFFFBFBFD),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFFE3E5EA)),
    ),
  ),

  textTheme: const TextTheme(
    bodyLarge: TextStyle(color: Color(0xFF1C1C1E)),
    bodyMedium: TextStyle(color: Color(0xFF2C2C2E)),
    bodySmall: TextStyle(color: Color(0xFF6E6E73)),
  ),
);
