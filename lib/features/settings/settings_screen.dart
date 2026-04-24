import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/api/fireball_api.dart';
import '../../core/countries.dart';
import '../../core/models/sponsor_segment.dart';
import '../../core/store/providers.dart';
import '../../core/ui/shell_content_insets.dart';
import '../../core/theme/app_theme.dart';

import 'package:file_picker/file_picker.dart';
import '../../core/widgets/fireball_logo.dart';
import '../../core/widgets/glass_widgets.dart';
import '../../sync/gdrive_sync.dart';
import '../../sync/webdav_sync.dart';
import '../../remote/remote_pairing.dart';
import '../../remote/remote_server.dart';
import '../remote/remote_lan_pairing.dart';
import '../remote/remote_scan_screen.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

class SettingsScreen extends HookConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packageInfo = useFuture(
      useMemoized(() => PackageInfo.fromPlatform(), const []),
    );
    final settings = ref.watch(settingsProvider);
    const api = FireballApi();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final saving = useState(false);
    final searchQuery = useState('');

    bool showSection(String keywords) {
      final q = searchQuery.value.trim().toLowerCase();
      if (q.isEmpty) return true;
      final hay = keywords.toLowerCase();
      for (final part in q.split(RegExp(r'\s+'))) {
        if (part.isNotEmpty && !hay.contains(part)) return false;
      }
      return true;
    }

    // Controller state
    final lbTokenCtrl = useTextEditingController();
    final lbUserCtrl = useTextEditingController();
    final ollamaUrlCtrl = useTextEditingController();
    final ollamaModelCtrl = useTextEditingController();
    final invidiousInstanceCtrl = useTextEditingController();
    final lastFmKeyCtrl = useTextEditingController();
    final invUserCtrl = useTextEditingController();
    final invPassCtrl = useTextEditingController();
    final webDavUrlCtrl = useTextEditingController();
    final webDavUserCtrl = useTextEditingController();
    final webDavPassCtrl = useTextEditingController();
    final gotifyUrlCtrl = useTextEditingController();
    final gotifyTokenCtrl = useTextEditingController();
    final remotePairingCtrl = useTextEditingController();

    // Testing and busy states
    final testingLB = useState(false);
    final testingLastFm = useState(false);
    final testingOllama = useState(false);
    final testingInvidious = useState(false);
    final remotePairingBusy = useState(false);

    // Invidious playlists
    final invPlaylists = useState<List<dynamic>>([]);
    final invPlaylistsLoading = useState(false);

    // Sync states
    final gDriveUser = useState<GoogleSignInAccount?>(null);
    final gDriveLoading = useState(false);
    final gDriveStatus = useState('');
    final webDavTesting = useState(false);
    final webDavStatus = useState('');
    final backupLoading = useState(false);
    final restoreLoading = useState(false);

    // Sync controllers with persisted settings
    useEffect(() {
      lbTokenCtrl.text = settings.listenBrainzToken;
      lbUserCtrl.text = settings.listenBrainzUsername;
      ollamaUrlCtrl.text = settings.ollamaUrl;
      ollamaModelCtrl.text = settings.ollamaModel;
      invidiousInstanceCtrl.text = settings.invidiousInstance;
      lastFmKeyCtrl.text = settings.lastFmApiKey;
      webDavUrlCtrl.text = settings.webDavUrl;
      webDavUserCtrl.text = settings.webDavUsername;
      webDavPassCtrl.text = settings.webDavPassword;
      gotifyUrlCtrl.text = settings.gotifyUrl;
      gotifyTokenCtrl.text = settings.gotifyToken;
      return null;
    }, [settings]);

    // Check Google sign-in status on mount
    useEffect(() {
      GDriveSync.currentUser.then((u) => gDriveUser.value = u);
      return null;
    }, const []);

    Future<void> saveSettings(Map<String, dynamic> patch) async {
      saving.value = true;
      try {
        await ref.read(localStoreProvider.notifier).updateSettings(patch);
      } finally {
        saving.value = false;
      }
    }

    Future<void> runPairing(Future<void> Function() fn) async {
      remotePairingBusy.value = true;
      try {
        await fn();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Paired — both devices can control each other')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), backgroundColor: cs.error),
          );
        }
      } finally {
        remotePairingBusy.value = false;
      }
    }

    Future<void> testAndSaveLB() async {
      final token = lbTokenCtrl.text.trim();
      if (token.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter a ListenBrainz token')));
        return;
      }
      testingLB.value = true;
      try {
        final res = await api.validateListenBrainzToken(token);
        final username =
            res['user_name']?.toString() ?? res['username']?.toString() ?? '';
        lbUserCtrl.text = username;
        await saveSettings({
          'listenBrainzToken': token,
          'listenBrainzUsername': username,
          'listenBrainzEnabled': true,
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('ListenBrainz connected ✓')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('ListenBrainz test failed: $e')));
        }
      } finally {
        testingLB.value = false;
      }
    }

    Future<void> testAndSaveLastFm() async {
      final key = lastFmKeyCtrl.text.trim();
      if (key.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter a Last.fm API Key')));
        return;
      }
      testingLastFm.value = true;
      try {
        await api.validateLastFmKey(key);
        await saveSettings({'lastFmApiKey': key});
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Last.fm connected ✓')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Last.fm test failed: $e')));
        }
      } finally {
        testingLastFm.value = false;
      }
    }

    Future<void> testAndSaveOllama() async {
      final url = ollamaUrlCtrl.text.trim();
      final model = ollamaModelCtrl.text.trim();
      if (url.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Enter an Ollama URL')));
        return;
      }
      testingOllama.value = true;
      try {
        await api.testOllama(url);
        await saveSettings({
          'ollamaUrl': url,
          'ollamaModel': model.isEmpty ? 'llama3.2:3b' : model,
          'ollamaEnabled': true,
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Ollama verified ✓')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Ollama failed: $e')));
        }
      } finally {
        testingOllama.value = false;
      }
    }

    Future<void> testAndSaveInvidious() async {
      final instance = invidiousInstanceCtrl.text.trim();
      if (instance.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter an Invidious instance URL')));
        return;
      }
      testingInvidious.value = true;
      try {
        final sanitized = Uri.parse(instance).origin;
        invidiousInstanceCtrl.text = sanitized;
        // Save the instance first so playback can work regardless of test result
        await saveSettings({'invidiousInstance': sanitized});
        await api.invidiousSearch('test', instanceUrl: sanitized);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Invidious instance saved & verified ✓')));
        }
      } catch (e) {
        // Instance was already saved above; just warn the user the test failed
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Instance saved, but test search failed: $e\nPlayback may still work.'),
            duration: const Duration(seconds: 5),
          ));
        }
      } finally {
        testingInvidious.value = false;
      }
    }

    Future<void> loadInvidiousPlaylists() async {
      if (settings.invidiousUsername == null) return;
      invPlaylistsLoading.value = true;
      try {
        final data = await api.getInvidiousPlaylists(
          instanceUrl: settings.invidiousInstance,
          sid: settings.invidiousSid,
        );
        invPlaylists.value = data;
      } catch (_) {
        invPlaylists.value = [];
      } finally {
        invPlaylistsLoading.value = false;
      }
    }

    Future<void> showInvidiousPlaylistPreview(
        String playlistId, String title) async {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _InvidiousPlaylistPreview(
          playlistId: playlistId,
          title: title,
          instanceUrl: settings.invidiousInstance,
          sid: settings.invidiousSid,
          onSync: () async {
            final pl = await api.syncInvidiousPlaylist(
              playlistId,
              instanceUrl: settings.invidiousInstance,
              sid: settings.invidiousSid,
            );
            await ref.read(localStoreProvider.notifier).addPlaylist(pl);
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Playlist synced to Library ✓')),
              );
            }
          },
        ),
      );
    }

    // Load playlists when user first logs in
    useEffect(() {
      if (settings.invidiousUsername != null && invPlaylists.value.isEmpty) {
        Future.microtask(loadInvidiousPlaylists);
      }
      return null;
    }, [settings.invidiousUsername]);

    Future<void> invidiousLogin() async {
      final instance = invidiousInstanceCtrl.text.trim();
      final user = invUserCtrl.text.trim();
      final pass = invPassCtrl.text.trim();
      if (instance.isEmpty || user.isEmpty || pass.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Fill in instance, username, and password')));
        return;
      }
      try {
        final sanitized = Uri.parse(instance).origin;
        invidiousInstanceCtrl.text = sanitized;

        // Always persist the instance URL first so playback works even if login fails
        await saveSettings({'invidiousInstance': sanitized});

        final res = await api.invidiousLogin(sanitized, user, pass);
        final sid = res['sid']?.toString() ?? '';
        await saveSettings({
          'invidiousUsername': user,
          'invidiousSid': sid,
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invidious login successful ✓')));
        }
      } catch (e) {
        final msg = e.toString().replaceAll('Exception: ', '');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg),
            duration: const Duration(seconds: 5),
          ));
        }
      }
    }

    // ── Google Drive actions ────────────────────────────────────────────────
    Future<void> gDriveSignIn() async {
      gDriveLoading.value = true;
      try {
        final account = await GDriveSync.signIn();
        gDriveUser.value = account;
        if (account != null) {
          await saveSettings({'gDriveEnabled': true});
          gDriveStatus.value = 'Connected as ${account.email}';
        }
      } catch (e) {
        gDriveStatus.value = 'Sign-in failed: $e';
      } finally {
        gDriveLoading.value = false;
      }
    }

    Future<void> gDriveSignOut() async {
      await GDriveSync.signOut();
      gDriveUser.value = null;
      await saveSettings({'gDriveEnabled': false});
      gDriveStatus.value = '';
    }

    Future<void> gDriveBackup() async {
      backupLoading.value = true;
      gDriveStatus.value = 'Backing up...';
      try {
        final json = ref.read(localStoreProvider.notifier).exportJson();
        await GDriveSync.backup(json);
        final now = DateTime.now().toIso8601String();
        await saveSettings({'lastBackupAt': now});
        gDriveStatus.value = 'Backup complete at ${_fmtTime(DateTime.now())}';
      } catch (e) {
        gDriveStatus.value = 'Backup failed: $e';
      } finally {
        backupLoading.value = false;
      }
    }

    Future<void> gDriveRestore() async {
      restoreLoading.value = true;
      gDriveStatus.value = 'Restoring...';
      try {
        final json = await GDriveSync.restore();
        if (json == null) {
          gDriveStatus.value = 'No backup found on Google Drive';
          return;
        }
        await ref.read(localStoreProvider.notifier).restore(json);
        gDriveStatus.value = 'Restored successfully';
      } catch (e) {
        gDriveStatus.value = 'Restore failed: $e';
      } finally {
        restoreLoading.value = false;
      }
    }

    // ── WebDAV actions ──────────────────────────────────────────────────────
    Future<void> saveWebDavSettings() async {
      await saveSettings({
        'webDavUrl': webDavUrlCtrl.text.trim(),
        'webDavUsername': webDavUserCtrl.text.trim(),
        'webDavPassword': webDavPassCtrl.text.trim(),
      });
    }

    Future<void> testWebDav() async {
      final messenger = ScaffoldMessenger.of(context);
      await saveWebDavSettings();
      final url = webDavUrlCtrl.text.trim();
      if (url.isEmpty) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Enter a WebDAV server URL')));
        return;
      }
      webDavTesting.value = true;
      webDavStatus.value = '';
      try {
        final ok = await WebDavSync.testConnection(
          serverUrl: url,
          username: webDavUserCtrl.text.trim(),
          password: webDavPassCtrl.text.trim(),
        );
        webDavStatus.value =
            ok ? 'Connection successful ✓' : 'Connection failed';
      } catch (e) {
        webDavStatus.value = 'Error: $e';
      } finally {
        webDavTesting.value = false;
      }
    }

    Future<void> webDavBackup() async {
      await saveWebDavSettings();
      // Use controller text directly — settings provider may not have flushed yet
      final url = webDavUrlCtrl.text.trim();
      final user = webDavUserCtrl.text.trim();
      final pass = webDavPassCtrl.text.trim();
      backupLoading.value = true;
      webDavStatus.value = 'Backing up...';
      try {
        final json = ref.read(localStoreProvider.notifier).exportJson();
        await WebDavSync.backup(
          serverUrl: url,
          username: user,
          password: pass,
          libraryJson: json,
        );
        final now = DateTime.now().toIso8601String();
        await saveSettings({'lastBackupAt': now});
        webDavStatus.value = 'Backup complete at ${_fmtTime(DateTime.now())}';
      } catch (e) {
        webDavStatus.value = 'Backup failed: $e';
      } finally {
        backupLoading.value = false;
      }
    }

    Future<void> webDavRestore() async {
      await saveWebDavSettings();
      // Use controller text directly — settings provider may not have flushed yet
      final url = webDavUrlCtrl.text.trim();
      final user = webDavUserCtrl.text.trim();
      final pass = webDavPassCtrl.text.trim();
      restoreLoading.value = true;
      webDavStatus.value = 'Restoring...';
      try {
        final json = await WebDavSync.restore(
          serverUrl: url,
          username: user,
          password: pass,
        );
        if (json == null) {
          webDavStatus.value = 'No backup found on WebDAV server';
          return;
        }
        await ref.read(localStoreProvider.notifier).restore(json);
        webDavStatus.value = 'Restored successfully';
      } catch (e) {
        webDavStatus.value = 'Restore failed: $e';
      } finally {
        restoreLoading.value = false;
      }
    }

    return PremiumBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
              child: Row(
                children: [
                  Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1,
                    ),
                  ),
                  const Spacer(),
                  if (saving.value)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cs.primary),
                    ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                style: const TextStyle(color: Colors.white, fontSize: 15),
                cursorColor: cs.primary,
                decoration: InputDecoration(
                  hintText: 'Search settings',
                  hintStyle:
                      TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: Colors.white.withValues(alpha: 0.45)),
                  suffixIcon: searchQuery.value.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.clear_rounded,
                              color: Colors.white.withValues(alpha: 0.45)),
                          onPressed: () => searchQuery.value = '',
                        ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: cs.primary.withValues(alpha: 0.6)),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onChanged: (v) => searchQuery.value = v,
              ),
            ),

            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  shellScrollBottomPadding(context),
                ),
                children: [
                  // ── REMOTE CONTROL ─────────────────────────────────────────
                  if (showSection(
                      'remote control server pairing qr code device connect'))
                    HookBuilder(builder: (context) {
                      final localIp = useState<String?>(RemoteServer.localIp);
                      final waitingForStart = useState(true);

                      useEffect(() {
                        final timeout =
                            Timer(const Duration(milliseconds: 1500), () {
                          waitingForStart.value = false;
                        });
                        final poll = Timer.periodic(
                            const Duration(milliseconds: 300), (_) {
                          final ip = RemoteServer.localIp;
                          if (ip != null) {
                            localIp.value = ip;
                            waitingForStart.value = false;
                          }
                        });
                        return () {
                          timeout.cancel();
                          poll.cancel();
                        };
                      }, [settings.remoteServerEnabled]);

                      final serverUrl = localIp.value != null
                          ? 'http://${localIp.value}:${RemoteServer.port}'
                          : null;
                      final pairingCode = localIp.value != null
                          ? encodeRemotePairing(
                              localIp.value!, RemoteServer.port)
                          : null;

                      return _SectionCard(
                        title: 'REMOTE CONTROL',
                        icon: Icons.cast_rounded,
                        isDark: isDark,
                        cs: cs,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Enable Remote Server',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 14)),
                              Switch(
                                value: settings.remoteServerEnabled,
                                onChanged: remotePairingBusy.value
                                    ? null
                                    : (v) => saveSettings(
                                        {'remoteServerEnabled': v}),
                                activeThumbColor: cs.primary,
                              ),
                            ],
                          ),
                          Text(
                            'Let other devices on Wi‑Fi control playback on this device.',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.45)),
                          ),
                          const SizedBox(height: 16),
                          if (serverUrl != null && pairingCode != null) ...[
                            _SettingsLabel('HOST THIS DEVICE'),
                            const SizedBox(height: 8),
                            Center(
                              child: QrImageView(
                                data: serverUrl,
                                version: QrVersions.auto,
                                size: 160,
                                backgroundColor: Colors.white,
                                padding: const EdgeInsets.all(8),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: SelectableText(
                                formatPairingCodeDisplay(pairingCode),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      fontFamily: 'monospace',
                                      letterSpacing: 2,
                                      color: Colors.white,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () {
                                    Clipboard.setData(
                                        ClipboardData(text: pairingCode));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text('Code copied')));
                                  },
                                  icon:
                                      const Icon(Icons.copy_rounded, size: 16),
                                  label: const Text('Copy code'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    Clipboard.setData(
                                        ClipboardData(text: serverUrl));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text('URL copied')));
                                  },
                                  icon:
                                      const Icon(Icons.link_rounded, size: 16),
                                  label: const Text('Copy URL'),
                                ),
                              ],
                            ),
                          ] else if (!settings.remoteServerEnabled)
                            Text(
                                'Enable the remote server above to host this device.',
                                style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.5))),
                          const SizedBox(height: 24),
                          _SettingsLabel('CONNECT TO ANOTHER DEVICE'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: remotePairingBusy.value
                                      ? null
                                      : () async {
                                          final ep = await Navigator.of(context,
                                                  rootNavigator: true)
                                              .push<RemoteEndpoint>(
                                                  MaterialPageRoute(
                                                      fullscreenDialog: true,
                                                      builder: (_) =>
                                                          const RemoteScanScreen()));
                                          if (ep == null || !context.mounted) {
                                            return;
                                          }
                                          await runPairing(() =>
                                              completeBidirectionalPairing(
                                                  ref, ep));
                                        },
                                  icon: const Icon(
                                      Icons.qr_code_scanner_rounded,
                                      size: 18),
                                  label: const Text('Scan QR',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _StyledTextField(
                            controller: remotePairingCtrl,
                            hint: 'Or paste pairing code/URL',
                            onSubmitted: (val) async {
                              final raw = val.trim();
                              if (raw.isEmpty) return;
                              final ep = parseRemoteConnectionString(raw);
                              if (ep == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Could not parse code/URL')));
                                return;
                              }
                              await runPairing(
                                  () => completeBidirectionalPairing(ref, ep));
                            },
                          ),
                          const SizedBox(height: 8),
                          _SyncButton(
                            label: remotePairingBusy.value
                                ? 'Pairing...'
                                : 'Pair from Text',
                            icon: Icons.link_rounded,
                            color: cs.primary,
                            loading: remotePairingBusy.value,
                            onTap: remotePairingBusy.value
                                ? () {}
                                : () async {
                                    final raw = remotePairingCtrl.text.trim();
                                    if (raw.isEmpty) return;
                                    final ep = parseRemoteConnectionString(raw);
                                    if (ep == null) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text(
                                                  'Could not parse code/URL')));
                                      return;
                                    }
                                    await runPairing(() =>
                                        completeBidirectionalPairing(ref, ep));
                                  },
                          ),
                          const SizedBox(height: 24),
                          _SettingsLabel('PAIRED DEVICE'),
                          const SizedBox(height: 4),
                          if (settings.remoteHostIp.isEmpty)
                            Text('No device paired.',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5)))
                          else ...[
                            Text(
                                '${settings.remoteHostIp}:${settings.remotePeerPort}',
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    color: Colors.white)),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () {
                                      context.go('/remote');
                                    },
                                    icon: const Icon(
                                        Icons.play_circle_outline_rounded,
                                        size: 18),
                                    label: const Text('Control Remote'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Forget pairing',
                                  onPressed: remotePairingBusy.value
                                      ? null
                                      : () async {
                                          await saveSettings({
                                            'remoteHostIp': '',
                                            'remotePeerPort': RemoteServer.port,
                                          });
                                        },
                                  icon: const Icon(Icons.link_off_rounded,
                                      color: Colors.white),
                                ),
                              ],
                            ),
                          ],
                        ],
                      );
                    }),

                  const SizedBox(height: 16),

                  // ── APPEARANCE & LAYOUT ───────────────────────────────────
                  if (showSection(
                      'appearance theme dark light system color accent scheme dynamic material ipad sidebar layout'))
                    Builder(
                      builder: (context) {
                        final mq = MediaQuery.sizeOf(context);
                        final shortest = min(mq.width, mq.height);
                        final showIpadLayout = !kIsWeb &&
                            defaultTargetPlatform == TargetPlatform.iOS &&
                            shortest >= 600;
                        final curatedIds =
                            kFireballSchemeChoices.map((e) => e.$1).toSet();
                        final schemeDropdownItems = <DropdownMenuItem<String>>[
                          if (!curatedIds.contains(settings.flexScheme))
                            DropdownMenuItem(
                              value: settings.flexScheme,
                              child: Text(settings.flexScheme),
                            ),
                          ...kFireballSchemeChoices.map(
                            (e) => DropdownMenuItem(
                              value: e.$1,
                              child: Text(e.$2),
                            ),
                          ),
                        ];

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _SectionCard(
                            title: 'APPEARANCE',
                            icon: Icons.palette_outlined,
                            isDark: isDark,
                            cs: cs,
                            children: [
                              const Text(
                                'Theme',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(
                                    value: 'system',
                                    label: Text('System'),
                                    icon: Icon(Icons.brightness_auto_rounded,
                                        size: 18),
                                  ),
                                  ButtonSegment(
                                    value: 'light',
                                    label: Text('Light'),
                                    icon: Icon(Icons.light_mode_rounded,
                                        size: 18),
                                  ),
                                  ButtonSegment(
                                    value: 'dark',
                                    label: Text('Dark'),
                                    icon:
                                        Icon(Icons.dark_mode_rounded, size: 18),
                                  ),
                                ],
                                selected: {settings.themeMode},
                                onSelectionChanged: (next) {
                                  if (next.isEmpty) return;
                                  saveSettings({'themeMode': next.first});
                                },
                              ),
                              const SizedBox(height: 16),
                              _SettingsLabel('COLOR SCHEME'),
                              DropdownButton<String>(
                                value: settings.flexScheme,
                                isExpanded: true,
                                dropdownColor: const Color(0xFF1A1A1A),
                                style: const TextStyle(color: Colors.white),
                                underline: Container(
                                  height: 1,
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                                items: schemeDropdownItems,
                                onChanged: (v) {
                                  if (v == null) return;
                                  saveSettings({'flexScheme': v});
                                },
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Use dynamic colors',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          settings.accentSeedColor != null
                                              ? 'Disabled while a custom accent is set'
                                              : 'Android 12+ wallpaper colors when available',
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.white
                                                .withValues(alpha: 0.4),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value:
                                        settings.useDynamicColorWhenAvailable,
                                    onChanged: settings.accentSeedColor != null
                                        ? null
                                        : (v) => saveSettings({
                                              'useDynamicColorWhenAvailable': v,
                                            }),
                                    activeThumbColor: cs.primary,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _SettingsLabel('ACCENT (OPTIONAL)'),
                              Text(
                                'Tap a swatch or use scheme default',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.45),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  for (final preset in kFireballAccentPresets)
                                    Tooltip(
                                      message: preset == null
                                          ? 'Scheme default'
                                          : 'Accent #${preset.toRadixString(16)}',
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () => saveSettings(
                                            preset == null
                                                ? {
                                                    'accentSeedColor': null,
                                                  }
                                                : {'accentSeedColor': preset},
                                          ),
                                          customBorder: const CircleBorder(),
                                          child: Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: settings
                                                            .accentSeedColor ==
                                                        preset
                                                    ? cs.primary
                                                    : Colors.white.withValues(
                                                        alpha: 0.2,
                                                      ),
                                                width:
                                                    settings.accentSeedColor ==
                                                            preset
                                                        ? 2.5
                                                        : 1,
                                              ),
                                              color: preset == null
                                                  ? Colors.white
                                                      .withValues(alpha: 0.15)
                                                  : Color(preset),
                                            ),
                                            child: preset == null
                                                ? Icon(
                                                    Icons.palette_outlined,
                                                    size: 18,
                                                    color:
                                                        Colors.white.withValues(
                                                      alpha: 0.8,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (settings.accentSeedColor != null) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () => saveSettings({
                                      'accentSeedColor': null,
                                    }),
                                    icon: const Icon(Icons.restart_alt_rounded,
                                        size: 18),
                                    label: const Text('Clear custom accent'),
                                  ),
                                ),
                              ],
                              if (showIpadLayout) ...[
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Compact iPad sidebar',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            'Icon-only rail to maximize content width',
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.white
                                                  .withValues(alpha: 0.4),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: settings.ipadSidebarCollapsed,
                                      onChanged: (v) => saveSettings({
                                        'ipadSidebarCollapsed': v,
                                      }),
                                      activeThumbColor: cs.primary,
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),

                  // ── YOUTUBE / INVIDIOUS ─────────────────────────────────
                  if (showSection(
                      'youtube invidious instance playlist login trending video'))
                    _SectionCard(
                      title: 'YOUTUBE / INVIDIOUS',
                      icon: Icons.play_circle_outline_rounded,
                      isDark: isDark,
                      cs: cs,
                      children: [
                        _SettingsLabel('INSTANCE URL'),
                        _StyledTextField(
                          controller: invidiousInstanceCtrl,
                          hint: 'https://invidious.example.com',
                        ),
                        const SizedBox(height: 8),
                        _SyncButton(
                          label: testingInvidious.value
                              ? 'Testing...'
                              : 'Test & Save Instance',
                          icon: Icons.check_circle_outline_rounded,
                          color: cs.primary,
                          onTap: testAndSaveInvidious,
                          loading: testingInvidious.value,
                        ),
                        const SizedBox(height: 16),
                        if (settings.invidiousUsername != null) ...[
                          _SettingsLabel('LOGGED IN AS'),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Icon(Icons.account_circle_rounded,
                                    size: 18,
                                    color: cs.primary.withValues(alpha: 0.7)),
                                const SizedBox(width: 8),
                                Text(settings.invidiousUsername!,
                                    style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.7),
                                        fontSize: 14)),
                                const Spacer(),
                                TextButton(
                                  onPressed: () {
                                    invPlaylists.value = [];
                                    saveSettings({
                                      'invidiousSid': null,
                                      'invidiousUsername': null,
                                    });
                                  },
                                  child: const Text('Sign out',
                                      style:
                                          TextStyle(color: Colors.redAccent)),
                                )
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          _SettingsLabel('PLAYLISTS'),
                          if (invPlaylistsLoading.value)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                            )
                          else if (invPlaylists.value.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'No playlists found',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 13),
                              ),
                            )
                          else
                            ...invPlaylists.value.map((pl) {
                              final id = pl['playlistId']?.toString() ?? '';
                              final name =
                                  pl['title']?.toString() ?? 'Playlist';
                              final count = pl['videoCount']?.toString() ?? '';
                              return _PlaylistSyncTile(
                                title: name,
                                subtitle:
                                    count.isNotEmpty ? '$count tracks' : null,
                                onSync: () async {
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  try {
                                    final synced =
                                        await api.syncInvidiousPlaylist(
                                      id,
                                      instanceUrl: settings.invidiousInstance,
                                      sid: settings.invidiousSid,
                                    );
                                    await ref
                                        .read(localStoreProvider.notifier)
                                        .addPlaylist(synced);
                                    messenger.showSnackBar(const SnackBar(
                                        content: Text(
                                            'Playlist synced to Library ✓')));
                                  } catch (e) {
                                    messenger.showSnackBar(SnackBar(
                                        content: Text(
                                            'Sync failed: ${e.toString().replaceAll("Exception: ", "")}')));
                                  }
                                },
                                onTap: () =>
                                    showInvidiousPlaylistPreview(id, name),
                              );
                            }),
                          Row(
                            children: [
                              TextButton.icon(
                                icon:
                                    const Icon(Icons.refresh_rounded, size: 16),
                                label: const Text('Refresh'),
                                onPressed: loadInvidiousPlaylists,
                              ),
                            ],
                          ),
                        ] else ...[
                          _SettingsLabel('LOGIN (OPTIONAL)'),
                          _StyledTextField(
                              controller: invUserCtrl, hint: 'Username'),
                          const SizedBox(height: 8),
                          _StyledTextField(
                              controller: invPassCtrl,
                              hint: 'Password',
                              obscure: true),
                          const SizedBox(height: 8),
                          _SyncButton(
                            label: 'Login',
                            icon: Icons.login_rounded,
                            color: cs.secondary,
                            onTap: invidiousLogin,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Auto-Push to Invidious',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 14)),
                                Text(
                                  'Sync local playlist changes to Invidious',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color:
                                          Colors.white.withValues(alpha: 0.4)),
                                ),
                              ],
                            ),
                            Switch(
                              value: settings.invidiousAutoPush,
                              onChanged: (v) =>
                                  saveSettings({'invidiousAutoPush': v}),
                              activeThumbColor: cs.primary,
                            ),
                          ],
                        ),
                      ],
                    ),

                  const SizedBox(height: 16),

                  // ── STORAGE & DOWNLOADS ──────────────────────────────────
                  if (showSection(
                      'storage downloads location save custom path'))
                    _SectionCard(
                      title: 'STORAGE & DOWNLOADS',
                      icon: Icons.folder_rounded,
                      isDark: isDark,
                      cs: cs,
                      children: [
                        const Text(
                          'Download Location',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        if (!kIsWeb &&
                            defaultTargetPlatform == TargetPlatform.iOS)
                          Text(
                            'iOS restrictions prevent custom download directories. Your tracks are saved in the app Documents folder and are accessible via the native iOS Files app.',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 13),
                          )
                        else ...[
                          Text(
                            settings.customDownloadPath?.isNotEmpty == true
                                ? settings.customDownloadPath!
                                : 'Default App Storage',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final path = await FilePicker.getDirectoryPath();
                                    if (path != null) {
                                      await saveSettings(
                                          {'customDownloadPath': path});
                                    }
                                  },
                                  icon: const Icon(Icons.folder_open_rounded,
                                      size: 18),
                                  label: const Text('Change Location'),
                                ),
                              ),
                              if (settings.customDownloadPath?.isNotEmpty ==
                                  true) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Reset to default',
                                  icon: const Icon(Icons.restore_rounded,
                                      color: Colors.white70),
                                  onPressed: () => saveSettings(
                                      {'customDownloadPath': null}),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),

                  const SizedBox(height: 16),

                  // ── LISTENBRAINZ ─────────────────────────────────────────
                  if (showSection(
                      'listenbrainz brainz token scrobble playing now'))
                    _SectionCard(
                      title: 'LISTENBRAINZ',
                      icon: Icons.graphic_eq_rounded,
                      isDark: isDark,
                      cs: cs,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Enable ListenBrainz',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 14)),
                            Switch(
                              value: settings.listenBrainzEnabled,
                              onChanged: (v) =>
                                  saveSettings({'listenBrainzEnabled': v}),
                              activeThumbColor: cs.primary,
                            ),
                          ],
                        ),
                        _SettingsLabel('TOKEN'),
                        _StyledTextField(
                          controller: lbTokenCtrl,
                          hint: 'Your ListenBrainz user token',
                        ),
                        const SizedBox(height: 8),
                        _SettingsLabel('USERNAME'),
                        _StyledTextField(
                            controller: lbUserCtrl,
                            hint: 'Auto-filled after token test'),
                        const SizedBox(height: 8),
                        _SyncButton(
                          label: testingLB.value
                              ? 'Testing...'
                              : 'Test & Save Token',
                          icon: Icons.verified_rounded,
                          color: const Color(0xFFEB743B),
                          onTap: testAndSaveLB,
                          loading: testingLB.value,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Submit Playing Now',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 14)),
                            Switch(
                              value: settings.listenBrainzPlayingNow,
                              onChanged: (v) =>
                                  saveSettings({'listenBrainzPlayingNow': v}),
                              activeThumbColor: cs.primary,
                            ),
                          ],
                        ),
                      ],
                    ),

                  const SizedBox(height: 16),

                  // ── LAST.FM ──────────────────────────────────────────────
                  if (showSection('last.fm lastfm chart radio api'))
                    _SectionCard(
                      title: 'LAST.FM',
                      icon: Icons.radio_rounded,
                      isDark: isDark,
                      cs: cs,
                      children: [
                        _SettingsLabel('API KEY'),
                        _StyledTextField(
                          controller: lastFmKeyCtrl,
                          hint: 'Your Last.fm API key',
                        ),
                        const SizedBox(height: 8),
                        _SyncButton(
                          label: testingLastFm.value
                              ? 'Testing...'
                              : 'Test & Save Key',
                          icon: Icons.check_circle_outline_rounded,
                          color: const Color(0xFFD51007),
                          onTap: testAndSaveLastFm,
                          loading: testingLastFm.value,
                        ),
                      ],
                    ),

                  const SizedBox(height: 16),

                  // ── OLLAMA AI ────────────────────────────────────────────
                  if (showSection('ollama ai llm queue model'))
                    _SectionCard(
                      title: 'OLLAMA AI QUEUE',
                      icon: Icons.auto_awesome_rounded,
                      isDark: isDark,
                      cs: cs,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Enable AI Queue',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 14)),
                            Switch(
                              value: settings.ollamaEnabled,
                              onChanged: (v) =>
                                  saveSettings({'ollamaEnabled': v}),
                              activeThumbColor: cs.primary,
                            ),
                          ],
                        ),
                        _SettingsLabel('OLLAMA URL'),
                        _StyledTextField(
                          controller: ollamaUrlCtrl,
                          hint: 'http://192.168.1.x:11434',
                        ),
                        const SizedBox(height: 8),
                        _SettingsLabel('MODEL'),
                        _StyledTextField(
                          controller: ollamaModelCtrl,
                          hint: 'llama3.2:3b',
                        ),
                        const SizedBox(height: 8),
                        _SyncButton(
                          label: testingOllama.value
                              ? 'Testing...'
                              : 'Test & Save Ollama',
                          icon: Icons.science_rounded,
                          color: const Color(0xFF7C3AED),
                          onTap: testAndSaveOllama,
                          loading: testingOllama.value,
                        ),
                      ],
                    ),

                  const SizedBox(height: 16),

                  // ── GOTIFY PUSH NOTIFICATIONS ──────────────────────────────
                  if (showSection(
                      'gotify push notifications alerts server token'))
                    _SectionCard(
                      title: 'GOTIFY PUSH NOTIFICATIONS',
                      icon: Icons.notifications_active_rounded,
                      isDark: isDark,
                      cs: cs,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Enable Gotify Push',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 14)),
                            Switch(
                              value: settings.gotifyEnabled,
                              onChanged: (v) =>
                                  saveSettings({'gotifyEnabled': v}),
                              activeThumbColor: cs.primary,
                            ),
                          ],
                        ),
                        _SettingsLabel('GOTIFY SERVER URL'),
                        _StyledTextField(
                          controller: gotifyUrlCtrl,
                          hint: 'https://gotify.example.com',
                          onChanged: (v) => saveSettings({'gotifyUrl': v}),
                        ),
                        const SizedBox(height: 8),
                        _SettingsLabel('APPLICATION TOKEN'),
                        _StyledTextField(
                          controller: gotifyTokenCtrl,
                          hint: 'Your Gotify App Token',
                          onChanged: (v) => saveSettings({'gotifyToken': v}),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sends a push notification to your Gotify server when a followed artist drops a new release.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 16),

                  // ── PLAYBACK ─────────────────────────────────────────────
                  if (showSection(
                      'playback quality audio queue lyrics scroll sync english hindi language reduced motion accessibility'))
                    _SectionCard(
                      title: 'PLAYBACK',
                      icon: Icons.music_note_rounded,
                      isDark: isDark,
                      cs: cs,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('High Quality Audio',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 14)),
                            Switch(
                              value: settings.highQuality,
                              onChanged: (v) =>
                                  saveSettings({'highQuality': v}),
                              activeThumbColor: cs.primary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _SettingsLabel('AI QUEUE MODE'),
                        _QueueModeSelector(
                          value: settings.queueMode,
                          onChanged: (v) => saveSettings({'queueMode': v}),
                          cs: cs,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Auto-scroll synced lyrics',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 14)),
                                Text(
                                  'Follow the active line while playing',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color:
                                          Colors.white.withValues(alpha: 0.4)),
                                ),
                              ],
                            ),
                            Switch(
                              value: settings.lyricsAutoScroll,
                              onChanged: (v) =>
                                  saveSettings({'lyricsAutoScroll': v}),
                              activeThumbColor: cs.primary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Reduced motion for lyrics',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 14)),
                                Text(
                                  'Jump instead of animating when following the active line',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color:
                                          Colors.white.withValues(alpha: 0.4)),
                                ),
                              ],
                            ),
                            Switch(
                              value: settings.lyricsReducedMotion,
                              onChanged: (v) =>
                                  saveSettings({'lyricsReducedMotion': v}),
                              activeThumbColor: cs.primary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Prefer English / Hindi lyrics',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 14)),
                                Text(
                                  'When LRCLIB has several scripts, favor Latin or Devanagari',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color:
                                          Colors.white.withValues(alpha: 0.4)),
                                ),
                              ],
                            ),
                            Switch(
                              value: settings.lyricsPreferEnglishHindi,
                              onChanged: (v) =>
                                  saveSettings({'lyricsPreferEnglishHindi': v}),
                              activeThumbColor: cs.primary,
                            ),
                          ],
                        ),
                      ],
                    ),

                  const SizedBox(height: 16),

                  // ── BACKUP & SYNC ─────────────────────────────────────────
                  if (showSection(
                      'backup sync google drive webdav nextcloud cloud'))
                    _SectionCard(
                      title: 'BACKUP & SYNC',
                      icon: Icons.cloud_sync_rounded,
                      isDark: isDark,
                      cs: cs,
                      children: [
                        // Last backup info
                        if (settings.lastBackupAt != null &&
                            DateTime.tryParse(settings.lastBackupAt!) != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Icon(Icons.history_rounded,
                                    size: 14,
                                    color: Colors.white.withValues(alpha: 0.4)),
                                const SizedBox(width: 6),
                                Text(
                                  'Last backup: ${_fmtTime(DateTime.tryParse(settings.lastBackupAt!)!)}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          Colors.white.withValues(alpha: 0.4)),
                                ),
                              ],
                            ),
                          ),

                        // ── Google Drive ──────────────────────────────────────
                        _SettingsLabel('GOOGLE DRIVE'),
                        if (gDriveUser.value == null)
                          _SyncButton(
                            label: gDriveLoading.value
                                ? 'Signing in...'
                                : 'Sign in with Google',
                            icon: Icons.account_circle_rounded,
                            color: const Color(0xFF4285F4),
                            onTap: gDriveSignIn,
                            loading: gDriveLoading.value,
                          )
                        else ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle_rounded,
                                    size: 16,
                                    color: const Color(0xFF4285F4)
                                        .withValues(alpha: 0.8)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    gDriveUser.value!.email,
                                    style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.8),
                                        fontSize: 13),
                                  ),
                                ),
                                TextButton(
                                  onPressed: gDriveSignOut,
                                  child: const Text('Sign out',
                                      style: TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: _SyncButton(
                                  label: backupLoading.value
                                      ? 'Backing up...'
                                      : 'Back Up Now',
                                  icon: Icons.cloud_upload_rounded,
                                  color: const Color(0xFF4285F4),
                                  onTap: gDriveBackup,
                                  loading: backupLoading.value,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _SyncButton(
                                  label: restoreLoading.value
                                      ? 'Restoring...'
                                      : 'Restore',
                                  icon: Icons.cloud_download_rounded,
                                  color: Colors.green,
                                  onTap: gDriveRestore,
                                  loading: restoreLoading.value,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (gDriveStatus.value.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            gDriveStatus.value,
                            style: TextStyle(
                                fontSize: 12,
                                color: gDriveStatus.value.contains('failed') ||
                                        gDriveStatus.value.contains('Error')
                                    ? Colors.redAccent.withValues(alpha: 0.8)
                                    : Colors.greenAccent
                                        .withValues(alpha: 0.8)),
                          ),
                        ],

                        const SizedBox(height: 20),
                        Divider(color: Colors.white.withValues(alpha: 0.08)),
                        const SizedBox(height: 16),

                        // ── WebDAV / Nextcloud ────────────────────────────────
                        _SettingsLabel('WEBDAV / NEXTCLOUD'),
                        _StyledTextField(
                          controller: webDavUrlCtrl,
                          hint:
                              'https://nextcloud.example.com/remote.php/dav/files/user',
                          onChanged: (_) {},
                        ),
                        const SizedBox(height: 8),
                        _StyledTextField(
                          controller: webDavUserCtrl,
                          hint: 'Username',
                          onChanged: (_) {},
                        ),
                        const SizedBox(height: 8),
                        _StyledTextField(
                          controller: webDavPassCtrl,
                          hint: 'Password / App Token',
                          obscure: true,
                          onChanged: (_) {},
                        ),
                        const SizedBox(height: 8),
                        IntrinsicWidth(
                          child: _SyncButton(
                            label: webDavTesting.value
                                ? 'Testing...'
                                : 'Test Connection',
                            icon: Icons.cable_rounded,
                            color: const Color(0xFF0082C9),
                            onTap: testWebDav,
                            loading: webDavTesting.value,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _SyncButton(
                                label: backupLoading.value
                                    ? 'Backing up...'
                                    : 'Back Up Now',
                                icon: Icons.upload_rounded,
                                color: const Color(0xFF0082C9),
                                onTap: webDavBackup,
                                loading: backupLoading.value,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _SyncButton(
                                label: restoreLoading.value
                                    ? 'Restoring...'
                                    : 'Restore',
                                icon: Icons.download_rounded,
                                color: Colors.green,
                                onTap: webDavRestore,
                                loading: restoreLoading.value,
                              ),
                            ),
                          ],
                        ),
                        if (webDavStatus.value.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            webDavStatus.value,
                            style: TextStyle(
                                fontSize: 12,
                                color: webDavStatus.value.contains('failed') ||
                                        webDavStatus.value.contains('Error')
                                    ? Colors.redAccent.withValues(alpha: 0.8)
                                    : Colors.greenAccent
                                        .withValues(alpha: 0.8)),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Live Sync',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 14)),
                                Text(
                                  'Auto pull/push on app resume',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color:
                                          Colors.white.withValues(alpha: 0.4)),
                                ),
                              ],
                            ),
                            Switch(
                              value: settings.webDavLiveSync,
                              onChanged: (v) =>
                                  saveSettings({'webDavLiveSync': v}),
                              activeThumbColor: cs.primary,
                            ),
                          ],
                        ),
                      ],
                    ),

                  const SizedBox(height: 16),

                  // ── TRENDING COUNTRIES ────────────────────────────────────
                  if (showSection(
                      'trending countries home charts region picker'))
                    _SectionCard(
                      title: 'TRENDING COUNTRIES',
                      icon: Icons.public_rounded,
                      isDark: isDark,
                      cs: cs,
                      children: [
                        Text(
                          'Choose which countries appear in the home screen trending picker.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: kAllCountries.map((entry) {
                            final (code, label) = entry;
                            final selected = settings.homeCountries.isEmpty
                                ? kDefaultHomeCountries.contains(code)
                                : settings.homeCountries.contains(code);
                            return GestureDetector(
                              onTap: () {
                                final current = settings.homeCountries.isEmpty
                                    ? List<String>.from(kDefaultHomeCountries)
                                    : List<String>.from(settings.homeCountries);
                                if (selected) {
                                  if (current.length <= 1) return;
                                  current.remove(code);
                                } else {
                                  current.add(code);
                                }
                                saveSettings({'homeCountries': current});
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? cs.primary.withValues(alpha: 0.25)
                                      : Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: selected
                                        ? cs.primary
                                        : Colors.white.withValues(alpha: 0.12),
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: selected
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.55),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => saveSettings(
                                  {'homeCountries': kDefaultHomeCountries}),
                              child: Text('Reset to defaults',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          cs.primary.withValues(alpha: 0.8))),
                            ),
                          ],
                        ),
                      ],
                    ),

                  const SizedBox(height: 16),

                  // ── SPONSORBLOCK ─────────────────────────────────────────
                  if (showSection(
                      'sponsorblock skip sponsor promo intro outro'))
                    _SectionCard(
                      title: 'SPONSORBLOCK',
                      icon: Icons.fast_forward_rounded,
                      isDark: isDark,
                      cs: cs,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Enable Auto-Skip',
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 14)),
                                  Text(
                                    'Crowd-sourced skipping of non-music segments',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white
                                            .withValues(alpha: 0.4)),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: settings.sponsorBlock,
                              onChanged: (v) =>
                                  saveSettings({'sponsorBlock': v}),
                              activeThumbColor: cs.primary,
                            ),
                          ],
                        ),
                        if (settings.sponsorBlock) ...[
                          const SizedBox(height: 12),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              'Skip Categories',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: SponsorSegment.allCategories.map((cat) {
                              final label = SponsorSegment.categoryLabels[cat]!;
                              final isSelected =
                                  settings.sponsorBlockCategories.contains(cat);

                              return GestureDetector(
                                onTap: () {
                                  final cats = List<String>.from(
                                      settings.sponsorBlockCategories);
                                  if (isSelected) {
                                    cats.remove(cat);
                                  } else {
                                    cats.add(cat);
                                  }
                                  saveSettings(
                                      {'sponsorBlockCategories': cats});
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? cs.primary.withValues(alpha: 0.25)
                                        : Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isSelected
                                          ? cs.primary
                                          : Colors.white
                                              .withValues(alpha: 0.12),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white
                                              .withValues(alpha: 0.55),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),

                  const SizedBox(height: 16),

                  // ── DATA MANAGEMENT ──────────────────────────────────────
                  if (showSection('data management cache history clear reset'))
                    _SectionCard(
                      title: 'DATA',
                      icon: Icons.storage_rounded,
                      isDark: isDark,
                      cs: cs,
                      children: [
                        _DangerButton(
                          label: 'Clear Play History',
                          icon: Icons.history_toggle_off_rounded,
                          onTap: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Clear History?'),
                                content: const Text(
                                    'This will remove all play history.'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancel')),
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Clear',
                                          style: TextStyle(
                                              color: Colors.redAccent))),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await ref
                                  .read(localStoreProvider.notifier)
                                  .clearHistory();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('History cleared')));
                              }
                            }
                          },
                        ),
                      ],
                    ),

                  const SizedBox(height: 16),

                  // App mark + version
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const FireballLogo(size: 56),
                        const SizedBox(height: 10),
                        Text(
                          packageInfo.hasData
                              ? 'Fireball v${packageInfo.data!.version} (${packageInfo.data!.buildNumber})'
                              : 'Fireball',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.2),
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month} $h:$m';
  }
}

