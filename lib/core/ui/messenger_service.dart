import 'package:flutter/material.dart';

/// A lightweight singleton that lets non-UI layers (store, sync) surface
/// error messages as SnackBars without needing a BuildContext.
///
/// Attach this at the root MaterialApp level via a Builder:
///
/// ```dart
/// Builder(builder: (context) {
///   MessengerService.instance.attach(ScaffoldMessenger.of(context));
///   return child;
/// })
/// ```
class MessengerService {
  MessengerService._();
  static final MessengerService instance = MessengerService._();

  ScaffoldMessengerState? _messenger;

  /// Call once from the root Builder after MaterialApp has been created.
  void attach(ScaffoldMessengerState messenger) {
    _messenger = messenger;
  }

  void showError(String message,
      {Duration duration = const Duration(seconds: 4)}) {
    _show(
      message,
      duration: duration,
      backgroundColor: Colors.red.shade800,
      icon: Icons.error_outline_rounded,
    );
  }

  void showInfo(String message,
      {Duration duration = const Duration(seconds: 3)}) {
    _show(
      message,
      duration: duration,
      icon: Icons.info_outline_rounded,
    );
  }

  void showSuccess(String message,
      {Duration duration = const Duration(seconds: 2)}) {
    _show(
      message,
      duration: duration,
      backgroundColor: Colors.green.shade700,
      icon: Icons.check_circle_outline_rounded,
    );
  }

  void _show(
    String message, {
    required Duration duration,
    Color? backgroundColor,
    IconData? icon,
  }) {
    final messenger = _messenger;
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: duration,
        behavior: SnackBarBehavior.floating,
        backgroundColor: backgroundColor,
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
