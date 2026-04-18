import 'dart:convert';

import 'package:http/http.dart' as http;

import 'remote_server.dart' show RemoteServer;

/// HTTP client for controlling a remote Fireball instance.
///
/// Point [hostIp] at the IP shown in the host device's Remote Control screen.
/// All calls complete quickly — if the host is unreachable they throw.
class RemoteClient {
  RemoteClient(this.hostIp, {this.port = RemoteServer.port});

  final String hostIp;
  final int port;

  String get _base => 'http://$hostIp:$port';

  /// Fetches the current player state from the remote host.
  Future<RemoteState> getState() async {
    final res = await http
        .get(Uri.parse('$_base/state'))
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) {
      throw Exception('Remote /state returned ${res.statusCode}');
    }
    final Map<String, dynamic> j = jsonDecode(res.body) as Map<String, dynamic>;
    return RemoteState.fromJson(j);
  }

  /// Registers this device's address on the peer so they can control you too.
  Future<void> registerPair(String myHost, int myPort) async {
    final res = await http
        .post(
          Uri.parse('$_base/pair'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'host': myHost, 'port': myPort}),
        )
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) {
      throw Exception('Remote /pair returned ${res.statusCode}');
    }
  }

  /// Sends a playback command to the remote host.
  Future<void> sendCommand(String action, {num? value}) async {
    final res = await http
        .post(
          Uri.parse('$_base/command'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': action,
            if (value != null) 'value': value,
          }),
        )
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) {
      throw Exception('Remote /command returned ${res.statusCode}');
    }
  }
}

/// Snapshot of the remote player state.
class RemoteState {
  final bool isPlaying;
  final int positionMs;
  final int durationMs;
  final String? trackTitle;
  final String? trackArtist;
  final String? trackArtwork;
  final int queueLength;
  final int currentIndex;

  const RemoteState({
    required this.isPlaying,
    required this.positionMs,
    required this.durationMs,
    this.trackTitle,
    this.trackArtist,
    this.trackArtwork,
    required this.queueLength,
    required this.currentIndex,
  });

  factory RemoteState.fromJson(Map<String, dynamic> j) {
    final track = j['track'] as Map<String, dynamic>?;
    return RemoteState(
      isPlaying: j['isPlaying'] as bool? ?? false,
      positionMs: (j['position'] as num?)?.toInt() ?? 0,
      durationMs: (j['duration'] as num?)?.toInt() ?? 0,
      trackTitle: track?['title']?.toString(),
      trackArtist: track?['artist']?.toString(),
      trackArtwork: track?['artwork']?.toString(),
      queueLength: (j['queueLength'] as num?)?.toInt() ?? 0,
      currentIndex: (j['currentIndex'] as num?)?.toInt() ?? -1,
    );
  }

  Duration get position => Duration(milliseconds: positionMs);
  Duration get duration => Duration(milliseconds: durationMs);

  bool get hasTrack => trackTitle != null && trackTitle!.isNotEmpty;
}
