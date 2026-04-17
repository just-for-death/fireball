import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/api/fireball_api.dart';
import '../../core/store/providers.dart';
import '../../core/widgets/glass_widgets.dart';
import '../../sync/gdrive_sync.dart';
import '../../sync/webdav_sync.dart';

class SettingsScreen extends HookConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    const api = FireballApi();
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final saving = useState(false);

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

    // Testing states
    final testingLB = useState(false);
    final testingLastFm = useState(false);
    final testingOllama = useState(false);
    final testingInvidious = useState(false);

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
      return null;
    }, [settings]);

    // Check Google sign-in status on mount
    useEffect(() {
      GDriveSync.currentUser.then((u) => gDriveUser.value = u);
      return null;
    }, const []);

    Future<void> saveSettings(Map<String, dynamic> patch) async {
      await ref.read(localStoreProvider.notifier).updateSettings(patch);
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
        final username = res['user_name']?.toString() ??
            res['username']?.toString() ?? '';
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
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Last.fm test failed: $e')));
        }
      } finally {
        testingLastFm.value = false;
      }
    }

    Future<void> testAndSaveOllama() async {
      final url = ollamaUrlCtrl.text.trim();
      final model = ollamaModelCtrl.text.trim();
      if (url.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Enter an Ollama URL')));
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
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ollama verified ✓')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Ollama failed: $e')));
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
        await api.invidiousSearch('test', instanceUrl: sanitized);
        await saveSettings({'invidiousInstance': sanitized});
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invidious instance verified ✓')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Invidious failed: $e')));
        }
      } finally {
        testingInvidious.value = false;
      }
    }

    Future<void> invidiousLogin() async {
      final instance = invidiousInstanceCtrl.text.trim();
      final user = invUserCtrl.text.trim();
      final pass = invPassCtrl.text.trim();
      if (instance.isEmpty || user.isEmpty || pass.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fill in instance, username, and password')));
        return;
      }
      try {
        final sanitized = Uri.parse(instance).origin;
        final res = await api.invidiousLogin(sanitized, user, pass);
        final sid = res['sid']?.toString() ?? '';
        await saveSettings({
          'invidiousInstance': sanitized,
          'invidiousUsername': user,
          'invidiousSid': sid,
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invidious login successful ✓')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Login failed: $e')));
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
        webDavStatus.value = ok ? 'Connection successful ✓' : 'Connection failed';
      } catch (e) {
        webDavStatus.value = 'Error: $e';
      } finally {
        webDavTesting.value = false;
      }
    }

    Future<void> webDavBackup() async {
      await saveWebDavSettings();
      backupLoading.value = true;
      webDavStatus.value = 'Backing up...';
      try {
        final json = ref.read(localStoreProvider.notifier).exportJson();
        await WebDavSync.backup(
          serverUrl: settings.webDavUrl,
          username: settings.webDavUsername,
          password: settings.webDavPassword,
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
      restoreLoading.value = true;
      webDavStatus.value = 'Restoring...';
      try {
        final json = await WebDavSync.restore(
          serverUrl: settings.webDavUrl,
          username: settings.webDavUsername,
          password: settings.webDavPassword,
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

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 160),
                children: [

                  // ── YOUTUBE / INVIDIOUS ─────────────────────────────────
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
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Icon(Icons.account_circle_rounded,
                                  size: 18,
                                  color: cs.primary.withValues(alpha: 0.7)),
                              const SizedBox(width: 8),
                              Text(settings.invidiousUsername!,
                                  style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontSize: 14)),
                              const Spacer(),
                              TextButton(
                                onPressed: () => saveSettings({
                                  'invidiousSid': null,
                                  'invidiousUsername': null,
                                }),
                                child: const Text('Sign out',
                                    style: TextStyle(color: Colors.redAccent)),
                              )
                            ],
                          ),
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
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ── LISTENBRAINZ ─────────────────────────────────────────
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
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ── LAST.FM ──────────────────────────────────────────────
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

                  // ── PLAYBACK ─────────────────────────────────────────────
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
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ── BACKUP & SYNC ─────────────────────────────────────────
                  _SectionCard(
                    title: 'BACKUP & SYNC',
                    icon: Icons.cloud_sync_rounded,
                    isDark: isDark,
                    cs: cs,
                    children: [
                      // Last backup info
                      if (settings.lastBackupAt != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Icon(Icons.history_rounded,
                                  size: 14,
                                  color: Colors.white.withValues(alpha: 0.4)),
                              const SizedBox(width: 6),
                              Text(
                                'Last backup: ${_fmtTime(DateTime.parse(settings.lastBackupAt!))}',
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
                                  color:
                                      const Color(0xFF4285F4).withValues(alpha: 0.8)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  gDriveUser.value!.email,
                                  style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.8),
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
                                  : Colors.greenAccent.withValues(alpha: 0.8)),
                        ),
                      ],

                      const SizedBox(height: 20),
                      Divider(color: Colors.white.withValues(alpha: 0.08)),
                      const SizedBox(height: 16),

                      // ── WebDAV / Nextcloud ────────────────────────────────
                      _SettingsLabel('WEBDAV / NEXTCLOUD'),
                      _StyledTextField(
                        controller: webDavUrlCtrl,
                        hint: 'https://nextcloud.example.com/remote.php/dav/files/user',
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
                                  : Colors.greenAccent.withValues(alpha: 0.8)),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ── DATA MANAGEMENT ──────────────────────────────────────
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

                  // App version
                  Center(
                    child: Text(
                      'Fireball v1.0.0',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.2),
                          fontSize: 12),
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
              Text(
                title,
                style: TextStyle(
                  color: cs.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
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
  });
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.1), width: 0.5),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: color.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: color),
              )
            else
              Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
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
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Colors.redAccent.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
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
    return Row(
      children: modes
          .map((m) => Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GlassPill(
                  label: m.$2,
                  selected: value == m.$1,
                  onTap: () => onChanged(m.$1),
                ),
              ))
          .toList(),
    );
  }
}
