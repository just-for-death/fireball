import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api/fireball_api.dart';
import '../models/models.dart';
import '../models/track.dart';

import '../store/providers.dart';

final downloadManagerProvider =
    StateNotifierProvider<DownloadManager, DownloadState>((ref) {
  final customPath =
      ref.watch(settingsProvider.select((s) => s.customDownloadPath));
  return DownloadManager(customPath);
});

class DownloadState {
  final Set<String> downloadedIds;
  final Set<String> activeDownloads;
  /// Full track metadata for every completed download.
  final Map<String, Track> downloadedTracks;

  const DownloadState({
    this.downloadedIds = const {},
    this.activeDownloads = const {},
    this.downloadedTracks = const {},
  });

  DownloadState copyWith({
    Set<String>? downloadedIds,
    Set<String>? activeDownloads,
    Map<String, Track>? downloadedTracks,
  }) {
    return DownloadState(
      downloadedIds: downloadedIds ?? this.downloadedIds,
      activeDownloads: activeDownloads ?? this.activeDownloads,
      downloadedTracks: downloadedTracks ?? this.downloadedTracks,
    );
  }
}

class DownloadManager extends StateNotifier<DownloadState> {
  final String? customPath;

  DownloadManager(this.customPath) : super(const DownloadState()) {
    init();
  }

  Directory? _dir;

  Future<void> init() async {
    try {
      if (customPath != null && customPath!.isNotEmpty) {
        _dir = Directory(customPath!);
      } else {
        final appDir = await getApplicationSupportDirectory();
        _dir = Directory('${appDir.path}/downloads');
      }
      if (!await _dir!.exists()) {
        await _dir!.create(recursive: true);
      }

      final files = _dir!.listSync();
      final downloaded = <String>{};
      final tracks = <String, Track>{};

      for (final f in files) {
        if (f is File && f.path.endsWith('.media')) {
          final id = f.uri.pathSegments.last.replaceAll('.media', '');
          downloaded.add(id);
          // Load sidecar metadata if present
          final sidecar = File('${_dir!.path}/$id.json');
          if (await sidecar.exists()) {
            try {
              final raw = jsonDecode(await sidecar.readAsString());
              tracks[id] = Track.fromJson(raw as Map<String, dynamic>);
            } catch (_) {}
          }
        }
      }
      state = state.copyWith(
        downloadedIds: downloaded,
        downloadedTracks: tracks,
      );
    } catch (e) {
      dev.log('DownloadManager init error: $e');
    }
  }

  bool isDownloaded(String trackId) {
    return state.downloadedIds.contains(trackId);
  }

  bool isDownloading(String trackId) {
    return state.activeDownloads.contains(trackId);
  }

  String? getLocalPath(String trackId) {
    if (_dir == null || !isDownloaded(trackId)) return null;
    return '${_dir!.path}/$trackId.media';
  }

  Future<void> removeDownload(String trackId) async {
    if (_dir == null) return;
    try {
      final file = File('${_dir!.path}/$trackId.media');
      if (await file.exists()) await file.delete();

      final sidecar = File('${_dir!.path}/$trackId.json');
      if (await sidecar.exists()) await sidecar.delete();

      final newTracks = Map<String, Track>.from(state.downloadedTracks)
        ..remove(trackId);
      state = state.copyWith(
        downloadedIds: {...state.downloadedIds}..remove(trackId),
        downloadedTracks: newTracks,
      );
    } catch (e) {
      dev.log('DownloadManager remove error: $e');
    }
  }

  /// Rewrites a direct YouTube CDN URL to route through the Invidious proxy.
  String _proxyStreamUrl(String url, String instance) {
    if (instance.isEmpty) return url;
    try {
      final uri = Uri.parse(url);
      if (!uri.host.contains('googlevideo.com')) return url;
      final base = instance.replaceAll(RegExp(r'/+$'), '');
      final newUri = Uri.parse('$base/videoplayback').replace(queryParameters: {
        ...uri.queryParameters,
        'host': uri.host,
      });
      return newUri.toString();
    } catch (_) {
      return url;
    }
  }

