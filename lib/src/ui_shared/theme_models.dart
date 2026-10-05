/// The models for theme modes and accent colors.
library;

import 'package:flutter/material.dart';

/// The base brightness or visual style for the app.
enum AppThemeMode {
  system('System', 'Match device settings', Icons.brightness_auto_outlined),
  light('Light', 'Clean light appearance', Icons.light_mode_outlined),
  dark('Dark', 'Material 3 charcoal dark', Icons.dark_mode_outlined),
  oled('OLED Black', 'Pure black for OLED screens', Icons.contrast);

  const AppThemeMode(this.label, this.subtitle, this.icon);

  final String label;
  final String subtitle;
  final IconData icon;

  /// Translates to Flutter's [ThemeMode].
  ///
  /// OLED uses [ThemeMode.dark] with a custom pitch black ThemeData.
  ThemeMode get flutterThemeMode => switch (this) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark || AppThemeMode.oled => ThemeMode.dark,
      };

  /// Parses a serialized name or returns [AppThemeMode.system] as fallback.
  static AppThemeMode fromName(String? name) => AppThemeMode.values.firstWhere(
        (mode) => mode.name.toLowerCase() == name?.toLowerCase(),
        orElse: () => AppThemeMode.system,
      );
}

/// The available accent color seeds.
enum AppAccentColor {
  blue('Classic Blue', Color(0xFF00518F)),
  red('Crimson Red', Color(0xFFD32F2F)),
  green('Emerald Green', Color(0xFF00897B)),
  purple('Royal Purple', Color(0xFF7C3AED)),
  orange('Sunset Orange', Color(0xFFEA580C)),
  pink('Rose Pink', Color(0xFFDB2777)),
  cyan('Teal Cyan', Color(0xFF0891B2)),
  amber('Cyber Amber', Color(0xFFD97706));

  const AppAccentColor(this.label, this.seedColor);

  final String label;
  final Color seedColor;

  /// Parses a serialized name or returns [AppAccentColor.blue] as fallback.
  static AppAccentColor fromName(String? name) =>
      AppAccentColor.values.firstWhere(
        (accent) => accent.name.toLowerCase() == name?.toLowerCase(),
        orElse: () => AppAccentColor.blue,
      );
}

/// The icon rendering pack used for category badges across the app.
enum AppIconPack {
  emojis('Vibrant Emojis', 'Colorful emojis in tinted squircles', Icons.emoji_emotions_outlined),
  outlined('Minimalist Outlined', 'Clean wireframe Material icons', Icons.category_outlined),
  filled('Modern Filled', 'Solid Material filled icons', Icons.category);

  const AppIconPack(this.label, this.subtitle, this.icon);

  final String label;
  final String subtitle;
  final IconData icon;

  /// Parses a serialized name or returns [AppIconPack.emojis] as fallback.
  static AppIconPack fromName(String? name) => AppIconPack.values.firstWhere(
        (pack) => pack.name.toLowerCase() == name?.toLowerCase(),
        orElse: () => AppIconPack.emojis,
      );
}

