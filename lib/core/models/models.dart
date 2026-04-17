import 'track.dart';

class Playlist {
  final String id;
  final String title;
  final List<Track> videos;

  const Playlist({required this.id, required this.title, this.videos = const []});

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '—',
        videos: (j['videos'] as List<dynamic>? ?? [])
            .map((v) => Track.fromJson(v as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'videos': videos.map((t) => t.toJson()).toList(),
      };
}

class Artist {
  final String artistId;
  final String name;
  final String? artwork;

  const Artist({required this.artistId, required this.name, this.artwork});

  factory Artist.fromJson(Map<String, dynamic> j) => Artist(
        artistId: j['artistId']?.toString() ?? '',
        name: j['name'] ?? '—',
        artwork: j['artwork'],
      );

  Map<String, dynamic> toJson() => {
        'artistId': artistId,
        'name': name,
        if (artwork != null) 'artwork': artwork,
      };
}

class Album {
  final String id;
  final String title;
  final String artist;
  final String? artwork;
  final int? year;
  final List<Track>? tracks;

  const Album({
    required this.id,
    required this.title,
    required this.artist,
    this.artwork,
    this.year,
    this.tracks,
  });

  factory Album.fromJson(Map<String, dynamic> j) => Album(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '—',
        artist: j['artist']?.toString() ?? '—',
        artwork: j['artwork']?.toString(),
        year: j['year'] is int ? j['year'] : int.tryParse(j['year']?.toString() ?? ''),
        tracks: (j['tracks'] as List<dynamic>?)
            ?.map((t) => Track.fromJson(t as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        if (artwork != null) 'artwork': artwork,
        if (year != null) 'year': year,
        if (tracks != null) 'tracks': tracks!.map((t) => t.toJson()).toList(),
      };
}

class FireballSettings {
  final bool ollamaEnabled;
  final String ollamaUrl;
  final String ollamaModel;
  final String lastFmApiKey;
  final String listenBrainzToken;
  final String listenBrainzUsername;
  final bool highQuality;
  final bool cacheEnabled;
  final String queueMode;
  final String invidiousInstance;
  final String? invidiousSid;
  final String? invidiousUsername;
  final bool videoMode;
  final bool sponsorBlock;
  final List<String> sponsorBlockCategories;
  final bool analytics;
  // ListenBrainz
  final bool listenBrainzEnabled;
  final bool listenBrainzPlayingNow;
  final int listenBrainzScrobblePercent;
  final int listenBrainzScrobbleMaxSeconds;
  // Invidious
  final String invidiousPlaylistPrivacy;
  final bool invidiousAutoPush;
  final Map<String, String> invidiousPlaylistMappings;
  // Backup & Sync
  final String webDavUrl;
  final String webDavUsername;
  final String webDavPassword;
  final bool gDriveEnabled;
  final String? lastBackupAt;
  final bool webDavLiveSync;
  // Remote Control
  final bool remoteServerEnabled;
  final String remoteHostIp;
  // Home
  final List<String> homeCountries;

  const FireballSettings({
    this.ollamaEnabled = false,
    this.ollamaUrl = '',
    this.ollamaModel = 'llama3.2:3b',
    this.lastFmApiKey = '',
    this.listenBrainzToken = '',
    this.listenBrainzUsername = '',
    this.highQuality = false,
    this.cacheEnabled = true,
    this.queueMode = 'off',
    this.invidiousInstance = '',
    this.invidiousSid,
    this.invidiousUsername,
    this.videoMode = false,
    this.sponsorBlock = false,
    this.sponsorBlockCategories = const [],
    this.analytics = false,
    this.listenBrainzEnabled = false,
    this.listenBrainzPlayingNow = false,
    this.listenBrainzScrobblePercent = 50,
    this.listenBrainzScrobbleMaxSeconds = 240,
    this.invidiousPlaylistPrivacy = 'private',
    this.invidiousAutoPush = false,
    this.invidiousPlaylistMappings = const {},
    this.webDavUrl = '',
    this.webDavUsername = '',
    this.webDavPassword = '',
    this.gDriveEnabled = false,
    this.lastBackupAt,
    this.webDavLiveSync = false,
    this.remoteServerEnabled = false,
    this.remoteHostIp = '',
    this.homeCountries = const [],
  });

  factory FireballSettings.fromJson(Map<String, dynamic> j) {
    bool toBool(dynamic v, bool def) {
      if (v == null) return def;
      if (v is bool) return v;
      if (v is String) return v.toLowerCase() == 'true' || v == '1';
      if (v is int) return v == 1;
      return def;
    }

    List<String> toStringList(dynamic v) {
      if (v == null) return [];
      if (v is List) return v.map((e) => e.toString()).toList();
      return [];
    }

    Map<String, String> toStringMap(dynamic v) {
      if (v == null) return {};
      if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val.toString()));
      return {};
    }

    return FireballSettings(
      ollamaEnabled: toBool(j['ollamaEnabled'], false),
      ollamaUrl: j['ollamaUrl']?.toString() ?? '',
      ollamaModel: j['ollamaModel']?.toString() ?? 'llama3.2:3b',
      lastFmApiKey: j['lastFmApiKey']?.toString() ?? '',
      listenBrainzToken: j['listenBrainzToken']?.toString() ?? '',
      listenBrainzUsername: j['listenBrainzUsername']?.toString() ?? '',
      highQuality: toBool(j['highQuality'], false),
      cacheEnabled: toBool(j['cacheEnabled'], true),
      queueMode: j['queueMode']?.toString() ?? 'off',
      invidiousInstance: j['invidiousInstance']?.toString() ?? '',
      invidiousSid: j['invidiousSid']?.toString(),
      invidiousUsername: j['invidiousUsername']?.toString(),
      videoMode: toBool(j['videoMode'], false),
      sponsorBlock: toBool(j['sponsorBlock'], false),
      sponsorBlockCategories: toStringList(j['sponsorBlockCategories']),
      analytics: toBool(j['analytics'], false),
      listenBrainzEnabled: toBool(j['listenBrainzEnabled'], false),
      listenBrainzPlayingNow: toBool(j['listenBrainzPlayingNow'], false),
      listenBrainzScrobblePercent:
          j['listenBrainzScrobblePercent'] is num
              ? (j['listenBrainzScrobblePercent'] as num).toInt()
              : 50,
      listenBrainzScrobbleMaxSeconds:
          j['listenBrainzScrobbleMaxSeconds'] is num
              ? (j['listenBrainzScrobbleMaxSeconds'] as num).toInt()
              : 240,
      invidiousPlaylistPrivacy: j['invidiousPlaylistPrivacy']?.toString() ?? 'private',
      invidiousAutoPush: toBool(j['invidiousAutoPush'], false),
      invidiousPlaylistMappings: toStringMap(j['invidiousPlaylistMappings']),
      webDavUrl: j['webDavUrl']?.toString() ?? '',
      webDavUsername: j['webDavUsername']?.toString() ?? '',
      webDavPassword: j['webDavPassword']?.toString() ?? '',
      gDriveEnabled: toBool(j['gDriveEnabled'], false),
      lastBackupAt: j['lastBackupAt']?.toString(),
      webDavLiveSync: toBool(j['webDavLiveSync'], false),
      remoteServerEnabled: toBool(j['remoteServerEnabled'], false),
      remoteHostIp: j['remoteHostIp']?.toString() ?? '',
      homeCountries: toStringList(j['homeCountries']),
    );
  }

