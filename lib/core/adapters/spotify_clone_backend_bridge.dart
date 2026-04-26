import '../api/fireball_api.dart';
import '../models/models.dart';
import '../models/track.dart';
import '../utils.dart';
import 'spotify_adapters.dart';

/// Backend bridge for Fireball UI surfaces.
///
/// Keeps UI/data-shape concerns isolated from Fireball's service layer so
/// cloned UI flows can be wired without pulling Firebase-specific logic.
class FireballBackendBridge {
  FireballBackendBridge({FireballApi? api}) : _api = api ?? const FireballApi();

  final FireballApi _api;

  Future<List<Map<String, dynamic>>> fetchTopSongs({
    required String countryCode,
    int limit = 20,
  }) async {
    final rss = await _api.itunesTopSongs(countryCode, limit: limit);
    final entries = FireballApi.appleRssFeedEntries(rss);
    return HomeFeedAdapter.topChartsFromItunesFeed(entries)
        .map((e) => {
              ...e,
              'url': extractItunesUrl(
                entries.firstWhere(
                  (raw) => (raw['id']?['attributes']?['im:id'] ?? '').toString() == e['id'],
                  orElse: () => <String, dynamic>{},
                )['link'],
              ),
              'kind': 'song',
            })
        .toList()
        .cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> searchAll({
    required String query,
    required FireballSettings settings,
  }) async {
    Future<dynamic> safeItunesSearch({
      required String entity,
      required int limit,
    }) async {
      try {
        return await _api.itunesSearch(query, entity: entity, limit: limit);
      } catch (_) {
        // Keep partial iTunes results flowing if one endpoint is flaky.
        return const <String, dynamic>{'results': <dynamic>[]};
      }
    }

    final response = await Future.wait<dynamic>([
      safeItunesSearch(entity: 'song', limit: 30),
      safeItunesSearch(entity: 'mix', limit: 20),
      safeItunesSearch(entity: 'musicArtist', limit: 15),
      safeItunesSearch(entity: 'album', limit: 20),
    ]);

    final itunesResults = SearchAdapter.normalizeItunesResults(
      songData: response[0],
      mixData: response[1],
      artistData: response[2],
      albumData: response[3],
    );
    if (itunesResults.isNotEmpty) return itunesResults;

    final instance = settings.invidiousInstance;
    if (instance.isEmpty) return const <Map<String, dynamic>>[];
    final tracks = await _api.invidiousSearch(query, instanceUrl: instance);
    return tracks
        .map((t) => {
              'id': t.id,
              'videoId': t.videoId,
              'title': t.title,
              'artist': t.artist,
              'artwork': t.artwork,
              'duration': t.duration,
              'kind': 'song',
            })
        .toList()
        .cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> searchGenre(String genre) async {
    final data = await _api.itunesSearch('$genre music', limit: 30);
    return ((data['results'] as List<dynamic>? ?? [])
            .map((t) => {
                  'id': t['trackId']?.toString() ?? '',
                  'title': t['trackName'] ?? '—',
                  'artist': t['artistName'] ?? '—',
                  'album': t['collectionName'],
                  'year': t['releaseDate']?.toString().split('-').first,
                  'artwork':
                      (t['artworkUrl100'] as String?)?.replaceAll('100x100bb', '400x400bb'),
                  'url': t['previewUrl'],
                  'kind': 'song',
                })
            .toList())
        .cast<Map<String, dynamic>>();
  }

  Future<List<Track>> collectionTracks(int collectionId) async {
    final tracksRaw = await _api.itunesCollectionTracks(collectionId);
    return tracksRaw
        .map((t) => Track(
              id: t['trackId']?.toString() ?? '',
              title: t['trackName'] ?? '—',
              artist: t['artistName'] ?? '—',
              album: t['collectionName'],
              year: t['releaseDate']?.toString().split('-').first,
              artwork: (t['artworkUrl100'] as String?)?.replaceAll('100x100bb', '400x400bb'),
              url: t['previewUrl']?.toString() ?? '',
            ))
        .toList();
  }

  Future<Map<String, dynamic>?> findArtist(String artistName) {
    return _api.itunesFindArtist(artistName);
  }

  Future<List<Map<String, dynamic>>> artistTopSongs(
    int artistId, {
    int limit = 20,
  }) {
    return _api.itunesArtistTopSongs(artistId, limit: limit);
  }

  Future<List<Map<String, dynamic>>> artistAlbums(
    int artistId, {
    int limit = 20,
  }) {
    return _api.itunesArtistAlbums(artistId, limit: limit);
  }

  Future<Artist> resolveArtistForFollow({
    required String artistName,
    String? fallbackArtwork,
  }) async {
    String finalId = artistName;
    String finalName = artistName;
    String? artwork = fallbackArtwork;

    try {
      final data = await _api.itunesFindArtist(artistName);
      if (data != null) {
        finalId = data['artistId']?.toString() ?? artistName;
        finalName = data['artistName']?.toString() ?? artistName;

        if (artwork == null) {
          final id = data['artistId'] as int?;
          if (id != null) {
            final albumResults = await _api.itunesArtistAlbums(id, limit: 1);
            if (albumResults.isNotEmpty) {
              final url = albumResults.first['artworkUrl100'] as String?;
              if (url != null && url.isNotEmpty) {
                artwork = url.replaceAll('100x100bb', '600x600bb');
              }
            }
          }
        }
      }
    } catch (_) {
      // Network failures fall back to provided name/artwork.
    }

    return Artist(
      artistId: finalId,
      name: finalName,
      artwork: artwork,
    );
  }
}

