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
        if (f is File) {
          final ext = f.path.split('.').last.toLowerCase();
          if (ext == 'media' || ext == 'm4a') {
            final id = f.uri.pathSegments.last.replaceAll('.$ext', '');
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
      }
      state = state.copyWith(
        downloadedIds: downloaded,
        downloadedTracks: tracks,
      );
    } catch (e) {
      dev.log('DownloadManager init error: $e');
    }
  }

  /// Scans every registered download and removes entries whose file on disk
  /// no longer exists (e.g., user deleted the file via a file manager).
  Future<void> verifyDownloads() async {
    if (_dir == null) return;
    final staleIds = <String>{};
    for (final id in state.downloadedIds) {
      final m4a = File('${_dir!.path}/$id.m4a');
      final media = File('${_dir!.path}/$id.media');
      final exists = m4a.existsSync() || media.existsSync();
      if (!exists) staleIds.add(id);
    }
    if (staleIds.isEmpty) return;
    dev.log('DownloadManager: pruning ${staleIds.length} stale entries');
    final newIds = Set<String>.from(state.downloadedIds)..removeAll(staleIds);
    final newTracks = Map<String, Track>.from(state.downloadedTracks)
      ..removeWhere((k, _) => staleIds.contains(k));
    state = state.copyWith(downloadedIds: newIds, downloadedTracks: newTracks);
  }

  /// Deletes the audio file (and sidecar) from disk **and** removes the
  /// registry entry.  Use this when the user explicitly requests deletion.
  Future<void> deleteDownload(String trackId) async {
    if (_dir == null) return;
    try {
      final m4aFile = File('${_dir!.path}/$trackId.m4a');
      if (await m4aFile.exists()) await m4aFile.delete();

      final mediaFile = File('${_dir!.path}/$trackId.media');
      if (await mediaFile.exists()) await mediaFile.delete();

      final lrcFile = File('${_dir!.path}/$trackId.lrc');
      if (await lrcFile.exists()) await lrcFile.delete();

      final sidecar = File('${_dir!.path}/$trackId.json');
      if (await sidecar.exists()) await sidecar.delete();

      final newTracks = Map<String, Track>.from(state.downloadedTracks)
        ..remove(trackId);
      state = state.copyWith(
        downloadedIds: {...state.downloadedIds}..remove(trackId),
        downloadedTracks: newTracks,
      );
    } catch (e) {
      dev.log('DownloadManager deleteDownload error: $e');
    }
  }

  List<Track> get downloadedTracksList =>
      state.downloadedTracks.values.toList();

  bool isDownloaded(String trackId) {
    return state.downloadedIds.contains(trackId);
  }

  bool isDownloading(String trackId) {
    return state.activeDownloads.contains(trackId);
  }

  String? getLocalPath(String trackId) {
    if (_dir == null || !isDownloaded(trackId)) return null;
    final m4a = File('${_dir!.path}/$trackId.m4a');
    if (m4a.existsSync()) return m4a.path;
    return '${_dir!.path}/$trackId.media';
  }

  String? getLocalLyricsPath(String trackId) {
    if (_dir == null || !isDownloaded(trackId)) return null;
    final file = File('${_dir!.path}/$trackId.lrc');
    if (file.existsSync()) return file.path;
    return null;
  }

  Future<void> removeDownload(String trackId) async {
    if (_dir == null) return;
    try {
      final mediaFile = File('${_dir!.path}/$trackId.media');
      if (await mediaFile.exists()) await mediaFile.delete();

      final m4aFile = File('${_dir!.path}/$trackId.m4a');
      if (await m4aFile.exists()) await m4aFile.delete();

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
        final isHigh = settings.highQuality;
        formats.sort((a, b) {
          final bitA = int.tryParse(a['bitrate']?.toString() ?? '0') ?? 0;
          final bitB = int.tryParse(b['bitrate']?.toString() ?? '0') ?? 0;
          return isHigh ? bitB.compareTo(bitA) : bitA.compareTo(bitB);
        });

        final bestFormat = formats.firstWhere(
          (f) => f['type']?.toString().startsWith('audio/mp4') ?? false,
          orElse: () => formats.firstWhere(
            (f) => f['type']?.toString().startsWith('audio/') ?? false,
            orElse: () => formats.isEmpty ? null : formats.first,
          ),
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
            (f) => f['type']?.toString().startsWith('audio/mp4') ?? false,
            orElse: () => formats.firstWhere(
              (f) => f['type']?.toString().startsWith('audio/') ?? false,
              orElse: () => formats.isEmpty ? null : formats.first,
            ),
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
            (f) => f['type']?.toString().startsWith('audio/mp4') ?? false,
            orElse: () => formats.firstWhere(
              (f) => f['type']?.toString().startsWith('audio/') ?? false,
              orElse: () => formats.isEmpty ? null : formats.first,
            ),
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

      final file = File('${_dir!.path}/${track.effectiveId}.m4a');
      await file.writeAsBytes(response.bodyBytes);

      // Enhance metadata and fetch lyrics
      final enhancedTrack = await _enhanceMetadataAndFetchLyrics(track, api);

      // Write metadata sidecar
      final sidecar = File('${_dir!.path}/${enhancedTrack.effectiveId}.json');
      await sidecar.writeAsString(jsonEncode(enhancedTrack.toJson()));

      final newTracks = Map<String, Track>.from(state.downloadedTracks)
        ..[enhancedTrack.effectiveId] = enhancedTrack;

      state = state.copyWith(
        downloadedIds: {...state.downloadedIds, enhancedTrack.effectiveId},
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

  Future<Track> _enhanceMetadataAndFetchLyrics(
      Track track, FireballApi api) async {
    Track enhanced = track;

    // 1. iTunes Metadata Enhancement
    try {
      final term = '${track.artist} ${track.title}';
      final results = await api.itunesSearch(term, limit: 3);
      final raw = results['results'] as List<dynamic>? ?? [];

      if (raw.isNotEmpty) {
        final match = raw.first;
        enhanced = enhanced.copyWith(
          title: match['trackName']?.toString() ?? track.title,
          artist: match['artistName']?.toString() ?? track.artist,
          album: match['collectionName']?.toString() ?? track.album,
          artwork: (match['artworkUrl100']?.toString() ?? '')
              .replaceAll('100x100bb', '600x600bb'),
        );
      }
    } catch (e) {
      dev.log('iTunes metadata enhancement failed: $e');
    }

    // 2. Fetch and save Lyrics (.lrc)
    try {
      String? lyricText;

      // LRCLIB
      try {
        final lrclibData = await api.lrclibGet(enhanced.artist, enhanced.title,
            album: enhanced.album);
        if (lrclibData != null && lrclibData is Map) {
          final synced = lrclibData['syncedLyrics']?.toString();
          final plain = lrclibData['plainLyrics']?.toString();
          if (synced != null && synced.trim().isNotEmpty) {
            lyricText = synced.trim();
          } else if (plain != null && plain.trim().isNotEmpty) {
            lyricText = plain.trim();
          }
        }
      } catch (_) {}

      // Fallback to NetEase
      if (lyricText == null) {
        try {
          final q = '${enhanced.artist} ${enhanced.title}'.trim();
          final searchData = await api.lyricsSearch(q);
          if (searchData != null && searchData['result'] != null) {
            final songs = searchData['result']['songs'] as List<dynamic>? ?? [];
            if (songs.isNotEmpty) {
              final songId = songs.first['id']?.toString();
              if (songId != null) {
                final lData = await api.lyricsGet(songId);
                if (lData != null) {
                  for (final key in ['klyric', 'lrc']) {
                    final lrc = (lData[key] as Map?)?['lyric']?.toString();
                    if (lrc != null && lrc.trim().isNotEmpty) {
                      lyricText = lrc.trim();
                      break;
                    }
                  }
                }
              }
            }
          }
        } catch (_) {}
      }

      if (lyricText != null && lyricText.isNotEmpty) {
        final lrcFile = File('${_dir!.path}/${enhanced.effectiveId}.lrc');
        await lrcFile.writeAsString(lyricText);
      }
    } catch (e) {
      dev.log('Lyrics fetch failed: $e');
    }

    return enhanced;
  }
}
