import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import 'flex_scheme_key.dart';

/// Maps persisted [FireballSettings.flexScheme] to [FlexScheme].
FlexScheme flexSchemeFromKey(String key) {
  final k = normalizeFlexSchemeKey(key);
  for (final v in FlexScheme.values) {
    if (v.name == k) return v;
  }
  return FlexScheme.deepPurple;
}

ThemeMode themeModeFromSettings(FireballSettings s) {
  switch (s.themeMode) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

ThemeData buildFireballLightTheme(FireballSettings settings) {
  final scheme = flexSchemeFromKey(settings.flexScheme);
  var td = FlexThemeData.light(
    scheme: scheme,
    useMaterial3: true,
    useMaterial3ErrorColors: true,
  ).copyWith(
    tabBarTheme: const TabBarThemeData(tabAlignment: TabAlignment.center),
  );
  final seed = settings.accentSeedColor;
  if (seed != null) {
    final cs = ColorScheme.fromSeed(
      seedColor: Color(seed),
      brightness: Brightness.light,
    );
    td = td.copyWith(colorScheme: cs, scaffoldBackgroundColor: cs.surface);
  }
  return td;
}

ThemeData buildFireballDarkTheme(FireballSettings settings) {
  final scheme = flexSchemeFromKey(settings.flexScheme);
  var td = FlexThemeData.dark(
    scheme: scheme,
    useMaterial3: true,
    useMaterial3ErrorColors: true,
    darkIsTrueBlack: true,
  ).copyWith(
    tabBarTheme: const TabBarThemeData(tabAlignment: TabAlignment.center),
  );
  final seed = settings.accentSeedColor;
  if (seed != null) {
    final cs = ColorScheme.fromSeed(
      seedColor: Color(seed),
      brightness: Brightness.dark,
    );
    td = td.copyWith(
      colorScheme: cs,
      scaffoldBackgroundColor: const Color(0xFF050505),
    );
  }
  return td;
}

/// Curated schemes for the settings picker (key = [FlexScheme.name]).
const List<(String, String)> kFireballSchemeChoices = [
  ('deepPurple', 'Deep purple'),
  ('purpleM3', 'Purple (M3)'),
  ('blueM3', 'Blue (M3)'),
  ('tealM3', 'Teal (M3)'),
  ('material', 'Material'),
  ('indigo', 'Indigo'),
  ('green', 'Green'),
  ('redM3', 'Red (M3)'),
  ('cyanM3', 'Cyan (M3)'),
  ('materialBaseline', 'Material baseline'),
  ('shadViolet', 'Shadcn violet'),
];

/// Optional accent seeds (ARGB). First entry = use scheme default.
const List<int?> kFireballAccentPresets = [
  null,
  0xFF6750A4,
  0xFF006A6B,
  0xFF1B6EF3,
  0xFFB3261E,
  0xFF386A20,
  0xFF7D5260,
  0xFFFF6F00,
];