// ── UI components ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.isDark,
    required this.cs,
    required this.children,
  });
  final String title;
  final IconData icon;
  final bool isDark;
  final ColorScheme cs;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      opacity: 0.05,
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsLabel extends StatelessWidget {
  const _SettingsLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _StyledTextField extends StatelessWidget {
  const _StyledTextField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.onChanged,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.5),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}

class _SyncButton extends StatelessWidget {
  const _SyncButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.loading = false,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Row(
          children: [
            if (loading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DangerButton extends StatelessWidget {
  const _DangerButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Colors.redAccent.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.redAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueModeSelector extends StatelessWidget {
  const _QueueModeSelector({
    required this.value,
    required this.onChanged,
    required this.cs,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    const modes = [
      ('off', 'Off'),
      ('ai', 'AI Queue'),
      ('repeat', 'Repeat'),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: modes
          .map(
            (m) => GlassPill(
              label: m.$2,
              selected: value == m.$1,
              onTap: () => onChanged(m.$1),
            ),
          )
          .toList(),
    );
  }
}

// ── Invidious playlist sync tile ──────────────────────────────────────────────
class _PlaylistSyncTile extends StatelessWidget {
  const _PlaylistSyncTile({
    required this.title,
    this.subtitle,
    required this.onSync,
    required this.onTap,
  });
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(Icons.queue_music_rounded,
          color: cs.primary.withValues(alpha: 0.8), size: 22),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            )
          : null,
      onTap: onTap,
      trailing: _SyncTrailingButton(onSync: onSync),
    );
  }
}

// ── Small async sync button for playlist tiles ────────────────────────────────
class _SyncTrailingButton extends StatefulWidget {
  const _SyncTrailingButton({required this.onSync});
  final Future<void> Function() onSync;

  @override
  State<_SyncTrailingButton> createState() => _SyncTrailingButtonState();
}

class _SyncTrailingButtonState extends State<_SyncTrailingButton> {
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: _syncing
          ? null
          : () async {
              setState(() => _syncing = true);
              try {
                await widget.onSync();
              } finally {
                if (mounted) setState(() => _syncing = false);
              }
            },
      icon: _syncing
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: cs.secondary))
          : Icon(Icons.download_rounded, size: 16, color: cs.secondary),
      label: Text(_syncing ? '…' : 'Sync',
          style: TextStyle(color: cs.secondary, fontSize: 12)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
    );
  }
}

