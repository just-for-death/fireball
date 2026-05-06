import '../contracts/music_contracts.dart';
import '../models/models.dart';
import '../models/track.dart';

abstract class MusicRepository {
  Future<List<MusicDiscoveryItem>> fetchTopSongs({
    required String countryCode,
    int limit = 20,
  });

  Future<List<MusicDiscoveryItem>> searchAll({
    required String query,
    required FireballSettings settings,
  });

  Future<List<MusicDiscoveryItem>> searchGenre(String genre);

  Future<List<Track>> collectionTracks(int collectionId);

  Future<ArtistProfile?> findArtist(String artistName);

  Future<List<MusicDiscoveryItem>> artistTopSongs(
    int artistId, {
    int limit = 20,
  });

  Future<List<MusicDiscoveryItem>> artistAlbums(
    int artistId, {
    int limit = 20,
  });

  Future<Artist> resolveArtistForFollow({
    required String artistName,
    String? fallbackArtwork,
  });

  List<Track> buildRecommendations({
    required List<Track> history,
    required List<Track> favorites,
    required List<Track> trending,
    int maxItems = 20,
  });
}
