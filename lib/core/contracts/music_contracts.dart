import '../models/track.dart';

enum MusicItemKind { song, playlist, artist, album }

MusicItemKind musicItemKindFromString(String raw) {
  switch (raw.toLowerCase()) {
    case 'playlist':
      return MusicItemKind.playlist;
    case 'artist':
      return MusicItemKind.artist;
    case 'album':
      return MusicItemKind.album;
    case 'song':
    default:
      return MusicItemKind.song;
  }
}

class MusicDiscoveryItem {
  const MusicDiscoveryItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.kind,
    this.artwork,
    this.url,
    this.videoId,
    this.album,
    this.year,
    this.duration,
    this.collectionId,
    this.trackCount,
  });

  final String id;
  final String title;
  final String artist;
  final MusicItemKind kind;
  final String? artwork;
  final String? url;
  final String? videoId;
  final String? album;
  final String? year;
  final int? duration;
  final int? collectionId;
  final int? trackCount;

  factory MusicDiscoveryItem.fromMap(Map<String, dynamic> data) {
    final collectionIdRaw = data['collectionId'];
    final trackCountRaw = data['trackCount'];
    final durationRaw = data['duration'];
    return MusicDiscoveryItem(
      id: data['id']?.toString() ?? '',
      title: data['title']?.toString() ?? '—',
      artist: data['artist']?.toString() ?? '—',
      kind: musicItemKindFromString(data['kind']?.toString() ?? 'song'),
      artwork: data['artwork']?.toString(),
      url: data['url']?.toString(),
      videoId: data['videoId']?.toString(),
      album: data['album']?.toString(),
      year: data['year']?.toString(),
      duration: durationRaw is int ? durationRaw : int.tryParse('$durationRaw'),
      collectionId: collectionIdRaw is int
          ? collectionIdRaw
          : int.tryParse('$collectionIdRaw'),
      trackCount:
          trackCountRaw is int ? trackCountRaw : int.tryParse('$trackCountRaw'),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'artist': artist,
        'kind': kind.name,
        'artwork': artwork,
        'url': url,
        'videoId': videoId,
        'album': album,
        'year': year,
        'duration': duration,
        'collectionId': collectionId,
        'trackCount': trackCount,
      };

  Track toTrack() => Track(
        id: id,
        videoId: videoId,
        title: title,
        artist: artist,
        artwork: artwork,
        url: url ?? '',
        duration: duration,
        album: album,
        year: year,
      );
}

class ArtistProfile {
  const ArtistProfile({
    required this.id,
    required this.name,
    this.primaryGenreName,
  });

  final int id;
  final String name;
  final String? primaryGenreName;

  factory ArtistProfile.fromMap(Map<String, dynamic> data) {
    final artistIdRaw = data['artistId'];
    final artistId = artistIdRaw is int ? artistIdRaw : int.tryParse('$artistIdRaw');
    return ArtistProfile(
      id: artistId ?? 0,
      name: data['artistName']?.toString() ?? '—',
      primaryGenreName: data['primaryGenreName']?.toString(),
    );
  }
}

class ListenBrainzRecentListen {
  const ListenBrainzRecentListen({
    required this.title,
    required this.artist,
    this.album,
    this.caaReleaseMbid,
    this.listenedAtEpochSec,
  });

  final String title;
  final String artist;
  final String? album;
  final String? caaReleaseMbid;
  final int? listenedAtEpochSec;

  factory ListenBrainzRecentListen.fromApi(dynamic raw) {
    final listen = raw is Map ? raw : const <String, dynamic>{};
    final metaRaw = listen['track_metadata'];
    final meta = metaRaw is Map ? metaRaw : const <String, dynamic>{};
    final mbidMappingRaw = meta['mbid_mapping'];
    final mbidMapping =
        mbidMappingRaw is Map ? mbidMappingRaw : const <String, dynamic>{};
    final listenedAtRaw = listen['listened_at'];
    return ListenBrainzRecentListen(
      title: meta['track_name']?.toString() ?? '—',
      artist: meta['artist_name']?.toString() ?? '—',
      album: meta['release_name']?.toString(),
      caaReleaseMbid: mbidMapping['caa_release_mbid']?.toString(),
      listenedAtEpochSec:
          listenedAtRaw is int ? listenedAtRaw : int.tryParse('$listenedAtRaw'),
    );
  }

  Track toTrack() => Track(
        id: '$artist::$title',
        title: title,
        artist: artist,
        album: album,
      );
}

class ListenBrainzTopTrack {
  const ListenBrainzTopTrack({
    required this.title,
    required this.artist,
    required this.listenCount,
    this.album,
    this.caaReleaseMbid,
  });

  final String title;
  final String artist;
  final String? album;
  final String? caaReleaseMbid;
  final int listenCount;

  factory ListenBrainzTopTrack.fromApi(dynamic raw) {
    final rec = raw is Map ? raw : const <String, dynamic>{};
    final listensRaw = rec['listen_count'];
    return ListenBrainzTopTrack(
      title: rec['track_name']?.toString() ?? '—',
      artist: rec['artist_name']?.toString() ?? '—',
      album: rec['release_name']?.toString(),
      caaReleaseMbid: rec['caa_release_mbid']?.toString(),
      listenCount: listensRaw is int ? listensRaw : int.tryParse('$listensRaw') ?? 0,
    );
  }

  Track toTrack() => Track(
        id: '$artist::$title',
        title: title,
        artist: artist,
        album: album,
      );
}
