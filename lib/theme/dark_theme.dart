import 'package:flutter/material.dart';

ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,

  colorScheme: const ColorScheme.dark(
    primary: Color(0xFFB69DF8),
    onPrimary: Color(0xFF1A1325),

    secondary: Color(0xFF9A82DB),
    onSecondary: Color(0xFF1A1325),

    background: Color(0xFF0E0E11),
    onBackground: Color(0xFFECECF1),

    surface: Color(0xFF16161A),
    onSurface: Color(0xFFECECF1),

    outline: Color(0xFF2A2A30),
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
  ),

  scaffoldBackgroundColor: const Color(0xFF0E0E11),

  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF0E0E11),
    foregroundColor: Color(0xFFECECF1),
    elevation: 0,
    centerTitle: true,
  ),

  dividerTheme: const DividerThemeData(
    color: Color(0xFF2A2A30),
    thickness: 1,
  ),

  cardTheme: CardTheme(
    color: const Color(0xFF16161A),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFF2A2A30)),
    ),
  ),

  textTheme: const TextTheme(
    bodyLarge: TextStyle(color: Color(0xFFECECF1)),
    bodyMedium: TextStyle(color: Color(0xFFD1D1D6)),
    bodySmall: TextStyle(color: Color(0xFF9A9AA0)),
  ),
);
