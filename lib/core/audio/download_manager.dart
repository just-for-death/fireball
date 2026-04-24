import 'dart:async';
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
  final customPath = ref.watch(settingsProvider.select((s) => s.customDownloadPath));
  return DownloadManager(customPath);
});

class DownloadState {
  final Set<String> downloadedIds;
  final Set<String> activeDownloads;

  const DownloadState({
    this.downloadedIds = const {},
    this.activeDownloads = const {},
  });

  DownloadState copyWith({
    Set<String>? downloadedIds,
    Set<String>? activeDownloads,
  }) {
    return DownloadState(
      downloadedIds: downloadedIds ?? this.downloadedIds,
      activeDownloads: activeDownloads ?? this.activeDownloads,
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
      for (final f in files) {
        if (f is File && f.path.endsWith('.media')) {
          final id = f.uri.pathSegments.last.replaceAll('.media', '');
          downloaded.add(id);
        }
      }
      state = state.copyWith(downloadedIds: downloaded);
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
      if (await file.exists()) {
        await file.delete();
      }
      state = state.copyWith(
        downloadedIds: {...state.downloadedIds}..remove(trackId),
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

      state = state.copyWith(
        downloadedIds: {...state.downloadedIds, track.effectiveId},
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
