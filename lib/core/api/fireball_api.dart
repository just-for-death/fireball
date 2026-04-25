import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import '../models/track.dart';
import '../url_utils.dart';

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
    final upper = method.toUpperCase();
    // Do not send Content-Type on GET/HEAD/DELETE — some CDNs and mobile stacks
    // mishandle it; iTunes RSS/top charts must use a plain GET.
    final requestHeaders = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'Fireball/1.0 (https://github.com/fireball)',
      ...?headers,
    };
    if (upper == 'POST' || upper == 'PUT') {
      requestHeaders['Content-Type'] = 'application/json';
    }

    try {
      final http.Response res;
      const timeout = Duration(seconds: 15);

      switch (upper) {
        case 'POST':
          res = await http
              .post(uri,
                  headers: requestHeaders,
                  body: body != null ? json.encode(body) : null)
              .timeout(timeout);
          break;
        case 'PUT':
          res = await http
              .put(uri,
                  headers: requestHeaders,
                  body: body != null ? json.encode(body) : null)
              .timeout(timeout);
          break;
        case 'DELETE':
          res =
              await http.delete(uri, headers: requestHeaders).timeout(timeout);
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

  /// Search for an artist by name and return the first matching iTunes artist.
  Future<Map<String, dynamic>?> itunesFindArtist(String artistName) async {
    try {
      final data = await _get(
        '$_itunesBase/search?term=${Uri.encodeComponent(artistName)}&entity=musicArtist&limit=5',
      );
      final results = (data['results'] as List<dynamic>? ?? []);
      if (results.isEmpty) return null;
      // Prefer exact name match
      final lower = artistName.toLowerCase();
      for (final r in results) {
        final name = (r['artistName'] as String? ?? '').toLowerCase();
        if (name == lower) return r as Map<String, dynamic>;
      }
      return results.first as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Fetch the top songs for an iTunes artist by their numeric [artistId].
  Future<List<Map<String, dynamic>>> itunesArtistTopSongs(
    int artistId, {
    int limit = 20,
  }) async {
    try {
      final data = await _get(
        '$_itunesBase/lookup?id=$artistId&entity=song&limit=$limit&sort=popular',
      );
      final results = (data['results'] as List<dynamic>? ?? []);
      return results
          .where((r) => r['wrapperType'] == 'track')
          .cast<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch the studio albums for an iTunes artist by their numeric [artistId].
  Future<List<Map<String, dynamic>>> itunesArtistAlbums(
    int artistId, {
    int limit = 20,
  }) async {
    try {
      final data = await _get(
        '$_itunesBase/lookup?id=$artistId&entity=album&limit=$limit&sort=recent',
      );
      final results = (data['results'] as List<dynamic>? ?? []);
      return results
          .where((r) => r['wrapperType'] == 'collection')
          .cast<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<dynamic> itunesTopSongs(String cc, {int limit = 30}) async {
    return _get(
      '$_itunesBase/$cc/rss/topsongs/limit=$limit/json',
    );
  }

  /// Apple RSS JSON uses `feed.entry` as a [List] for multiple items but a
  /// single [Map] when there is exactly one entry (e.g. limit=1). Normalize
  /// so callers always iterate a list.
  static List<dynamic> appleRssFeedEntries(dynamic data) {
    if (data is! Map) return [];
    final feed = data['feed'];
    if (feed is! Map) return [];
    final entry = feed['entry'];
    if (entry == null) return [];
    if (entry is List) return entry;
    if (entry is Map) return [entry];
    return [];
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
    final qs = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return _get('$_lrclibBase/get?$qs', headers: _lrclibHeaders);
  }

  Future<dynamic> lrclibSearch(String query) async {
    return _get('$_lrclibBase/search?q=${Uri.encodeComponent(query)}',
        headers: _lrclibHeaders);
  }

  /// Structured field search — more precise than a combined [query] string.
  Future<dynamic> lrclibSearchByFields(
      String trackName, String artistName) async {
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
              artwork: normalizeHttpUrl(() {
                final vt = v['videoThumbnails'];
                if (vt is List && vt.isNotEmpty && vt[0] is Map) {
                  return vt[0]['url'] as String?;
                }
                final th = v['thumbnails'];
                if (th is List && th.isNotEmpty && th[0] is Map) {
                  return th[0]['url'] as String?;
                }
                return null;
              }()),
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

  /// Extracts Invidious session id from Set-Cookie. SID values are Base64url and
  /// often end with `=` — regex must allow `=` inside the value (do not use
  /// `[^;,\s]+`, which truncates at the first `=`).
  static String _sidFromSetCookieLines(Iterable<String> lines) {
    for (final line in lines) {
      final m = RegExp(r'SID=([^;]+)', caseSensitive: false).firstMatch(line);
      if (m != null) {
        final v = m.group(1)!.trim();
        if (v.isNotEmpty) return v;
      }
    }
    return '';
  }

  /// Logs into an Invidious instance by form-posting to `/login` (web UI), then
  /// reading the `SID` cookie from the redirect response. Matches upstream
  /// [invidious login.cr](https://github.com/iv-org/invidious): body uses
  /// `email` + `password`; query defaults to `type=invidious`.
  Future<Map<String, dynamic>> invidiousLogin(
    String instanceUrl,
    String username,
    String password,
  ) async {
    final base = instanceUrl.replaceAll(RegExp(r'/+$'), '');
    final loginUri = Uri.parse('$base/login?type=invidious');
    final originHeader = Uri.parse(base).origin;

    // Use dart:io HttpClient so we can disable redirect-following and read the
    // Set-Cookie on the 302 from `env.redirect referer` after successful login.
    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..autoUncompress = true;

    Future<({String sid, int status})> tryLogin(String body) async {
      final req = await httpClient.postUrl(loginUri);
      req.followRedirects = false;
      req.headers.set(
          HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
      req.headers.set(HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (compatible; Fireball/1.0; +https://github.com/fireball)');
      req.headers.set(HttpHeaders.refererHeader, '$base/login');
      req.headers.set('origin', originHeader);
      req.headers.set(HttpHeaders.acceptHeader, '*/*');
      req.write(body);

      final resp = await req.close().timeout(const Duration(seconds: 15));
      await resp.drain<void>();

      var sid = '';
      for (final cookie in resp.cookies) {
        if (cookie.name.toUpperCase() == 'SID' && cookie.value.isNotEmpty) {
          sid = cookie.value;
          break;
        }
      }

      if (sid.isEmpty) {
        final raw = resp.headers[HttpHeaders.setCookieHeader] ?? const [];
        sid = _sidFromSetCookieLines(raw);
        if (sid.isEmpty && raw.isNotEmpty) {
          sid = _sidFromSetCookieLines([raw.join(', ')]);
        }
      }

      return (sid: sid, status: resp.statusCode);
    }

    try {
      // Upstream Invidious reads `email` and `password` (see login.cr).
      var body =
          'email=${Uri.encodeComponent(username)}&password=${Uri.encodeComponent(password)}';
      var result = await tryLogin(body);

      // Older form UIs send `action=signin` — retry if the minimal body failed.
      if (result.sid.isEmpty) {
        body = '$body&action=${Uri.encodeComponent('signin')}';
        result = await tryLogin(body);
      }

      if (result.sid.isEmpty) {
        final code = result.status;
        if (code == 401 || code == 403) {
          throw Exception('Wrong credentials.');
        }
        throw Exception(
            'Login failed — wrong credentials, captcha required, or login disabled on this instance.');
      }

      return {'sid': result.sid, 'username': username, 'instanceUrl': base};
    } on Exception {
      rethrow;
    } catch (e) {
      throw Exception('Could not reach Invidious: $e');
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
            artwork: normalizeHttpUrl(artwork),
            duration:
                v['lengthSeconds'] is int ? v['lengthSeconds'] as int : null,
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
      invId =
          (created as Map<String, dynamic>?)?['playlistId']?.toString() ?? '';
      if (invId.isEmpty) {
        throw Exception('Failed to create playlist on Invidious');
      }
    }

    for (final track in local.videos) {
      final videoId =
          track.videoId?.isNotEmpty == true ? track.videoId! : track.id;
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

  // ── SponsorBlock ──────────────────────────────────────────────────────────
  static const _sponsorBlockBase = 'https://sponsor.ajay.app';

  /// Fetches crowd-sourced skip segments for [videoId] from SponsorBlock.
  ///
  /// [categories] defaults to all standard categories when empty.
  /// Returns an empty list when the video has no segments (404).
  /// Anonymous / read-only — no userID is sent.
  Future<List<dynamic>> sponsorBlockSegments(
    String videoId, {
    List<String> categories = const [],
  }) async {
    if (videoId.isEmpty) return [];
    final cats = categories.isEmpty
        ? [
            'sponsor',
            'selfpromo',
            'interaction',
            'intro',
            'outro',
            'preview',
            'music_offtopic',
            'filler',
          ]
        : categories;

    // Build ?categories[]=sponsor&categories[]=intro&… query string
    final catQs =
        cats.map((c) => 'categories[]=${Uri.encodeComponent(c)}').join('&');
    final url =
        '$_sponsorBlockBase/api/skipSegments?videoID=${Uri.encodeComponent(videoId)}&$catQs';

    try {
      final data = await _get(url);
      if (data is List) return data;
      return [];
    } catch (e) {
      // 404 means no segments exist for this video — not an error.
      final msg = e.toString();
      if (msg.contains('404') || msg.contains('Not Found')) return [];
      rethrow;
    }
  }

  /// Reports a segment view to SponsorBlock (best-effort, fire-and-forget).
  /// Called after auto-skipping a segment so the community stats stay accurate.
  Future<void> sponsorBlockMarkViewed(String segmentUuid) async {
    if (segmentUuid.isEmpty) return;
    try {
      await _request(
        'POST',
        '$_sponsorBlockBase/api/viewedVideoSponsorTime?UUID=${Uri.encodeComponent(segmentUuid)}',
      );
    } catch (_) {
      // Best-effort — ignore all errors.
    }
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

  // ── Gotify ────────────────────────────────────────────────────────────────
  Future<void> sendGotifyMessage({
    required String url,
    required String token,
    required String title,
    required String message,
  }) async {
    if (url.isEmpty || token.isEmpty) return;
    final base = url.replaceAll(RegExp(r'/+$'), '');
    try {
      await _post(
        '$base/message',
        {
          'title': title,
          'message': message,
          'priority': 5,
        },
        headers: {
          'X-Gotify-Key': token,
        },
      );
    } catch (_) {
      // Best-effort push notification
    }
  }

  // ── lbdl Server ───────────────────────────────────────────────────────────
  Map<String, String> _lbdlAuthHeader(String user, String pass) {
    if (user.isEmpty && pass.isEmpty) return {};
    final basic = base64Encode(utf8.encode('$user:$pass'));
    return {'Authorization': 'Basic $basic'};
  }

  Future<Map<String, dynamic>> lbdlAuthStatus(
      String url, String user, String pass) async {
    final base = url.replaceAll(RegExp(r'/+$'), '');
    final data = await _get('$base/api/auth/status',
        headers: _lbdlAuthHeader(user, pass));
    return data as Map<String, dynamic>;
  }

  Future<String> lbdlStartJob(String url, String user, String pass,
      String playlistUrl, String invidiousInstance) async {
    final base = url.replaceAll(RegExp(r'/+$'), '');
    final data = await _post(
      '$base/api/jobs',
      {
        'playlist_url': playlistUrl,
        'invidious_instance': invidiousInstance,
      },
      headers: _lbdlAuthHeader(user, pass),
    );
    return (data as Map<String, dynamic>)['job_id']?.toString() ?? '';
  }

  Future<Map<String, dynamic>> lbdlGetJob(
      String url, String user, String pass, String jobId) async {
    final base = url.replaceAll(RegExp(r'/+$'), '');
    final data = await _get('$base/api/jobs/$jobId',
        headers: _lbdlAuthHeader(user, pass));
    return data as Map<String, dynamic>;
  }
}
