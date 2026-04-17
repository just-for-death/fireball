import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../api/fireball_api.dart';
import '../models/models.dart';
import '../models/track.dart';

// ── Schema version ─────────────────────────────────────────────────────────────
const _kDbVersion = 2;

// ── Provider ────────────────────────────────────────────────────────────────────
final localStoreProvider =
    StateNotifierProvider<LocalStoreNotifier, LibraryData>((ref) {
  return LocalStoreNotifier();
});

// ── Library data model ──────────────────────────────────────────────────────────
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

// ── Notifier ────────────────────────────────────────────────────────────────────
class LocalStoreNotifier extends StateNotifier<LibraryData> {
  LocalStoreNotifier() : super(const LibraryData()) {
    _init();
  }

  // Completer that resolves once _init() finishes; all writes await this first
  // so that a late-finishing _init() cannot overwrite mutations made after init.
  final Completer<void> _ready = Completer<void>();

  // Serializes concurrent _write() calls so a slower write can never land
  // after a faster write and overwrite newer data with older data.
  Future<void> _lastWrite = Future.value();

  Future<File> get _dbFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/fireball_library.json');
  }

  // ── Init ──────────────────────────────────────────────────────────────────────
  Future<void> _init() async {
    try {
      final file = await _dbFile;
      if (!await file.exists()) {
        // No file yet — flush the default state through the serialization chain
        // so a concurrent _save() from an early mutation stays ordered.
        _ready.complete();
        _lastWrite = _lastWrite.catchError((_) {}).then((_) => _write(state));
        await _lastWrite;
        return;
      }
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      // Only apply loaded state if no mutations have arrived yet
      if (!_ready.isCompleted) {
        state = _fromJson(json);
      }
    } catch (e) {
      dev.log('LocalStore: corrupt file, starting fresh. Error: $e');
      // Backup the corrupt file so data isn't silently lost
      try {
        final file = await _dbFile;
        if (await file.exists()) {
          await file.rename('${file.path}.corrupt');
        }
      } catch (_) {}
      if (!_ready.isCompleted) {
        // Route corrupt-recovery write through the chain so it stays ordered
        // with any concurrent _save() calls.
        _ready.complete();
        _lastWrite = _lastWrite.catchError((_) {}).then((_) => _write(state));
        await _lastWrite;
      }
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  LibraryData _fromJson(Map<String, dynamic> j) {
    return LibraryData(
      settings: j['settings'] != null
          ? FireballSettings.fromJson(j['settings'] as Map<String, dynamic>)
          : const FireballSettings(),
      history: _parseTracks(j['history']),
      favorites: _parseTracks(j['favorites']),
      playlists: _parsePlaylists(j['playlists']),
      artists: _parseArtists(j['artists']),
      albums: _parseAlbums(j['albums']),
    );
  }

  Map<String, dynamic> _toJson(LibraryData data) => {
        'version': _kDbVersion,
        'settings': data.settings.toJson(),
        'history': data.history.map((t) => t.toJson()).toList(),
        'favorites': data.favorites.map((t) => t.toJson()).toList(),
        'playlists': data.playlists.map((p) => p.toJson()).toList(),
        'artists': data.artists.map((a) => a.toJson()).toList(),
        'albums': data.albums.map((a) => a.toJson()).toList(),
      };

  Future<void> _write(LibraryData data) async {
    final file = await _dbFile;
    // Write to temp file first, then rename for atomicity
    final tmpPath = '${file.path}.tmp';
    final tmp = File(tmpPath);
    await tmp.writeAsString(jsonEncode(_toJson(data)));
    // rename returns FileSystemEntity; no return value needed
    await tmp.rename(file.path);
  }

  Future<void> _save() async {
    // Mark ready immediately when a mutation occurs so _init cannot overwrite
    if (!_ready.isCompleted) _ready.complete();
    await _ready.future; // ensures any in-flight init has finished before we write
    // Chain onto the previous write so concurrent saves are serialized.
    // The closure captures `state` lazily (at execution time), so each write
    // always persists the latest state — never an older one.
    _lastWrite = _lastWrite
        .catchError((_) {}) // recover from a prior write failure
        .then((_) => _write(state));
    await _lastWrite;
  }

  // ── Settings ──────────────────────────────────────────────────────────────────
  Future<void> updateSettings(Map<String, dynamic> patch) async {
    final merged = {...state.settings.toJson(), ...patch};
    state = state.copyWith(settings: FireballSettings.fromJson(merged));
    await _save();
  }

  Future<void> setSettings(FireballSettings s) async {
    state = state.copyWith(settings: s);
    await _save();
  }

  // ── History ───────────────────────────────────────────────────────────────────
  Future<void> addHistory(Track track) async {
    final list = [track, ...state.history.where((t) => t.effectiveId != track.effectiveId)]
        .take(200)
        .toList();
    state = state.copyWith(history: list);
    await _save();
  }

  Future<void> deleteHistoryItem(String id) async {
    state = state.copyWith(
      history: state.history.where((t) => t.effectiveId != id).toList(),
    );
    await _save();
  }

  Future<void> clearHistory() async {
    state = state.copyWith(history: []);
    await _save();
  }

  // ── Favorites ─────────────────────────────────────────────────────────────────
  Future<void> addFavorite(Track track) async {
    if (state.favorites.any((f) => f.effectiveId == track.effectiveId)) return;
    state = state.copyWith(favorites: [...state.favorites, track]);
    await _save();
  }

  Future<void> deleteFavorite(String id) async {
    state = state.copyWith(
      favorites: state.favorites.where((f) => f.effectiveId != id).toList(),
    );
    await _save();
  }

  // ── Playlists ─────────────────────────────────────────────────────────────────
  Future<Playlist> createPlaylist(String title) async {
    final id = 'pl_${DateTime.now().millisecondsSinceEpoch}';
    final pl = Playlist(id: id, title: title);
    state = state.copyWith(playlists: [...state.playlists, pl]);
    await _save();
    return pl;
  }

  Future<void> addPlaylist(Playlist playlist) async {
    final existing = state.playlists.indexWhere((p) => p.id == playlist.id);
    if (existing >= 0) {
      final list = List<Playlist>.from(state.playlists);
      list[existing] = playlist;
      state = state.copyWith(playlists: list);
    } else {
      state = state.copyWith(playlists: [...state.playlists, playlist]);
    }
    await _save();
  }

  Future<void> deletePlaylist(String id) async {
    state = state.copyWith(
      playlists: state.playlists.where((p) => p.id != id).toList(),
    );
    await _save();
  }

  Future<void> addTrackToPlaylist(String playlistId, Track track) async {
    final idx = state.playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final pl = state.playlists[idx];
    if (pl.videos.any((t) => t.effectiveId == track.effectiveId)) return;
    final updated = Playlist(id: pl.id, title: pl.title, videos: [...pl.videos, track]);
    final list = List<Playlist>.from(state.playlists);
    list[idx] = updated;
    state = state.copyWith(playlists: list);
    await _save();
    _autoPushTrackToInvidious(playlistId, track);
  }

  void _autoPushTrackToInvidious(String playlistId, Track track) {
    final s = state.settings;
    if (!s.invidiousAutoPush || s.invidiousInstance.isEmpty) return;
    final invPlaylistId = s.invidiousPlaylistMappings[playlistId];
    if (invPlaylistId == null) return;
    const FireballApi()
        .pushPlaylistToInvidious(
          Playlist(id: playlistId, title: '', videos: [track]),
          instanceUrl: s.invidiousInstance,
          sid: s.invidiousSid,
          existingInvidiousId: invPlaylistId,
        )
        .catchError((Object e) {
      dev.log('Auto-push track to Invidious failed: $e');
      return '';
    });
  }

  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    final idx = state.playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final pl = state.playlists[idx];
    final updated = Playlist(
      id: pl.id,
      title: pl.title,
      videos: pl.videos.where((t) => t.effectiveId != trackId).toList(),
    );
    final list = List<Playlist>.from(state.playlists);
    list[idx] = updated;
    state = state.copyWith(playlists: list);
    await _save();
  }

  // ── Artists ───────────────────────────────────────────────────────────────────
  Future<void> addArtist(Artist artist) async {
    if (state.artists.any((a) => a.artistId == artist.artistId)) return;
    state = state.copyWith(artists: [...state.artists, artist]);
    await _save();
  }

  Future<void> deleteArtist(String id) async {
    state = state.copyWith(
      artists: state.artists.where((a) => a.artistId != id).toList(),
    );
    await _save();
  }

  // ── Albums ────────────────────────────────────────────────────────────────────
  Future<void> addAlbum(Album album) async {
    if (state.albums.any((a) => a.id == album.id)) return;
    state = state.copyWith(albums: [...state.albums, album]);
    await _save();
  }

  Future<void> deleteAlbum(String id) async {
    state = state.copyWith(
      albums: state.albums.where((a) => a.id != id).toList(),
    );
    await _save();
  }

  // ── Full restore (used by sync) ───────────────────────────────────────────────
  Future<void> restore(String libraryJson) async {
    try {
      final j = jsonDecode(libraryJson) as Map<String, dynamic>;
      state = _fromJson(j);
      await _save();
    } catch (e) {
      throw Exception('Failed to restore library: $e');
    }
  }

  String exportJson() => jsonEncode(_toJson(state));

  // ── Parsers ───────────────────────────────────────────────────────────────────
  static List<Track> _parseTracks(dynamic v) {
    if (v is! List) return [];
    final result = <Track>[];
    for (final e in v) {
      try {
        if (e is Map<String, dynamic>) result.add(Track.fromJson(e));
      } catch (err) {
        dev.log('LocalStore: skipping malformed track: $err');
      }
    }
    return result;
  }

  static List<Playlist> _parsePlaylists(dynamic v) {
    if (v is! List) return [];
    final result = <Playlist>[];
    for (final e in v) {
      try {
        if (e is Map<String, dynamic>) result.add(Playlist.fromJson(e));
      } catch (err) {
        dev.log('LocalStore: skipping malformed playlist: $err');
      }
    }
    return result;
  }

  static List<Artist> _parseArtists(dynamic v) {
    if (v is! List) return [];
    final result = <Artist>[];
    for (final e in v) {
      try {
        if (e is Map<String, dynamic>) result.add(Artist.fromJson(e));
      } catch (err) {
        dev.log('LocalStore: skipping malformed artist: $err');
      }
    }
    return result;
  }

  static List<Album> _parseAlbums(dynamic v) {
    if (v is! List) return [];
    final result = <Album>[];
    for (final e in v) {
      try {
        if (e is Map<String, dynamic>) result.add(Album.fromJson(e));
      } catch (err) {
        dev.log('LocalStore: skipping malformed album: $err');
      }
    }
    return result;
  }
}
