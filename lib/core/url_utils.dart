/// Normalizes URLs for [CachedNetworkImage] and HTTP clients.
/// Protocol-relative URLs (`//host/...`) fail on some Android builds unless
/// resolved to `https:`.
String? normalizeHttpUrl(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty) return null;
  if (t.startsWith('//')) return 'https:$t';
  return t;
}