  Map<String, dynamic> toJson() => {
        'ollamaEnabled': ollamaEnabled,
        'ollamaUrl': ollamaUrl,
        'ollamaModel': ollamaModel,
        'lastFmApiKey': lastFmApiKey,
        'listenBrainzToken': listenBrainzToken,
        'listenBrainzUsername': listenBrainzUsername,
        'highQuality': highQuality,
        'cacheEnabled': cacheEnabled,
        'queueMode': queueMode,
        'invidiousInstance': invidiousInstance,
        if (invidiousSid != null) 'invidiousSid': invidiousSid,
        if (invidiousUsername != null) 'invidiousUsername': invidiousUsername,
        'videoMode': videoMode,
        'sponsorBlock': sponsorBlock,
        'sponsorBlockCategories': sponsorBlockCategories,
        'analytics': analytics,
        'listenBrainzEnabled': listenBrainzEnabled,
        'listenBrainzPlayingNow': listenBrainzPlayingNow,
        'listenBrainzScrobblePercent': listenBrainzScrobblePercent,
        'listenBrainzScrobbleMaxSeconds': listenBrainzScrobbleMaxSeconds,
        'invidiousPlaylistPrivacy': invidiousPlaylistPrivacy,
        'invidiousAutoPush': invidiousAutoPush,
        'invidiousPlaylistMappings': invidiousPlaylistMappings,
        'webDavUrl': webDavUrl,
        'webDavUsername': webDavUsername,
        'webDavPassword': webDavPassword,
        'gDriveEnabled': gDriveEnabled,
        if (lastBackupAt != null) 'lastBackupAt': lastBackupAt,
        'webDavLiveSync': webDavLiveSync,
        'remoteServerEnabled': remoteServerEnabled,
        'remoteHostIp': remoteHostIp,
        'homeCountries': homeCountries,
      };

