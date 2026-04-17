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
class RemoteServer {
  static HttpServer? _server;
  static String? _cachedIp;

  /// The local IPv4 address shown to the user (for QR code / manual entry).
  static String? get localIp => _cachedIp;

  /// Port the server listens on.
  static const int port = 7771;

  /// Starts the embedded HTTP server and wires [player] as the command target.
  /// A second call while already running is a no-op.
  static Future<void> start(RemotePlayerProxy player) async {
    if (_server != null) return;
    try {
      _cachedIp = await _resolveLocalIp();
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      dev.log('RemoteServer: listening on ${_cachedIp ?? '0.0.0.0'}:$port');
      _server!.listen(
        (req) => _handle(req, player),
        onError: (e) => dev.log('RemoteServer error: $e'),
      );
    } catch (e) {
      dev.log('RemoteServer.start failed: $e');
    }
  }

  /// Stops and cleans up the HTTP server.
  static Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _cachedIp = null;
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
      } else if (req.uri.path == '/command' && req.method == 'POST') {
        final body = await utf8.decoder.bind(req).join();
        final Map<String, dynamic> cmd =
            body.isNotEmpty ? jsonDecode(body) as Map<String, dynamic> : {};
        await _dispatch(cmd, player);
        req.response.write('{"ok":true}');
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
        await player.seekTo(Duration(milliseconds: ms));
    }
  }

  static Future<String?> _resolveLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
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
