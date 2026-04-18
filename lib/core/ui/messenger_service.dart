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
    _messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade800,
      ),
    );
  }

  void showInfo(String message,
      {Duration duration = const Duration(seconds: 3)}) {
    _messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
