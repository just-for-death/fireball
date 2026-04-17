import 'dart:convert';
import 'dart:typed_data';

import 'package:webdav_client/webdav_client.dart' as webdav;

const _kRemotePath = '/fireball/library.json';

/// WebDAV / Nextcloud backup and restore for Fireball library.
///
/// Stores library.json at {serverUrl}/fireball/library.json.
/// Credentials are passed directly (loaded from FireballSettings by the caller).
class WebDavSync {
  // ── Backup ────────────────────────────────────────────────────────────────
  static Future<void> backup({
    required String serverUrl,
    required String username,
    required String password,
    required String libraryJson,
  }) async {
    final client = _client(serverUrl, username, password);

    // Ensure the parent directory exists
    try {
      await client.mkdir('/fireball');
    } catch (_) {
      // Ignore if directory already exists
    }

    final bytes = Uint8List.fromList(utf8.encode(libraryJson));
    await client.write(_kRemotePath, bytes);
  }

  // ── Restore ───────────────────────────────────────────────────────────────
  static Future<String?> restore({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final client = _client(serverUrl, username, password);
    try {
      final bytes = await client.read(_kRemotePath);
      return utf8.decode(bytes);
    } catch (e) {
      if (e.toString().contains('404') || e.toString().contains('Not Found')) {
        return null;
      }
      rethrow;
    }
  }

  // ── Test connection ────────────────────────────────────────────────────────
  static Future<bool> testConnection({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    try {
      final client = _client(serverUrl, username, password);
      await client.readDir('/');
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Factory ───────────────────────────────────────────────────────────────
  static webdav.Client _client(
      String serverUrl, String username, String password) {
    final base = serverUrl.replaceAll(RegExp(r'/+$'), '');
    return webdav.newClient(
      base,
      user: username,
      password: password,
      debug: false,
    );
  }
}
