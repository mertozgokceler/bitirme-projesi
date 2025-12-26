// lib/providers/theme_provider.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    _loadTheme();
  }

  // Kayıtlı temayı SharedPreferences'tan yükler
  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    // Kayıtlı bir tema yoksa, varsayılan olarak 'sistem' temasını kullanır (index 2)
    final themeIndex = prefs.getInt('themeMode') ?? 2;
    _themeMode = ThemeMode.values[themeIndex];
    notifyListeners();
  }

  // Yeni temayı ayarlar ve SharedPreferences'a kaydeder
  Future<void> setTheme(ThemeMode themeMode) async {
    if (_themeMode == themeMode) return;

    _themeMode = themeMode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', themeMode.index);
  }
}