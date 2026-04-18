import '../models/models.dart';
import '../models/track.dart';
import 'library_data.dart';

/// Merges two libraries so two devices can sync via WebDAV without one side
/// wiping the other's edits (last-write-wins on the file, merge in-app).
LibraryData mergeLibraryData(LibraryData local, LibraryData remote) {
  return LibraryData(
    settings: local.settings.mergeSharedFromRemote(remote.settings),
    history: _mergeHistory(local.history, remote.history),
    favorites: _mergeFavorites(local.favorites, remote.favorites),
    playlists: _mergePlaylists(local.playlists, remote.playlists),
    artists: _mergeArtists(local.artists, remote.artists),
    albums: _mergeAlbums(local.albums, remote.albums),
  );
}

List<Track> _mergeHistory(List<Track> local, List<Track> remote) {
  final seen = <String>{};
  final out = <Track>[];
  for (final t in [...remote, ...local]) {
    if (seen.add(t.effectiveId)) out.add(t);
    if (out.length >= 200) break;
  }
  return out;
}

List<Track> _mergeFavorites(List<Track> local, List<Track> remote) {
  final map = <String, Track>{};
  for (final t in local) {
    map[t.effectiveId] = t;
  }
  for (final t in remote) {
    map[t.effectiveId] = t;
  }
  return map.values.toList();
}

List<Playlist> _mergePlaylists(List<Playlist> local, List<Playlist> remote) {
  final map = <String, Playlist>{for (final p in local) p.id: p};
  for (final p in remote) {
    final existing = map[p.id];
    if (existing == null) {
      map[p.id] = p;
    } else {
      final ids = <String>{};
      final videos = <Track>[];
      for (final t in [...existing.videos, ...p.videos]) {
        if (ids.add(t.effectiveId)) videos.add(t);
      }
      final title = existing.title.isNotEmpty ? existing.title : p.title;
      map[p.id] = Playlist(id: p.id, title: title, videos: videos);
    }
  }
  return map.values.toList();
}

List<Artist> _mergeArtists(List<Artist> local, List<Artist> remote) {
  final map = <String, Artist>{for (final a in local) a.artistId: a};
  for (final a in remote) {
    map[a.artistId] = a;
  }
  return map.values.toList();
}

List<Album> _mergeAlbums(List<Album> local, List<Album> remote) {
  final map = <String, Album>{for (final a in local) a.id: a};
  for (final a in remote) {
    map[a.id] = a;
  }
  return map.values.toList();
}
