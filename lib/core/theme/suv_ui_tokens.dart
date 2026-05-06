import 'package:flutter/material.dart';

/// Visual tokens used to keep Suv-style UI consistent across screens.
abstract final class SuvUiTokens {
  static const double pageHorizontalPaddingPhone = 20;
  static const double sectionTitleSize = 22;
  static const double heroTitleSize = 26;

  static const double chipHeight = 38;
  static const double pillRadius = 999;

  static const double cardRadiusSm = 12;
  static const double cardRadiusMd = 16;
  static const double cardRadiusLg = 20;

  static const EdgeInsets pageHeaderPadding =
      EdgeInsets.fromLTRB(20, 28, 20, 14);

  static const Duration motionFast = Duration(milliseconds: 180);
  static const Duration motionQuick = Duration(milliseconds: 140);
  static const Curve motionCurve = Curves.easeOutCubic;

  static const double hoverAlpha = 0.07;
  static const double splashAlpha = 0.11;
  static const double highlightAlpha = 0.055;
}
