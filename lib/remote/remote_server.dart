import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

/// Local-network HTTP server (port 7771) that exposes the Fireball player
/// state and accepts control commands.
///
/// Endpoints:
///   GET  /state   → JSON snapshot of current PlayerState
///   POST /command → JSON body with "action" (play/pause/toggle/next/prev/seek)
///                   and optional "value" (seek position in ms)
///   POST /pair    → JSON `{"host","port"}` so this device stores the peer for
///                   bidirectional control (no cloud; LAN only).
class RemoteServer {
  static HttpServer? _server;
  static String? _cachedIp;

  /// Called when a remote device POSTs its address to `/pair`.
  static Future<void> Function(String host, int port)? onPeerRegistered;

  /// The local IPv4 address shown to the user (for QR code / manual entry).
  static String? get localIp => _cachedIp;

  /// Port the server listens on.
  static const int port = 7771;

  /// Starts the embedded HTTP server and wires [player] as the command target.
  /// A second call while already running is a no-op.
  static Future<void> start(
    RemotePlayerProxy player, {
    Future<void> Function(String host, int port)? peerCallback,
  }) async {
    onPeerRegistered = peerCallback;
    if (_server != null) return;
    try {
      // Bind first; only set _cachedIp on success so the QR code / host URL
      // is never shown when the server failed to start.
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _cachedIp = await _resolveLocalIp();
      dev.log('RemoteServer: listening on ${_cachedIp ?? '0.0.0.0'}:$port');
      _server!.listen(
        (req) => _handle(req, player),
        onError: (e) => dev.log('RemoteServer error: $e'),
      );
    } catch (e) {
      _cachedIp = null;
      _server = null;
      dev.log('RemoteServer.start failed: $e');
    }
  }

  /// Stops and cleans up the HTTP server.
  static Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _cachedIp = null;
    onPeerRegistered = null;
  }

  static Future<void> _handle(HttpRequest req, RemotePlayerProxy player) async {
    req.response.headers
      ..add('Access-Control-Allow-Origin', '*')
      ..add('Content-Type', 'application/json');

    try {
      if (req.method == 'OPTIONS') {
        req.response.statusCode = 204;
        await req.response.close();
        return;
      }

      if (req.uri.path == '/state' && req.method == 'GET') {
        final snapshot = player.stateSnapshot();
        req.response.write(jsonEncode(snapshot));
      } else if (req.uri.path == '/pair' && req.method == 'POST') {
        final body = await utf8.decoder.bind(req).join();
        final Map<String, dynamic> j =
            body.isNotEmpty ? jsonDecode(body) as Map<String, dynamic> : {};
        final host = j['host']?.toString().trim();
        final port = (j['port'] as num?)?.toInt() ?? RemoteServer.port;
        if (host == null || host.isEmpty) {
          req.response.statusCode = 400;
          req.response.write(jsonEncode({'error': 'host required'}));
        } else if (port < 1 || port > 65535) {
          req.response.statusCode = 400;
          req.response.write(jsonEncode({'error': 'invalid port'}));
        } else {
          await onPeerRegistered?.call(host, port);
          req.response.write('{"ok":true}');
        }
      } else if (req.uri.path == '/command' && req.method == 'POST') {
        final body = await utf8.decoder.bind(req).join();
        final Map<String, dynamic> cmd =
            body.isNotEmpty ? jsonDecode(body) as Map<String, dynamic> : {};
        try {
          await _dispatch(cmd, player);
          req.response.write('{"ok":true}');
        } on ArgumentError catch (e) {
          // Unknown / missing action → 400 Bad Request, not 500
          req.response.statusCode = 400;
          req.response.write(jsonEncode({'error': e.message.toString()}));
        }
      } else {
        req.response.statusCode = 404;
        req.response.write('{"error":"not found"}');
      }
    } catch (e) {
      req.response.statusCode = 500;
      req.response.write(jsonEncode({'error': e.toString()}));
    }

    await req.response.close();
  }

  static Future<void> _dispatch(
    Map<String, dynamic> cmd,
    RemotePlayerProxy player,
  ) async {
    switch (cmd['action']?.toString()) {
      case 'play':
        await player.play();
      case 'pause':
        await player.pause();
      case 'toggle':
        await player.togglePlayPause();
      case 'next':
        await player.next();
      case 'prev':
        await player.previous();
      case 'seek':
        final ms = (cmd['value'] as num?)?.toInt() ?? 0;
        await player.seekTo(Duration(milliseconds: ms.clamp(0, 86400000)));
      default:
        throw ArgumentError('Unknown action: ${cmd['action']}');
    }
  }

  static bool _isPrivateIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]) ?? -1;
    final b = int.tryParse(parts[1]) ?? -1;
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    return false;
  }

  /// Prefer a private LAN address (e.g. 192.168.x.x) so phones pick Wi‑Fi over
  /// mobile data interfaces when both exist.
  static Future<String?> _resolveLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      final private = <String>[];
      final other = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final ip = addr.address;
          if (_isPrivateIpv4(ip)) {
            private.add(ip);
          } else {
            other.add(ip);
          }
        }
      }
      private.sort();
      if (private.isNotEmpty) return private.first;
      other.sort();
      if (other.isNotEmpty) return other.first;
    } catch (_) {}
    return null;
  }
}

/// Minimal interface that [RemoteServer] calls back on.
/// Implemented by [PlayerNotifier] in providers.dart.
abstract class RemotePlayerProxy {
  Map<String, dynamic> stateSnapshot();
  Future<void> play();
  Future<void> pause();
  Future<void> togglePlayPause();
  Future<void> next();
  Future<void> previous();
  Future<void> seekTo(Duration position);
}
