String extractItunesUrl(dynamic link) {
  if (link is List) {
    try {
      final match = link.firstWhere((l) {
        if (l is! Map) return false;
        final attrs = l['attributes'] as Map?;
        return attrs?['type'] == 'audio/x-m4a' || attrs?['title'] == 'Preview';
      });
      return match['attributes']?['href']?.toString() ?? '';
    } catch (_) {
      return '';
    }
  } else if (link is Map) {
    return link['attributes']?['href']?.toString() ?? '';
  }
  return '';
}