  Future<void> downloadTrack(
    Track track,
    FireballApi api,
    FireballSettings settings,
  ) async {
    if (_dir == null) await init();
    if (_dir == null) return;
    if (isDownloaded(track.effectiveId) || isDownloading(track.effectiveId)) {
      return;
    }

    state = state.copyWith(
      activeDownloads: {...state.activeDownloads, track.effectiveId},
    );

    try {
      String? dlUrl = track.url;
      final instance = settings.invidiousInstance.isNotEmpty
          ? settings.invidiousInstance
          : '';

      if (instance.isEmpty && track.videoId != null) {
        throw Exception('No Invidious instance configured.');
      }

      if (track.videoId != null) {
        final details = await api.getVideoDetails(track.videoId!,
            instanceUrl: instance, sid: settings.invidiousSid);
        final formats = (details['adaptiveFormats'] as List<dynamic>? ?? []);
        final bestFormat = formats.firstWhere(
          (f) => f['type']?.toString().startsWith('audio/') ?? false,
          orElse: () => formats.isEmpty ? null : formats.first,
        );
        if (bestFormat != null && bestFormat['url'] != null) {
          dlUrl = _proxyStreamUrl(bestFormat['url'] as String, instance);
        }
      } else if (dlUrl != null &&
          (dlUrl.contains('apple.com') || dlUrl.contains('itunes'))) {
        if (instance.isEmpty) throw Exception('Invidious instance required.');
        final results = await api.invidiousSearch(
            '${track.artist} ${track.title} official audio',
            instanceUrl: instance);
        if (results.isNotEmpty) {
          final match = results.first;
          final details = await api.getVideoDetails(match.videoId ?? match.id,
              instanceUrl: instance, sid: settings.invidiousSid);
          final formats = (details['adaptiveFormats'] as List<dynamic>? ?? []);
          final bestFormat = formats.firstWhere(
            (f) => f['type']?.toString().startsWith('audio/') ?? false,
            orElse: () => formats.isEmpty ? null : formats.first,
          );
          if (bestFormat != null && bestFormat['url'] != null) {
            dlUrl = _proxyStreamUrl(bestFormat['url'] as String, instance);
          }
        }
      } else if (dlUrl == null || dlUrl.isEmpty) {
        if (instance.isEmpty) throw Exception('Invidious instance required.');
        final results = await api.invidiousSearch(
            '${track.artist} ${track.title}',
            instanceUrl: instance);
        if (results.isNotEmpty) {
          final match = results.first;
          final details = await api.getVideoDetails(match.videoId ?? match.id,
              instanceUrl: instance, sid: settings.invidiousSid);
          final formats = (details['adaptiveFormats'] as List<dynamic>? ?? []);
          final bestFormat = formats.firstWhere(
            (f) => f['type']?.toString().startsWith('audio/') ?? false,
            orElse: () => formats.isEmpty ? null : formats.first,
          );
          if (bestFormat != null && bestFormat['url'] != null) {
            dlUrl = _proxyStreamUrl(bestFormat['url'] as String, instance);
          }
        }
      }

      if (dlUrl == null || dlUrl.isEmpty) {
        throw Exception('No download URL found');
      }

      final response = await http.get(Uri.parse(dlUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download: ${response.statusCode}');
      }

      final file = File('${_dir!.path}/${track.effectiveId}.media');
      await file.writeAsBytes(response.bodyBytes);

      // Write metadata sidecar so we can reconstruct track info on next launch
      final sidecar = File('${_dir!.path}/${track.effectiveId}.json');
      await sidecar.writeAsString(jsonEncode(track.toJson()));

      final newTracks = Map<String, Track>.from(state.downloadedTracks)
        ..[track.effectiveId] = track;

      state = state.copyWith(
        downloadedIds: {...state.downloadedIds, track.effectiveId},
        downloadedTracks: newTracks,
      );
    } catch (e) {
      dev.log('Download error for ${track.effectiveId}: $e');
      rethrow;
    } finally {
      state = state.copyWith(
        activeDownloads: {...state.activeDownloads}..remove(track.effectiveId),
      );
    }
  }
}