// ── Invidious playlist preview bottom sheet ───────────────────────────────────
class _InvidiousPlaylistPreview extends HookConsumerWidget {
  const _InvidiousPlaylistPreview({
    required this.playlistId,
    required this.title,
    required this.instanceUrl,
    this.sid,
    required this.onSync,
  });
  final String playlistId;
  final String title;
  final String instanceUrl;
  final String? sid;
  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    const api = FireballApi();
    final playlist = useState<dynamic>(null);
    final loading = useState(true);
    final syncing = useState(false);

    useEffect(() {
      api
          .getInvidiousPlaylistDetail(playlistId,
              instanceUrl: instanceUrl, sid: sid)
          .then((p) {
        playlist.value = p;
        loading.value = false;
      }).catchError((_) {
        loading.value = false;
      });
      return null;
    }, const []);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: syncing.value
                        ? null
                        : () async {
                            syncing.value = true;
                            try {
                              await onSync();
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            } finally {
                              syncing.value = false;
                            }
                          },
                    icon: syncing.value
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download_rounded, size: 16),
                    label: Text(syncing.value ? 'Syncing…' : 'Sync to Library'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            Expanded(
              child: loading.value
                  ? const Center(child: CircularProgressIndicator())
                  : playlist.value == null
                      ? const Center(
                          child: Text('Could not load playlist',
                              style: TextStyle(color: Colors.white54)))
                      : ListView.builder(
                          controller: ctrl,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: (playlist.value!.videos as List).length,
                          itemBuilder: (_, i) {
                            final t = playlist.value!.videos[i];
                            return ListTile(
                              leading: t.artwork != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.network(t.artwork!,
                                          width: 40,
                                          height: 40,
                                          fit: BoxFit.cover))
                                  : const Icon(Icons.music_note_rounded,
                                      color: Colors.white38),
                              title: Text(t.title,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(t.artist,
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
