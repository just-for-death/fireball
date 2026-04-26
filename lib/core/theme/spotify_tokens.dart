import 'package:flutter/material.dart';

/// Shared UI tokens for Fireball visual rhythm.
abstract final class FireballTokens {
  static const Color green = Color(0xFF1DB954);
  static const Color greenBright = Color(0xFF1ED760);
  static const Color black = Color(0xFF121212);
  static const Color blackElevated = Color(0xFF181818);
  static const Color blackElevatedHigh = Color(0xFF242424);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFB3B3B3);

  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;

  static const double gapXs = 4;
  static const double gapSm = 8;
  static const double gapMd = 12;
  static const double gapLg = 16;
  static const double gapXl = 24;

  static const Duration motionFast = Duration(milliseconds: 180);
  static const Duration motionBase = Duration(milliseconds: 220);
  static const Duration motionSlow = Duration(milliseconds: 350);
  static const Curve motionCurve = Curves.easeOutCubic;
  static const Curve motionInCurve = Curves.easeInCubic;

  static const double navHeight = 72;
  static const double miniPlayerHeight = 72;
  static const double miniPlayerRadius = 10;
  static const double desktopPlayerRadius = 10;
}

