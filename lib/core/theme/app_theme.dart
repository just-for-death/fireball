import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import 'flex_scheme_key.dart';
import 'fireball_tokens.dart';

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
  final cs = td.colorScheme;
  return td.copyWith(
    colorScheme: cs,
    textTheme: td.textTheme.apply(
      bodyColor: cs.onSurface,
      displayColor: cs.onSurface,
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: cs.primary.withValues(alpha: 0.2),
      backgroundColor: cs.surfaceContainer,
      elevation: 0,
      height: FireballTokens.navHeight,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight:
              states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ),
  );
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
  final cs = td.colorScheme.copyWith(
    surface: FireballTokens.black,
    surfaceContainer: FireballTokens.blackElevated,
    surfaceContainerHigh: const Color(0xFF202020),
  );
  return td.copyWith(
    colorScheme: cs,
    scaffoldBackgroundColor: const Color(0xFF0A0A0A),
    textTheme: td.textTheme.apply(
      bodyColor: FireballTokens.textPrimary,
      displayColor: FireballTokens.textPrimary,
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: cs.primary.withValues(alpha: 0.22),
      backgroundColor: FireballTokens.black,
      elevation: 0,
      height: FireballTokens.navHeight,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight:
              states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ),
    cardTheme: const CardThemeData(
      color: FireballTokens.blackElevated,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
  );
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
