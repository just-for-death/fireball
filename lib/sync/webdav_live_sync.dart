import 'dart:developer' as dev;

import 'package:webdav_client/webdav_client.dart' as webdav;

import '../core/models/models.dart';
import '../core/store/local_store.dart';
import 'webdav_sync.dart';

/// Automatic bidirectional WebDAV sync using a last-write-wins strategy.
///
/// On app resume: if the remote `library.json` was modified after our last
/// known backup timestamp, pull it; otherwise push our current state.
class WebDavLiveSync {
  /// Returns `true` when the remote file was modified more recently than
  /// the local [settings.lastBackupAt] timestamp.
  static Future<bool> isRemoteNewer(FireballSettings s) async {
    if (s.webDavUrl.isEmpty || s.webDavUsername.isEmpty) return false;
    try {
      final client = webdav.newClient(
        s.webDavUrl.replaceAll(RegExp(r'/+$'), ''),
        user: s.webDavUsername,
        password: s.webDavPassword,
        debug: false,
      );
      final files = await client.readDir('/fireball');
      webdav.File? remote;
      for (final f in files) {
        // Match by name or by full path suffix in case the server returns
        // the full path instead of just the filename.
        final name = f.name ?? '';
        final path = f.path ?? '';
        if (name == 'library.json' || path.endsWith('library.json')) {
          remote = f;
          break;
        }
      }
      if (remote == null) return false;

      final remoteModified = remote.mTime;
      if (remoteModified == null) return false;

      final lastBackup = s.lastBackupAt;
      if (lastBackup == null) return true;

      final localTime = DateTime.tryParse(lastBackup);
      if (localTime == null) return true;

      return remoteModified.isAfter(localTime);
    } catch (e) {
      dev.log('WebDavLiveSync.isRemoteNewer: $e');
      return false;
    }
  }

  /// Pulls from WebDAV when the remote is newer; pushes otherwise.
  static Future<void> syncIfNeeded(
    FireballSettings s,
    LocalStoreNotifier store,
  ) async {
    if (s.webDavUrl.isEmpty || s.webDavUsername.isEmpty) return;
    try {
      if (await isRemoteNewer(s)) {
        final json = await WebDavSync.restore(
          serverUrl: s.webDavUrl,
          username: s.webDavUsername,
          password: s.webDavPassword,
        );
        if (json != null) {
          await store.restore(json);
          dev.log('WebDavLiveSync: pulled from remote');
        }
      } else {
        await WebDavSync.backup(
          serverUrl: s.webDavUrl,
          username: s.webDavUsername,
          password: s.webDavPassword,
          libraryJson: store.exportJson(),
        );
        await store.updateSettings({
          'lastBackupAt': DateTime.now().toIso8601String(),
        });
        dev.log('WebDavLiveSync: pushed to remote');
      }
    } catch (e) {
      dev.log('WebDavLiveSync.syncIfNeeded error: $e');
    }
  }
}