  FireballSettings copyWith({
    bool? ollamaEnabled,
    String? ollamaUrl,
    String? ollamaModel,
    String? lastFmApiKey,
    String? listenBrainzToken,
    String? listenBrainzUsername,
    bool? highQuality,
    bool? cacheEnabled,
    String? queueMode,
    String? invidiousInstance,
    String? invidiousSid,
    bool clearInvidiousSid = false,
    String? invidiousUsername,
    bool clearInvidiousUsername = false,
    bool? videoMode,
    bool? sponsorBlock,
    List<String>? sponsorBlockCategories,
    bool? analytics,
    bool? listenBrainzEnabled,
    bool? listenBrainzPlayingNow,
    int? listenBrainzScrobblePercent,
    int? listenBrainzScrobbleMaxSeconds,
    String? invidiousPlaylistPrivacy,
    bool? invidiousAutoPush,
    Map<String, String>? invidiousPlaylistMappings,
    String? webDavUrl,
    String? webDavUsername,
    String? webDavPassword,
    bool? gDriveEnabled,
    String? lastBackupAt,
    bool? webDavLiveSync,
    bool? remoteServerEnabled,
    String? remoteHostIp,
    List<String>? homeCountries,
  }) =>
      FireballSettings(
        ollamaEnabled: ollamaEnabled ?? this.ollamaEnabled,
        ollamaUrl: ollamaUrl ?? this.ollamaUrl,
        ollamaModel: ollamaModel ?? this.ollamaModel,
        lastFmApiKey: lastFmApiKey ?? this.lastFmApiKey,
        listenBrainzToken: listenBrainzToken ?? this.listenBrainzToken,
        listenBrainzUsername: listenBrainzUsername ?? this.listenBrainzUsername,
        highQuality: highQuality ?? this.highQuality,
        cacheEnabled: cacheEnabled ?? this.cacheEnabled,
        queueMode: queueMode ?? this.queueMode,
        invidiousInstance: invidiousInstance ?? this.invidiousInstance,
        invidiousSid: clearInvidiousSid ? null : (invidiousSid ?? this.invidiousSid),
        invidiousUsername:
            clearInvidiousUsername ? null : (invidiousUsername ?? this.invidiousUsername),
        videoMode: videoMode ?? this.videoMode,
        sponsorBlock: sponsorBlock ?? this.sponsorBlock,
        sponsorBlockCategories: sponsorBlockCategories ?? this.sponsorBlockCategories,
        analytics: analytics ?? this.analytics,
        listenBrainzEnabled: listenBrainzEnabled ?? this.listenBrainzEnabled,
        listenBrainzPlayingNow: listenBrainzPlayingNow ?? this.listenBrainzPlayingNow,
        listenBrainzScrobblePercent:
            listenBrainzScrobblePercent ?? this.listenBrainzScrobblePercent,
        listenBrainzScrobbleMaxSeconds:
            listenBrainzScrobbleMaxSeconds ?? this.listenBrainzScrobbleMaxSeconds,
        invidiousPlaylistPrivacy: invidiousPlaylistPrivacy ?? this.invidiousPlaylistPrivacy,
        invidiousAutoPush: invidiousAutoPush ?? this.invidiousAutoPush,
        invidiousPlaylistMappings: invidiousPlaylistMappings ?? this.invidiousPlaylistMappings,
        webDavUrl: webDavUrl ?? this.webDavUrl,
        webDavUsername: webDavUsername ?? this.webDavUsername,
        webDavPassword: webDavPassword ?? this.webDavPassword,
        gDriveEnabled: gDriveEnabled ?? this.gDriveEnabled,
        lastBackupAt: lastBackupAt ?? this.lastBackupAt,
        webDavLiveSync: webDavLiveSync ?? this.webDavLiveSync,
        remoteServerEnabled: remoteServerEnabled ?? this.remoteServerEnabled,
        remoteHostIp: remoteHostIp ?? this.remoteHostIp,
        homeCountries: homeCountries ?? this.homeCountries,
      );
}
