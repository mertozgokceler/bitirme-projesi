// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Tema sağlayıcısına erişiyoruz
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // "Görünüm" başlığı
          Text(
            'GÖRÜNÜM',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),

          // Tema seçim radyo butonları
          RadioListTile<ThemeMode>(
            title: const Text('Açık Tema'),
            secondary: const Icon(Icons.wb_sunny_outlined),
            value: ThemeMode.light,
            groupValue: themeProvider.themeMode,
            onChanged: (ThemeMode? value) {
              if (value != null) {
                themeProvider.setTheme(value);
              }
            },
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Koyu Tema'),
            secondary: const Icon(Icons.nightlight_round),
            value: ThemeMode.dark,
            groupValue: themeProvider.themeMode,
            onChanged: (ThemeMode? value) {
              if (value != null) {
                themeProvider.setTheme(value);
              }
            },
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Sistem Varsayılanı'),
            secondary: const Icon(Icons.settings_system_daydream_outlined),
            value: ThemeMode.system,
            groupValue: themeProvider.themeMode,
            onChanged: (ThemeMode? value) {
              if (value != null) {
                themeProvider.setTheme(value);
              }
            },
          ),
        ],
      ),
    );
  }
}