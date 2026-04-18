import '../models/models.dart';
import '../models/track.dart';

/// In-memory + JSON snapshot of the user's library (settings + collections).
class LibraryData {
  final FireballSettings settings;
  final List<Track> history;
  final List<Track> favorites;
  final List<Playlist> playlists;
  final List<Artist> artists;
  final List<Album> albums;

  const LibraryData({
    this.settings = const FireballSettings(),
    this.history = const [],
    this.favorites = const [],
    this.playlists = const [],
    this.artists = const [],
    this.albums = const [],
  });

  LibraryData copyWith({
    FireballSettings? settings,
    List<Track>? history,
    List<Track>? favorites,
    List<Playlist>? playlists,
    List<Artist>? artists,
    List<Album>? albums,
  }) =>
      LibraryData(
        settings: settings ?? this.settings,
        history: history ?? this.history,
        favorites: favorites ?? this.favorites,
        playlists: playlists ?? this.playlists,
        artists: artists ?? this.artists,
        albums: albums ?? this.albums,
      );
}
