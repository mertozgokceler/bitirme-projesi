import 'package:flutter/material.dart';

class AppColors {
  static Color brand(ThemeData t) => t.colorScheme.primary;
  static Color onBrand(ThemeData t) => t.colorScheme.onPrimary;

  static Color navSelected(ThemeData t) => t.colorScheme.primary;
  static Color navUnselected(ThemeData t) => t.colorScheme.onSurfaceVariant;

  static Color navSplash(ThemeData t) => t.colorScheme.primary.withOpacity(0.14);
  static Color navHighlight(ThemeData t) =>
      t.colorScheme.primary.withOpacity(0.08);

  static Color badge(ThemeData t) => t.colorScheme.error;
  static Color onBadge(ThemeData t) => t.colorScheme.onError;

  static Color subtleText(ThemeData t) => t.colorScheme.onSurfaceVariant;

  static Color floatingBarBg(ThemeData t) => t.colorScheme.surface.withOpacity(
      t.brightness == Brightness.dark ? 0.92 : 0.96);

  static Color floatingBarBorder(ThemeData t) =>
      t.colorScheme.outlineVariant.withOpacity(
          t.brightness == Brightness.dark ? 0.22 : 0.35);

  static Color floatingBarShadow(ThemeData t) => Colors.black.withOpacity(
      t.brightness == Brightness.dark ? 0.55 : 0.12);

  static Color aiGlow(ThemeData t) =>
      (t.brightness == Brightness.dark
          ? t.colorScheme.secondary
          : t.colorScheme.primary)
          .withOpacity(0.55);

  static Color premiumIcon(ThemeData t) => (t.brightness == Brightness.dark
      ? t.colorScheme.tertiary
      : t.colorScheme.primary);

  static Color sheetHandle(ThemeData t) =>
      t.colorScheme.onSurfaceVariant.withOpacity(0.35);

  static Color cardBg(ThemeData t) => t.colorScheme.surface;
  static Color cardBorder(ThemeData t) =>
      t.colorScheme.outlineVariant.withOpacity(0.35);

  static Color chipBg(ThemeData t) => t.colorScheme.surfaceVariant.withOpacity(
      t.brightness == Brightness.dark ? 0.18 : 0.65);

  static Color logoBoxBg(ThemeData t) =>
      t.colorScheme.surfaceVariant.withOpacity(
          t.brightness == Brightness.dark ? 0.18 : 0.65);

  static Color fallbackAvatarBg(ThemeData t) =>
      t.colorScheme.primary.withOpacity(0.35);
  static Color onFallbackAvatar(ThemeData t) => t.colorScheme.onPrimary;

  static Color listBorder(ThemeData t) =>
      t.colorScheme.outlineVariant.withOpacity(0.45);

  static Color success(ThemeData t) => (t.brightness == Brightness.dark
      ? t.colorScheme.tertiary
      : t.colorScheme.secondary);
}

class AppGradients {
  static LinearGradient aiUserBubble(ThemeData t) => LinearGradient(
    colors: [
      t.colorScheme.primary.withOpacity(0.95),
      t.colorScheme.secondary.withOpacity(0.90),
      t.colorScheme.tertiary.withOpacity(0.85),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppBubbleStyle {
  final BoxDecoration decoration;
  final Color textColor;

  const AppBubbleStyle({
    required this.decoration,
    required this.textColor,
  });

  static AppBubbleStyle user(ThemeData t) => AppBubbleStyle(
    decoration: BoxDecoration(
      gradient: AppGradients.aiUserBubble(t),
      borderRadius: BorderRadius.circular(12),
    ),
    textColor: t.colorScheme.onPrimary,
  );

  static AppBubbleStyle ai(ThemeData t) => AppBubbleStyle(
    decoration: BoxDecoration(
      color: t.colorScheme.surfaceVariant
          .withOpacity(t.brightness == Brightness.dark ? 0.25 : 0.8),
      borderRadius: BorderRadius.circular(12),
    ),
    textColor: t.colorScheme.onSurface,
  );
}
