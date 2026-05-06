import '../adapters/spotify_clone_backend_bridge.dart';
import '../contracts/music_contracts.dart';
import '../models/models.dart';
import '../models/track.dart';
import 'music_repository.dart';

class FireballMusicRepository implements MusicRepository {
  FireballMusicRepository({FireballBackendBridge? bridge})
      : _bridge = bridge ?? FireballBackendBridge();

  final FireballBackendBridge _bridge;

  @override
  Future<List<MusicDiscoveryItem>> fetchTopSongs({
    required String countryCode,
    int limit = 20,
  }) async {
    final rows = await _bridge.fetchTopSongs(countryCode: countryCode, limit: limit);
    return rows.map(MusicDiscoveryItem.fromMap).toList();
  }

  @override
  Future<List<MusicDiscoveryItem>> searchAll({
    required String query,
    required FireballSettings settings,
  }) async {
    final rows = await _bridge.searchAll(query: query, settings: settings);
    return rows.map(MusicDiscoveryItem.fromMap).toList();
  }

  @override
  Future<List<MusicDiscoveryItem>> searchGenre(String genre) async {
    final rows = await _bridge.searchGenre(genre);
    return rows.map(MusicDiscoveryItem.fromMap).toList();
  }

  @override
  Future<List<Track>> collectionTracks(int collectionId) {
    return _bridge.collectionTracks(collectionId);
  }

  @override
  Future<ArtistProfile?> findArtist(String artistName) async {
    final data = await _bridge.findArtist(artistName);
    if (data == null) return null;
    return ArtistProfile.fromMap(data);
  }

  @override
  Future<List<MusicDiscoveryItem>> artistTopSongs(
    int artistId, {
    int limit = 20,
  }) async {
    final rows = await _bridge.artistTopSongs(artistId, limit: limit);
    return rows
        .map((t) => MusicDiscoveryItem(
              id: t['trackId']?.toString() ?? '',
              title: t['trackName']?.toString() ?? '—',
              artist: t['artistName']?.toString() ?? '—',
              artwork: (t['artworkUrl100'] as String?)
                  ?.replaceAll('100x100bb', '400x400bb'),
              url: t['previewUrl']?.toString(),
              album: t['collectionName']?.toString(),
              year: t['releaseDate']?.toString().split('-').first,
              kind: MusicItemKind.song,
            ))
        .toList();
  }

  @override
  Future<List<MusicDiscoveryItem>> artistAlbums(
    int artistId, {
    int limit = 20,
  }) async {
    final rows = await _bridge.artistAlbums(artistId, limit: limit);
    return rows
        .map((t) => MusicDiscoveryItem(
              id: t['collectionId']?.toString() ?? '',
              collectionId: t['collectionId'] is int
                  ? t['collectionId'] as int
                  : int.tryParse('${t['collectionId']}'),
              title: t['collectionName']?.toString() ?? '—',
              artist: t['artistName']?.toString() ?? '—',
              artwork: (t['artworkUrl100'] as String?)
                  ?.replaceAll('100x100bb', '400x400bb'),
              year: t['releaseDate']?.toString().split('-').first,
              trackCount: t['trackCount'] is int
                  ? t['trackCount'] as int
                  : int.tryParse('${t['trackCount']}'),
              kind: MusicItemKind.album,
            ))
        .toList();
  }

  @override
  Future<Artist> resolveArtistForFollow({
    required String artistName,
    String? fallbackArtwork,
  }) {
    return _bridge.resolveArtistForFollow(
      artistName: artistName,
      fallbackArtwork: fallbackArtwork,
    );
  }

  @override
  List<Track> buildRecommendations({
    required List<Track> history,
    required List<Track> favorites,
    required List<Track> trending,
    int maxItems = 20,
  }) {
    final seen = <String>{};
    final ordered = <Track>[];

    void pushAll(List<Track> source) {
      for (final t in source) {
        if (t.title.trim().isEmpty || t.artist.trim().isEmpty) continue;
        final key = '${t.title}::${t.artist}'.toLowerCase();
        if (seen.add(key)) ordered.add(t);
        if (ordered.length >= maxItems) return;
      }
    }

    pushAll(history);
    pushAll(favorites);
    pushAll(trending);

    return ordered.take(maxItems).toList();
  }
}
