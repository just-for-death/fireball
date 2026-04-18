import 'package:flutter/material.dart';

/// Bottom padding for scrollable shell tabs so list/grid content stays above the
/// [NavigationBar] (72) and floating [MiniPlayer] (~72) plus system gesture inset.
double shellScrollBottomPadding(BuildContext context) {
  const navBar = 72.0;
  const miniPlayer = 72.0;
  const gap = 24.0;
  return navBar + miniPlayer + gap + MediaQuery.viewPaddingOf(context).bottom;
}
