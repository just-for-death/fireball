import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:audiotags/audiotags.dart' as tags;

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

      final files = _dir!.listSync(recursive: true);
      final downloaded = <String>{};
      final tracks = <String, Track>{};

      for (final f in files) {
        if (f is File && f.path.endsWith('.json')) {
          try {
            final raw = jsonDecode(await f.readAsString());
            final track = Track.fromJson(raw as Map<String, dynamic>);
            final id = track.effectiveId;
            downloaded.add(id);
            tracks[id] = track;
          } catch (_) {}
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
      final track = state.downloadedTracks[trackId];
      if (track == null) {
        // Fallback for ID-only deletion if track metadata is missing
        final f1 = File('${_dir!.path}/$trackId.m4a');
        if (await f1.exists()) await f1.delete();
        final f2 = File('${_dir!.path}/$trackId.json');
        if (await f2.exists()) await f2.delete();
        return;
      }

      final artist = _sanitize(track.artist);
      final title = _sanitize(track.title);
      final artistDirPath = '${_dir!.path}/$artist';
      final base = '$artistDirPath/$title';

      final m4a = File('$base.m4a');
      if (await m4a.exists()) await m4a.delete();

      final lrc = File('$base.lrc');
      if (await lrc.exists()) await lrc.delete();

      final json = File('$base.json');
      if (await json.exists()) await json.delete();

      // Clean up artist directory if empty
      final artistDir = Directory(artistDirPath);
      if (await artistDir.exists()) {
        final remaining = await artistDir.list().isEmpty;
        if (remaining) {
          await artistDir.delete();
        }
      }

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
    final track = state.downloadedTracks[trackId];
    if (track == null) return null;
    final artist = _sanitize(track.artist);
    final title = _sanitize(track.title);
    return '${_dir!.path}/$artist/$title.m4a';
  }

  String? getLocalLyricsPath(String trackId) {
    if (_dir == null || !isDownloaded(trackId)) return null;
    final track = state.downloadedTracks[trackId];
    if (track == null) return null;
    final artist = _sanitize(track.artist);
    final title = _sanitize(track.title);
    final file = File('${_dir!.path}/$artist/$title.lrc');
    if (file.existsSync()) return file.path;
    return null;
  }

  Future<void> removeDownload(String trackId) async {
    await deleteDownload(trackId);
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

  String _sanitize(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
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
        }
      }

      if (dlUrl == null || dlUrl.isEmpty) {
        throw Exception('No download URL found');
      }

      final response = await http.get(Uri.parse(dlUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download: ${response.statusCode}');
      }

      // 1. Initial save as temporary ID-based file
      final tempFilePath = '${_dir!.path}/${track.effectiveId}.tmp';
      final tempFile = File(tempFilePath);
      await tempFile.writeAsBytes(response.bodyBytes);

      // 2. Enhance metadata and fetch lyrics
      final result = await _enhanceMetadataAndFetchLyrics(track, api, tempFilePath);
      final enhancedTrack = result.track;
      final lyricText = result.lyrics;

      // 3. Reorganize to Artist/Title format
      final artistName = _sanitize(enhancedTrack.artist);
      final trackTitle = _sanitize(enhancedTrack.title);
      final artistDir = Directory('${_dir!.path}/$artistName');
      if (!await artistDir.exists()) await artistDir.create(recursive: true);

      final finalFile = File('${artistDir.path}/$trackTitle.m4a');
      if (await finalFile.exists()) await finalFile.delete();
      await tempFile.rename(finalFile.path);

      // 4. Write metadata sidecar (keep sidecar next to the file for easy scanning)
      final sidecar = File('${artistDir.path}/$trackTitle.json');
      await sidecar.writeAsString(jsonEncode(enhancedTrack.toJson()));

      // 5. Save .lrc sidecar
      if (lyricText != null && lyricText.isNotEmpty) {
        final lrcFile = File('${artistDir.path}/$trackTitle.lrc');
        await lrcFile.writeAsString(lyricText);
      }

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

  Future<({Track track, String? lyrics})> _enhanceMetadataAndFetchLyrics(
      Track track, FireballApi api, String filePath) async {
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
          year: match['releaseDate']?.toString().split('-').first,
          artwork: (match['artworkUrl100']?.toString() ?? '')
              .replaceAll('100x100bb', '600x600bb'),
        );
      }
    } catch (e) {
      dev.log('iTunes metadata enhancement failed: $e');
    }

    // 2. Fetch Lyrics (.lrc)
    String? lyricText;
    try {
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
    } catch (e) {
      dev.log('Lyrics fetch failed: $e');
    }

    // 3. Embed Tags (lbdl-style)
    try {
      final audioFile = File(filePath);
      if (await audioFile.exists()) {
        List<tags.Picture> pictures = [];
        if (enhanced.artwork != null && enhanced.artwork!.startsWith('http')) {
          try {
            final artResponse = await http.get(Uri.parse(enhanced.artwork!));
            if (artResponse.statusCode == 200) {
              pictures.add(tags.Picture(
                bytes: artResponse.bodyBytes,
                mimeType: null,
                pictureType: tags.PictureType.coverFront,
              ));
            }
          } catch (_) {}
        }

        final tag = tags.Tag(
          title: enhanced.title,
          trackArtist: enhanced.artist,
          album: enhanced.album,
          year: int.tryParse(enhanced.year ?? ''),
          lyrics: lyricText,
          pictures: pictures,
        );

        await tags.AudioTags.write(audioFile.path, tag);
        dev.log('Successfully embedded tags for ${enhanced.effectiveId}');
      }
    } catch (e) {
      dev.log('Tag embedding failed: $e');
    }

    return (track: enhanced, lyrics: lyricText);
  }
}
