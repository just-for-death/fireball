import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../diagnostics/soft_error_reporter.dart';
import '../models/track.dart';
import '../store/providers.dart';

final streamCacheManagerProvider =
    StateNotifierProvider<StreamCacheManager, StreamCacheState>((ref) {
  final manager = StreamCacheManager(ref);
  ref.listen(settingsProvider.select((s) => s.localMusicCacheLimit), (_, __) {
    manager.enforceCacheLimit();
  });
  return manager;
});

class StreamCacheState {
  final Set<String> cachedIds;
  final Set<String> activeDownloads;
  final Map<String, Track> cachedTracks;

  const StreamCacheState({
    this.cachedIds = const {},
    this.activeDownloads = const {},
    this.cachedTracks = const {},
  });

  StreamCacheState copyWith({
    Set<String>? cachedIds,
    Set<String>? activeDownloads,
    Map<String, Track>? cachedTracks,
  }) {
    return StreamCacheState(
      cachedIds: cachedIds ?? this.cachedIds,
      activeDownloads: activeDownloads ?? this.activeDownloads,
      cachedTracks: cachedTracks ?? this.cachedTracks,
    );
  }
}

class StreamCacheManager extends StateNotifier<StreamCacheState> {
  final Ref _ref;
  Directory? _dir;

  StreamCacheManager(this._ref) : super(const StreamCacheState()) {
    init();
  }

  Future<void> init() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      _dir = Directory('${appDir.path}/stream_cache');
      if (!await _dir!.exists()) {
        await _dir!.create(recursive: true);
      }

      final files = _dir!.listSync();
      final cached = <String>{};
      final tracks = <String, Track>{};

      for (final f in files) {
        if (f is File && f.path.endsWith('.m4a')) {
          final id = f.uri.pathSegments.last.replaceAll('.m4a', '');
          cached.add(id);
          final sidecar = File('${_dir!.path}/$id.json');
          if (await sidecar.exists()) {
            try {
              final raw = jsonDecode(await sidecar.readAsString());
              tracks[id] = Track.fromJson(raw as Map<String, dynamic>);
            } catch (e, st) {
              SoftErrorReporter.report(
                'stream_cache_manager.init.readSidecar',
                e,
                st,
                details: <String, Object?>{'trackId': id},
              );
            }
          }
        }
      }
      state = state.copyWith(cachedIds: cached, cachedTracks: tracks);
      _enforceLimit();
    } catch (e) {
      dev.log('StreamCacheManager init error: $e');
    }
  }

  bool isCached(String trackId) {
    return state.cachedIds.contains(trackId);
  }

  bool isCaching(String trackId) {
    return state.activeDownloads.contains(trackId);
  }

  String? getLocalPath(String trackId) {
    if (_dir == null || !isCached(trackId)) return null;
    return '${_dir!.path}/$trackId.m4a';
  }

  List<Track> get cachedTracksList => state.cachedTracks.values.toList();

  /// Public method to enforce the cache size limit after user changes settings.
  Future<void> enforceCacheLimit() async {
    await _enforceLimit();
  }
  Future<void> deleteCachedTrack(String trackId) async {
    if (_dir == null) return;
    try {
      final f = File('${_dir!.path}/$trackId.m4a');
      if (await f.exists()) await f.delete();
      final sidecar = File('${_dir!.path}/$trackId.json');
      if (await sidecar.exists()) await sidecar.delete();
      final newIds = Set<String>.from(state.cachedIds)..remove(trackId);
      final newTracks = Map<String, Track>.from(state.cachedTracks)
        ..remove(trackId);
      state = state.copyWith(cachedIds: newIds, cachedTracks: newTracks);
    } catch (e) {
      dev.log('StreamCacheManager deleteCachedTrack error: $e');
    }
  }

  Future<void> _enforceLimit() async {
    if (_dir == null) return;
    try {
      final limit = _ref.read(settingsProvider).localMusicCacheLimit;
      final files = _dir!
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.m4a'))
          .toList();

      if (files.length <= limit) return;

      // Sort by modified time (oldest first)
      files
          .sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

      final toDeleteCount = files.length - limit;
      final cachedIds = Set<String>.from(state.cachedIds);
      final cachedTracks = Map<String, Track>.from(state.cachedTracks);

      for (int i = 0; i < toDeleteCount; i++) {
        final f = files[i];
        final id = f.uri.pathSegments.last.replaceAll('.m4a', '');

        try {
          await f.delete();
          cachedIds.remove(id);
          cachedTracks.remove(id);

          final sidecar = File('${_dir!.path}/$id.json');
          if (await sidecar.exists()) {
            await sidecar.delete();
          }
        } catch (e, st) {
          SoftErrorReporter.report(
            'stream_cache_manager.enforceLimit.deleteTrack',
            e,
            st,
            details: <String, Object?>{'trackId': id},
          );
        }
      }

      state = state.copyWith(cachedIds: cachedIds, cachedTracks: cachedTracks);
    } catch (e) {
      dev.log('StreamCacheManager enforce limit error: $e');
    }
  }

  Future<void> cacheTrack(Track track, String url) async {
    if (_dir == null) await init();
    if (_dir == null) return;
    if (isCached(track.effectiveId) || isCaching(track.effectiveId)) return;

    state = state.copyWith(
      activeDownloads: {...state.activeDownloads, track.effectiveId},
    );

    try {
      final file = File('${_dir!.path}/${track.effectiveId}.m4a');
      await _downloadToFile(url, file.path);

      final sidecar = File('${_dir!.path}/${track.effectiveId}.json');
      await sidecar.writeAsString(jsonEncode(track.toJson()));

      final newTracks = Map<String, Track>.from(state.cachedTracks)
        ..[track.effectiveId] = track;
      state = state.copyWith(
        cachedIds: {...state.cachedIds, track.effectiveId},
        cachedTracks: newTracks,
      );

      await _enforceLimit();
    } catch (e) {
      dev.log('Stream cache error for ${track.effectiveId}: $e');
    } finally {
      state = state.copyWith(
        activeDownloads: {...state.activeDownloads}..remove(track.effectiveId),
      );
    }
  }

  Future<void> _downloadToFile(String url, String destinationPath) async {
    final client = http.Client();
    final request = http.Request('GET', Uri.parse(url));
    try {
      final response =
          await client.send(request).timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        throw Exception('Failed to cache stream: ${response.statusCode}');
      }
      final file = File(destinationPath);
      final sink = file.openWrite();
      try {
        await response.stream
            .timeout(const Duration(seconds: 60))
            .pipe(sink);
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }
}
