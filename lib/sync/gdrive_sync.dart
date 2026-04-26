import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../core/diagnostics/soft_error_reporter.dart';

const _kFileName = 'fireball_library.json';
const _kMimeType = 'application/json';

/// Google Drive backup/restore for Fireball library.
/// Stores library.json in the app's private appDataFolder (not visible to users).
class GDriveSync {
  static final _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveAppdataScope],
  );

  // ── Auth ─────────────────────────────────────────────────────────────────
  static Future<GoogleSignInAccount?> signIn() async {
    try {
      return await _googleSignIn.signIn();
    } catch (e) {
      throw Exception('Google Sign-In failed: $e');
    }
  }

  static Future<void> signOut() async {
    await _googleSignIn.signOut();
  }

  static Future<GoogleSignInAccount?> get currentUser async {
    return _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
  }

  static Future<bool> get isSignedIn => _googleSignIn.isSignedIn();

  // ── Drive client helper ───────────────────────────────────────────────────
  static Future<drive.DriveApi> _getDriveApi() async {
    final account = await currentUser;
    if (account == null) {
      throw Exception('Not signed in to Google');
    }
    final authHeaders = await account.authHeaders;
    final client = _AuthenticatedClient(authHeaders);
    return drive.DriveApi(client);
  }

  // ── Backup ────────────────────────────────────────────────────────────────
  static Future<void> backup(String libraryJson) async {
    final api = await _getDriveApi();
    final bytes = utf8.encode(libraryJson);

    // Find all existing backup files (duplicates can accumulate over time)
    final allIds = await _findAllFiles(api);

    final media = drive.Media(
      Stream.fromIterable([bytes]),
      bytes.length,
      contentType: _kMimeType,
    );

    if (allIds.isNotEmpty) {
      // Update the first file, delete any extras
      await api.files.update(drive.File(), allIds.first, uploadMedia: media);
      for (final id in allIds.skip(1)) {
        try {
          await api.files.delete(id);
        } catch (e, st) {
          SoftErrorReporter.report(
            'gdrive_sync.uploadLibrary.deleteDuplicate',
            e,
            st,
            details: <String, Object?>{'fileId': id},
          );
        }
      }
    } else {
      final file = drive.File()
        ..name = _kFileName
        ..parents = ['appDataFolder'];
      await api.files.create(file, uploadMedia: media);
    }
  }

  // ── Restore ───────────────────────────────────────────────────────────────
  static Future<String?> restore() async {
    final api = await _getDriveApi();
    final fileId = await _findFile(api);
    if (fileId == null) return null;

    final response = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final rawChunks = await response.stream.toList();
    final bytes = rawChunks.expand((c) => c).toList();
    return utf8.decode(bytes);
  }

  // ── Last backup time ──────────────────────────────────────────────────────
  static Future<DateTime?> getLastBackupTime() async {
    try {
      final api = await _getDriveApi();
      final fileId = await _findFile(api);
      if (fileId == null) return null;

      final file = await api.files.get(
        fileId,
        $fields: 'modifiedTime',
      ) as drive.File;
      return file.modifiedTime;
    } catch (e, st) {
      SoftErrorReporter.report(
        'gdrive_sync.getLastBackupTime',
        e,
        st,
      );
      return null;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  static Future<String?> _findFile(drive.DriveApi api) async {
    final ids = await _findAllFiles(api);
    return ids.isEmpty ? null : ids.first;
  }

  static Future<List<String>> _findAllFiles(drive.DriveApi api) async {
    final list = await api.files.list(
      spaces: 'appDataFolder',
      q: "name='$_kFileName' and trashed=false",
      $fields: 'files(id)',
    );
    return list.files?.map((f) => f.id!).whereType<String>().toList() ?? [];
  }
}

// ── HTTP client that injects Google auth headers ─────────────────────────────
class _AuthenticatedClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  _AuthenticatedClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
