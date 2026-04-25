// lib/core/widgets/platform_widgets.dart

import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
/// Platform‑aware Scaffold: Material on Android, Cupertino on iOS.
class PlatformScaffold extends StatelessWidget {
  const PlatformScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.backgroundColor,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return CupertinoPageScaffold(
        navigationBar: appBar is CupertinoNavigationBar
            ? appBar as CupertinoNavigationBar
            : const CupertinoNavigationBar(),
        backgroundColor: backgroundColor,
        child: SafeArea(child: body),
      );
    }
    // Android / other platforms
    return Scaffold(
      appBar: appBar,
      body: body,
      floatingActionButton: floatingActionButton,
      backgroundColor: backgroundColor,
    );
  }
}

/// Platform‑aware button: ElevatedButton for Android, CupertinoButton for iOS.
class PlatformButton extends StatelessWidget {
  const PlatformButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.color,
    this.padding,
  });

  final VoidCallback onPressed;
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return CupertinoButton(
        onPressed: onPressed,
        color: color,
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: child,
      );
    }
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: padding,
      ),
      child: child,
    );
  }
}

/// Platform‑aware switch: Material Switch on Android, CupertinoSwitch on iOS.
class PlatformSwitch extends StatelessWidget {
  const PlatformSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return CupertinoSwitch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: activeColor,
      );
    }
    return Switch(
      value: value,
      onChanged: onChanged,
      activeTrackColor: activeColor,
    );
  }
}

/// Platform‑aware dialog: Material AlertDialog vs CupertinoAlertDialog.
Future<bool?> showPlatformDialog({
  required BuildContext context,
  required String title,
  required String content,
  String confirmText = 'OK',
  String cancelText = 'Cancel',
}) async {
  if (Platform.isIOS) {
    return showCupertinoDialog<bool>(
      context: context,
      builder: (c) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          CupertinoDialogAction(
            child: Text(cancelText),
            onPressed: () => Navigator.of(c).pop(false),
          ),
          CupertinoDialogAction(
            child: Text(confirmText),
            onPressed: () => Navigator.of(c).pop(true),
          ),
        ],
      ),
    );
  }
  return showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          child: Text(cancelText),
          onPressed: () => Navigator.of(c).pop(false),
        ),
        TextButton(
          child: Text(confirmText),
          onPressed: () => Navigator.of(c).pop(true),
        ),
      ],
    ),
  );
}

/// Platform‑aware slider with a consistent look.
class PlatformSlider extends StatelessWidget {
  const PlatformSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.activeColor,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final int? divisions;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      // CupertinoSlider does not support divisions directly; we round manually.
      return CupertinoSlider(
        value: value,
        onChanged: onChanged,
        min: min,
        max: max,
        activeColor: activeColor,
      );
    }
    return Slider(
      value: value,
      onChanged: onChanged,
      min: min,
      max: max,
      divisions: divisions,
      activeColor: activeColor,
    );
  }
}

// Additional helpful widget: a sleek glass‑morphism card usable on both platforms.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.opacity = 0.12,
    this.borderRadius = 12.0,
  });

  final Widget child;
  final double opacity;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}
