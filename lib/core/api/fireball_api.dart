import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import '../models/track.dart';

/// Standalone API client for Fireball.
///
/// No server required — all calls go directly to external services:
///   • iTunes Search API
///   • LRCLIB (lyrics)
///   • NetEase Music (lyrics fallback)
///   • Invidious (video search + stream resolution)
///   • ListenBrainz (direct)
///   • Last.fm (validation)
///   • Ollama (local AI, user-configured URL)
class FireballApi {
  const FireballApi();

  // ── Core fetch helper ──────────────────────────────────────────────────────
  Future<dynamic> _request(
    String method,
    String url, {
    Map<String, String>? headers,
    dynamic body,
  }) async {
    final uri = Uri.parse(url);
    final requestHeaders = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'Fireball/1.0 (https://github.com/fireball)',
      ...?headers,
    };

    try {
      final http.Response res;
      const timeout = Duration(seconds: 15);

      switch (method.toUpperCase()) {
        case 'POST':
          res = await http
              .post(uri, headers: requestHeaders,
                  body: body != null ? json.encode(body) : null)
              .timeout(timeout);
          break;
        case 'PUT':
          res = await http
              .put(uri, headers: requestHeaders,
                  body: body != null ? json.encode(body) : null)
              .timeout(timeout);
          break;
        case 'DELETE':
          res = await http.delete(uri, headers: requestHeaders).timeout(timeout);
          break;
        default:
          res = await http.get(uri, headers: requestHeaders).timeout(timeout);
      }

      final dynamic data = _safeDecode(res.body);

      if (res.statusCode >= 400) {
        String message = 'Error (${res.statusCode})';
        if (data is Map && data.containsKey('error')) {
          message = data['error'].toString();
          if (data.containsKey('detail')) message += ': ${data['detail']}';
        }
        throw Exception(message);
      }

      return data;
    } catch (e) {
      if (e is http.ClientException || e is Exception) rethrow;
      throw Exception('Network Error: $e');
    }
  }

  dynamic _safeDecode(String body) {
    if (body.isEmpty) return null;
    try {
      return json.decode(body);
    } catch (_) {
      return body;
    }
  }

  Future<dynamic> _get(String url, {Map<String, String>? headers}) =>
      _request('GET', url, headers: headers);

  Future<dynamic> _post(String url, Map<String, dynamic> body,
          {Map<String, String>? headers}) =>
      _request('POST', url, body: body, headers: headers);

  // ── iTunes ─────────────────────────────────────────────────────────────────
  static const _itunesBase = 'https://itunes.apple.com';

  Future<dynamic> itunesSearch(String term, {int limit = 30}) async {
    return _get(
      '$_itunesBase/search?term=${Uri.encodeComponent(term)}&entity=song&limit=$limit',
    );
  }

  Future<dynamic> itunesTopSongs(String cc, {int limit = 30}) async {
    return _get(
      '$_itunesBase/$cc/rss/topsongs/limit=$limit/json',
    );
  }

  /// Album art from iTunes Search when Invidious (or other sources) have none.
  /// Returns a ~600×600 URL, or null.
  Future<String?> itunesArtworkForTrack(String artist, String title,
      {int limit = 12}) async {
    final term = '$artist $title'.trim();
    if (term.length < 2) return null;
    try {
      final data = await itunesSearch(term, limit: limit);
      final raw = data['results'] as List<dynamic>? ?? [];
      if (raw.isEmpty) return null;
      final tl = title.toLowerCase();
      final al = artist.toLowerCase();
      for (final t in raw) {
        final tn = (t['trackName'] as String? ?? '').toLowerCase();
        final an = (t['artistName'] as String? ?? '').toLowerCase();
        final url = t['artworkUrl100'] as String?;
        if (url == null || url.isEmpty) continue;
        final titleMatch =
            tn.contains(tl) || tl.contains(tn) || tl.runes.length < 4;
        final artistMatch =
            an.contains(al) || al.contains(an) || al.runes.length < 3;
        if (titleMatch && artistMatch) {
          return url.replaceAll('100x100bb', '600x600bb');
        }
      }
      final url = raw.first['artworkUrl100'] as String?;
      if (url == null || url.isEmpty) return null;
      return url.replaceAll('100x100bb', '600x600bb');
    } catch (_) {
      return null;
    }
  }

  // ── LRCLIB ────────────────────────────────────────────────────────────────
  static const _lrclibBase = 'https://lrclib.net/api';
  static const _lrclibHeaders = {'Lrclib-Client': 'Fireball Music Player'};

  Future<dynamic> lrclibGet(String artist, String title,
      {String? album, int? duration}) async {
    final params = {
      'artist_name': artist,
      'track_name': title,
      if (album != null) 'album_name': album,
      if (duration != null) 'duration': '$duration',
    };
    final qs =
        params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    return _get('$_lrclibBase/get?$qs', headers: _lrclibHeaders);
  }

  Future<dynamic> lrclibSearch(String query) async {
    return _get('$_lrclibBase/search?q=${Uri.encodeComponent(query)}',
        headers: _lrclibHeaders);
  }

  /// Structured field search — more precise than a combined [query] string.
  Future<dynamic> lrclibSearchByFields(String trackName, String artistName) async {
    final qs =
        'track_name=${Uri.encodeComponent(trackName)}&artist_name=${Uri.encodeComponent(artistName)}';
    return _get('$_lrclibBase/search?$qs', headers: _lrclibHeaders);
  }

  // ── NetEase (lyrics fallback for Asian music) ─────────────────────────────
  static const _neteaseBase = 'https://music.163.com/api';

  Future<dynamic> lyricsSearch(String query) async {
    return _get(
      '$_neteaseBase/search/get?s=${Uri.encodeComponent(query)}&type=1&limit=10',
    );
  }

  Future<dynamic> lyricsGet(String id) async {
    return _get('$_neteaseBase/song/lyric?id=$id&lv=1&kv=1&tv=-1');
  }

  // ── Invidious ─────────────────────────────────────────────────────────────
  Future<List<Track>> invidiousSearch(
    String query, {
    required String instanceUrl,
    String type = 'video',
  }) async {
    if (instanceUrl.isEmpty) return [];
    final base = instanceUrl.replaceAll(RegExp(r'/+$'), '');
    final data = await _get(
      '$base/api/v1/search?q=${Uri.encodeComponent(query)}&type=$type',
    );
    if (data is! List) return [];
    return data
        .map((v) => Track(
              id: v['videoId'] ?? v['id'] ?? '',
              videoId: v['videoId']?.toString(),
              title: v['title'] ?? '',
              artist: v['author'] ?? v['artist'] ?? '',
              artwork: () {
                final vt = v['videoThumbnails'];
                if (vt is List && vt.isNotEmpty && vt[0] is Map) {
                  return vt[0]['url'] as String?;
                }
                final th = v['thumbnails'];
                if (th is List && th.isNotEmpty && th[0] is Map) {
                  return th[0]['url'] as String?;
                }
                return null;
              }(),
              duration: v['lengthSeconds'] ?? v['duration'],
            ))
        .toList();
  }

  Future<Map<String, dynamic>> getVideoDetails(
    String videoId, {
    required String instanceUrl,
    String? sid,
  }) async {
    final base = instanceUrl.replaceAll(RegExp(r'/+$'), '');
    final headers = <String, String>{
      if (sid != null) 'Cookie': 'SID=$sid',
    };
    return await _get('$base/api/v1/videos/$videoId', headers: headers)
        as Map<String, dynamic>;
  }

  /// Logs into an Invidious instance by form-posting to /login (the web UI
  /// endpoint), then extracting the SID from the Set-Cookie response header.
  /// This matches how elysium-server handles login and works on instances that
  /// have the JSON API /api/v1/auth/signin endpoint disabled.
  Future<Map<String, dynamic>> invidiousLogin(
    String instanceUrl,
    String username,
    String password,
  ) async {
    final base = instanceUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/login');

    // Use dart:io HttpClient so we can disable redirect-following
    // and read the Set-Cookie from the 302 response directly.
    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..autoUncompress = true;

    try {
      final body =
          'email=${Uri.encodeComponent(username)}'
          '&password=${Uri.encodeComponent(password)}'
          '&action=signin';

      final req = await httpClient.postUrl(uri);
      req.followRedirects = false; // read SID from the 302 Set-Cookie directly
      req.headers.set(HttpHeaders.contentTypeHeader,
          'application/x-www-form-urlencoded');
      req.headers.set(HttpHeaders.userAgentHeader, 'Fireball/1.0');
      req.write(body);

      final resp = await req.close().timeout(const Duration(seconds: 15));
      await resp.drain<void>();

      // Try structured cookie objects first
      String sid = '';
      for (final cookie in resp.cookies) {
        if (cookie.name.toUpperCase() == 'SID') {
          sid = cookie.value;
          break;
        }
      }

      // Fallback: scan raw Set-Cookie header strings
      if (sid.isEmpty) {
        final rawHeaders = resp.headers[HttpHeaders.setCookieHeader] ?? [];
        final joined = rawHeaders.join('; ');
        final m =
            RegExp(r'SID=([^;,\s]+)', caseSensitive: false).firstMatch(joined);
        if (m != null) sid = m.group(1)!;
      }

      if (sid.isEmpty) {
        final code = resp.statusCode;
        if (code == 401 || code == 403) {
          throw Exception('Wrong credentials.');
        }
        throw Exception(
            'Login failed — wrong credentials or login is disabled on this instance.');
      }

      return {'sid': sid, 'username': username, 'instanceUrl': base};
    } finally {
      httpClient.close(force: true);
    }
  }

  Future<List<dynamic>> getInvidiousPlaylists({
    required String instanceUrl,
    String? sid,
  }) async {
    final base = instanceUrl.replaceAll(RegExp(r'/+$'), '');
    final headers = <String, String>{
      if (sid != null) 'Cookie': 'SID=$sid',
    };
    final data = await _get('$base/api/v1/auth/playlists', headers: headers);
    return data as List<dynamic>;
  }

  Future<Playlist> getInvidiousPlaylistDetail(
    String playlistId, {
    required String instanceUrl,
    String? sid,
  }) async {
    final base = instanceUrl.replaceAll(RegExp(r'/+$'), '');
    final headers = <String, String>{
      if (sid != null) 'Cookie': 'SID=$sid',
    };
    final data =
        await _get('$base/api/v1/playlists/$playlistId', headers: headers)
            as Map<String, dynamic>;

    // Invidious returns playlistId not id; map to local Playlist format
    final id = data['playlistId']?.toString() ?? playlistId;
    final title = data['title']?.toString() ?? 'Playlist';
    final videos = (data['videos'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((v) {
          final videoId = v['videoId']?.toString() ?? '';
          if (videoId.isEmpty) return null;
          String? artwork;
          final thumbs = v['videoThumbnails'];
          if (thumbs is List && thumbs.isNotEmpty && thumbs[0] is Map) {
            artwork = thumbs[0]['url'] as String?;
          }
          return Track(
            id: videoId,
            videoId: videoId,
            title: v['title']?.toString() ?? '',
            artist: v['author']?.toString() ?? '',
            artwork: artwork,
            duration: v['lengthSeconds'] is int ? v['lengthSeconds'] as int : null,
          );
        })
        .whereType<Track>()
        .toList();

    return Playlist(id: id, title: title, videos: videos);
  }

  /// Fetches an Invidious playlist and returns it ready to be saved locally.
  Future<Playlist> syncInvidiousPlaylist(
    String playlistId, {
    required String instanceUrl,
    String? sid,
  }) =>
      getInvidiousPlaylistDetail(playlistId,
          instanceUrl: instanceUrl, sid: sid);

  /// Creates a new playlist on the Invidious instance (or pushes to an
  /// existing one when [existingInvidiousId] is provided) and returns the
  /// Invidious playlist ID.
  ///
  /// When [existingInvidiousId] is set the method skips playlist creation and
  /// only appends the tracks from [local] to that existing playlist — ideal
  /// for incremental auto-push when a single track is added locally.
  Future<String> pushPlaylistToInvidious(
    Playlist local, {
    required String instanceUrl,
    String? sid,
    String privacy = 'private',
    String? existingInvidiousId,
  }) async {
    final base = instanceUrl.replaceAll(RegExp(r'/+$'), '');
    final headers = <String, String>{
      if (sid != null && sid.isNotEmpty) 'Cookie': 'SID=$sid',
    };

    String invId = existingInvidiousId ?? '';

    if (invId.isEmpty) {
      final created = await _post(
        '$base/api/v1/auth/playlists',
        {'title': local.title, 'privacy': privacy},
        headers: headers,
      );
      invId = (created as Map<String, dynamic>?)?['playlistId']?.toString() ?? '';
      if (invId.isEmpty) {
        throw Exception('Failed to create playlist on Invidious');
      }
    }

    for (final track in local.videos) {
      final videoId = track.videoId?.isNotEmpty == true ? track.videoId! : track.id;
      if (videoId.isEmpty) continue;
      try {
        await _post(
          '$base/api/v1/auth/playlists/$invId/videos',
          {'videoId': videoId},
          headers: headers,
        );
      } catch (_) {
        // Best-effort — skip videos that fail (e.g. already present)
      }
    }

    return invId;
  }

  // ── ListenBrainz (direct) ─────────────────────────────────────────────────
  static const _lbApi = 'https://api.listenbrainz.org/1';

  Future<Map<String, dynamic>> validateListenBrainzToken(String token) async {
    return await _get(
      '$_lbApi/validate-token',
      headers: {'Authorization': 'Token $token'},
    ) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getLBRecentListens(
    String username,
    String token, {
    int count = 8,
  }) async {
    final data = await _get(
      '$_lbApi/user/${Uri.encodeComponent(username)}/listens?count=$count',
      headers: {'Authorization': 'Token $token'},
    );
    return (data as Map?)?['payload']?['listens'] as List? ?? [];
  }

  Future<List<dynamic>> getLBTopRecordings(
    String username,
    String token,
    String range, {
    int count = 10,
  }) async {
    final data = await _get(
      '$_lbApi/stats/user/${Uri.encodeComponent(username)}/recordings'
      '?count=$count&range=$range',
      headers: {'Authorization': 'Token $token'},
    );
    return (data as Map?)?['payload']?['recordings'] as List? ?? [];
  }

  Future<void> scrobble({
    required String token,
    required String artistName,
    required String trackName,
    String? releaseName,
  }) async {
    await _post(
      '$_lbApi/submit-listens',
      {
        'listen_type': 'single',
        'payload': [
          {
            'listened_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'track_metadata': {
              'artist_name': artistName,
              'track_name': trackName,
              if (releaseName != null) 'release_name': releaseName,
            },
          }
        ],
      },
      headers: {'Authorization': 'Token $token'},
    );
  }

  /// Submits a "playing now" notification to ListenBrainz (no listened_at).
  Future<void> submitPlayingNow({
    required String token,
    required String artistName,
    required String trackName,
    String? releaseName,
  }) async {
    await _post(
      '$_lbApi/submit-listens',
      {
        'listen_type': 'playing_now',
        'payload': [
          {
            'track_metadata': {
              'artist_name': artistName,
              'track_name': trackName,
              if (releaseName != null) 'release_name': releaseName,
            },
          }
        ],
      },
      headers: {'Authorization': 'Token $token'},
    );
  }

  // ── Last.fm ───────────────────────────────────────────────────────────────
  static const _lastFmApi = 'https://ws.audioscrobbler.com/2.0';

  /// Validates a Last.fm API key using a lightweight read-only endpoint.
  /// Returns the response map. Throws if the key is invalid or the request fails.
  Future<Map<String, dynamic>> validateLastFmKey(String apiKey) async {
    // chart.getTopArtists only needs api_key — no api_sig or session required.
    final data = await _get(
      '$_lastFmApi/?method=chart.gettopartists&limit=1&api_key=${Uri.encodeComponent(apiKey)}&format=json',
    ) as Map<String, dynamic>;
    // Last.fm returns HTTP 200 even for invalid keys, using a JSON error body.
    if (data.containsKey('error')) {
      throw Exception(data['message']?.toString() ?? 'Invalid Last.fm API key');
    }
    return data;
  }

  // ── Ollama (local AI — user-configured URL) ───────────────────────────────
  Future<dynamic> testOllama(String ollamaUrl) async {
    final base = ollamaUrl.replaceAll(RegExp(r'/+$'), '');
    return _get('$base/api/tags');
  }

  Future<dynamic> ollamaChat(
    String ollamaUrl,
    String model,
    List<Map<String, String>> messages,
  ) async {
    final base = ollamaUrl.replaceAll(RegExp(r'/+$'), '');
    return _post('$base/api/chat', {
      'model': model,
      'messages': messages,
      'stream': false,
    });
  }

  // ── AI Queue ──────────────────────────────────────────────────────────────
  Future<Track?> generateAIQueue(
    Track current, {
    required String ollamaUrl,
    required String ollamaModel,
  }) async {
    try {
      final prompt =
          'Suggest one song similar to "${current.title}" by "${current.artist}". '
          'Reply with JSON only: {"title": "...", "artist": "..."}';
      final res = await ollamaChat(
        ollamaUrl,
        ollamaModel,
        [
          {'role': 'user', 'content': prompt}
        ],
      );
      final content = res?['message']?['content'] as String? ?? '';
      final jsonStart = content.indexOf('{');
      final jsonEnd = content.lastIndexOf('}');
      if (jsonStart < 0 || jsonEnd < 0) return null;
      final data = jsonDecode(content.substring(jsonStart, jsonEnd + 1))
          as Map<String, dynamic>;
      return Track(
        id: data['title']?.toString() ?? '',
        title: data['title']?.toString() ?? '—',
        artist: data['artist']?.toString() ?? '—',
      );
    } catch (_) {
      return null;
    }
  }
}
