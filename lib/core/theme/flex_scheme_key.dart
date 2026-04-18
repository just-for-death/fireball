import 'package:flex_color_scheme/flex_color_scheme.dart';

/// Returns a persisted [FlexScheme.name] that always resolves in [flexSchemeFromKey].
String normalizeFlexSchemeKey(String? raw) {
  final s = raw?.trim() ?? '';
  if (s.isEmpty) return 'deepPurple';
  for (final v in FlexScheme.values) {
    if (v == FlexScheme.custom) continue;
    if (v.name == s) return s;
  }
  return 'deepPurple';
}
