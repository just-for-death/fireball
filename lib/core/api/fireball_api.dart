import 'dart:convert';

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
              .post(uri, headers: requestHeaders, body: json.encode(body))
              .timeout(timeout);
          break;
        case 'PUT':
          res = await http
              .put(uri, headers: requestHeaders, body: json.encode(body))
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

  // ── LRCLIB ────────────────────────────────────────────────────────────────
  static const _lrclibBase = 'https://lrclib.net/api';

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
    return _get('$_lrclibBase/get?$qs');
  }

  Future<dynamic> lrclibSearch(String query) async {
    return _get('$_lrclibBase/search?q=${Uri.encodeComponent(query)}');
  }

  /// Structured field search — more precise than a combined [query] string.
  Future<dynamic> lrclibSearchByFields(String trackName, String artistName) async {
    final qs =
        'track_name=${Uri.encodeComponent(trackName)}&artist_name=${Uri.encodeComponent(artistName)}';
    return _get('$_lrclibBase/search?$qs');
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

  Future<Map<String, dynamic>> invidiousLogin(
    String instanceUrl,
    String username,
    String password,
  ) async {
    final base = instanceUrl.replaceAll(RegExp(r'/+$'), '');
    return await _post(
      '$base/api/v1/auth/signin',
      {'username': username, 'password': password},
    ) as Map<String, dynamic>;
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
        await _get('$base/api/v1/playlists/$playlistId', headers: headers);
    return Playlist.fromJson(data as Map<String, dynamic>);
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

  // ── Last.fm ───────────────────────────────────────────────────────────────
  static const _lastFmApi = 'https://ws.audioscrobbler.com/2.0';

  /// Validates a Last.fm API key using a lightweight read-only endpoint.
  /// Returns the response map. Throws if the key is invalid or the request fails.
  Future<Map<String, dynamic>> validateLastFmKey(String apiKey) async {
    // chart.getTopArtists only needs api_key — no api_sig or session required.
    return await _get(
      '$_lastFmApi/?method=chart.gettopartists&limit=1&api_key=${Uri.encodeComponent(apiKey)}&format=json',
    ) as Map<String, dynamic>;
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
