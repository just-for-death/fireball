class HomeFeedAdapter {
  const HomeFeedAdapter._();

  static List<Map<String, dynamic>> topChartsFromItunesFeed(
      List<dynamic> entries) {
    return entries
        .map((e) => {
              'id': (e['id']?['attributes']?['im:id'] ?? '').toString(),
              'title': e['im:name']?['label'] ?? '—',
              'artist': e['im:artist']?['label'] ?? '—',
              'artwork': e['im:image']?[2]?['label'],
            })
        .toList()
        .cast<Map<String, dynamic>>();
  }
}

class SearchAdapter {
  const SearchAdapter._();

  static List<Map<String, dynamic>> normalizeItunesResults({
    required dynamic songData,
    required dynamic mixData,
    required dynamic artistData,
    required dynamic albumData,
  }) {
    final songResults = ((songData['results'] as List<dynamic>? ?? [])
            .map((t) => {
                  'id': t['trackId']?.toString() ?? '',
                  'title': t['trackName'] ?? '—',
                  'artist': t['artistName'] ?? '—',
                  'album': t['collectionName'],
                  'year': t['releaseDate']?.toString().split('-').first,
                  'artwork': (t['artworkUrl100'] as String?)
                      ?.replaceAll('100x100bb', '400x400bb'),
                  'url': t['previewUrl'],
                  'kind': 'song',
                })
            .toList())
        .cast<Map<String, dynamic>>();

    final playlistResults = ((mixData['results'] as List<dynamic>? ?? [])
            .where((t) {
              final collectionType =
                  t['collectionType']?.toString().toLowerCase() ?? '';
              final kind = t['kind']?.toString().toLowerCase() ?? '';
              final isPlaylistish = collectionType.contains('playlist') ||
                  kind.contains('playlist') ||
                  kind.contains('mix');
              return isPlaylistish && t['collectionId'] != null;
            })
            .map((t) => {
                  'id': t['collectionId']?.toString() ?? '',
                  'collectionId': t['collectionId'],
                  'title': t['collectionName'] ?? '—',
                  'artist': t['artistName'] ?? 'Apple Music',
                  'artwork': (t['artworkUrl100'] as String?)
                      ?.replaceAll('100x100bb', '400x400bb'),
                  'trackCount': t['trackCount'],
                  'kind': 'playlist',
                })
            .toList())
        .cast<Map<String, dynamic>>();

    final artistResults = ((artistData['results'] as List<dynamic>? ?? [])
            .map((t) => {
                  'id': t['artistId']?.toString() ?? '',
                  'title': t['artistName'] ?? '—',
                  'artist': 'Artist',
                  'artwork': null,
                  'kind': 'artist',
                })
            .toList())
        .cast<Map<String, dynamic>>();

    final albumResults = ((albumData['results'] as List<dynamic>? ?? [])
            .map((t) => {
                  'id': t['collectionId']?.toString() ?? '',
                  'collectionId': t['collectionId'],
                  'title': t['collectionName'] ?? '—',
                  'artist': t['artistName'] ?? '—',
                  'artwork': (t['artworkUrl100'] as String?)
                      ?.replaceAll('100x100bb', '400x400bb'),
                  'year': t['releaseDate']?.toString().split('-').first,
                  'kind': 'album',
                })
            .toList())
        .cast<Map<String, dynamic>>();

    return <Map<String, dynamic>>[
      ...songResults,
      ...playlistResults,
      ...artistResults,
      ...albumResults,
    ];
  }
}
