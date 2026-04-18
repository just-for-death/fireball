import '../url_utils.dart';

class Track {
  final String id;
  final String? videoId;
  final String title;
  final String artist;
  final String? artwork;
  final String? url;
  final int? duration;
  final String? album;

  const Track({
    required this.id,
    this.videoId,
    required this.title,
    required this.artist,
    this.artwork,
    this.url,
    this.duration,
    this.album,
  });

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: (j['id'] ?? j['videoId'] ?? '').toString(),
        videoId: j['videoId']?.toString(),
        title: j['title']?.toString() ?? '—',
        artist: j['artist']?.toString() ?? '—',
        artwork: normalizeHttpUrl(j['artwork']?.toString()),
        url: j['url']?.toString(),
        duration: j['duration'] is int
            ? j['duration']
            : int.tryParse(j['duration']?.toString() ?? ''),
        album: j['album']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (videoId != null) 'videoId': videoId,
        'title': title,
        'artist': artist,
        if (artwork != null) 'artwork': artwork,
        if (url != null) 'url': url,
        if (duration != null) 'duration': duration,
        if (album != null) 'album': album,
      };

  Track copyWith({
    String? id,
    String? videoId,
    String? title,
    String? artist,
    String? artwork,
    String? url,
    int? duration,
    String? album,
  }) =>
      Track(
        id: id ?? this.id,
        videoId: videoId ?? this.videoId,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        artwork: artwork ?? this.artwork,
        url: url ?? this.url,
        duration: duration ?? this.duration,
        album: album ?? this.album,
      );

  String get effectiveId => videoId ?? id;
}
