import 'dart:developer' as dev;

/// Reports non-fatal errors that we intentionally recover from.
///
/// This keeps recovery behavior unchanged (no new user-facing alerts), while
/// still leaving structured breadcrumbs for debugging and telemetry collection.
abstract final class SoftErrorReporter {
  static void report(
    String scope,
    Object error,
    StackTrace stackTrace, {
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    dev.log(
      '$scope recovered from non-fatal error',
      name: 'fireball.soft_error',
      error: error,
      stackTrace: stackTrace,
      level: 900, // warning
    );

    if (details.isNotEmpty) {
      dev.log(
        '$scope details: $details',
        name: 'fireball.soft_error',
        level: 700, // info
      );
    }
  }
}
