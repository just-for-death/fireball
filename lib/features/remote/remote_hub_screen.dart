import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/store/providers.dart';
import '../../remote/remote_pairing.dart';
import '../../remote/remote_server.dart';
import 'remote_lan_pairing.dart';
import 'remote_scan_screen.dart';
import 'remote_screen.dart';

/// Dedicated tab: host QR, pairing code, scan, and control of the paired device.
class RemoteHubScreen extends HookConsumerWidget {
  const RemoteHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final cs = Theme.of(context).colorScheme;
    final busy = useState(false);
    final manualCtrl = useTextEditingController();

    Future<void> runPairing(Future<void> Function() fn) async {
      busy.value = true;
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
        busy.value = false;
      }
    }

    final localIp = RemoteServer.localIp;
    final serverUrl =
        localIp != null ? 'http://$localIp:${RemoteServer.port}' : null;
    final pairingCode = localIp != null
        ? encodeRemotePairing(localIp, RemoteServer.port)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote'),
        backgroundColor: cs.surface,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          24 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          Card(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
            child: SwitchListTile(
              secondary: Icon(Icons.cast_rounded, color: cs.primary),
              title: const Text('Remote server'),
              subtitle: const Text(
                'Let other devices on Wi‑Fi control playback on this device',
              ),
              value: settings.remoteServerEnabled,
              onChanged: busy.value
                  ? null
                  : (v) => ref
                      .read(localStoreProvider.notifier)
                      .updateSettings({'remoteServerEnabled': v}),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Host this device',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'One QR code works in Fireball or any scanner. The pairing code is for typing.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (serverUrl != null && pairingCode != null) ...[
            Center(
              child: QrImageView(
                data: serverUrl,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                padding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              formatPairingCodeDisplay(pairingCode),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 1.5,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: pairingCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Pairing code copied')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy code'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: serverUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('URL copied')),
                    );
                  },
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: const Text('Copy URL'),
                ),
              ],
            ),
          ] else if (!settings.remoteServerEnabled)
            Text(
              'Enable the remote server above to show a QR code.',
              style: TextStyle(color: cs.onSurfaceVariant),
            )
          else
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 28),
          Text(
            'Connect to another device',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Scan their QR or enter a pairing code. Both devices should enable the remote server and be on the same Wi‑Fi.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 420;
              final scanBtn = Tooltip(
                message: 'Scan another device’s pairing QR',
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                  ),
                  onPressed: busy.value
                      ? null
                      : () async {
                          final ep =
                              await Navigator.of(context, rootNavigator: true)
                                  .push<RemoteEndpoint>(
                            MaterialPageRoute(
                              fullscreenDialog: true,
                              builder: (_) => const RemoteScanScreen(),
                            ),
                          );
                          if (ep == null || !context.mounted) return;
                          await runPairing(
                            () => completeBidirectionalPairing(ref, ep),
                          );
                        },
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                  label: const Text(
                    'Scan QR',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
              final hostBtn = Tooltip(
                message: 'Show this device’s pairing QR and code',
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                  ),
                  onPressed: busy.value
                      ? null
                      : () =>
                          Navigator.of(context, rootNavigator: true).push<void>(
                            MaterialPageRoute<void>(
                              fullscreenDialog: true,
                              builder: (_) => const RemoteScreen(),
                            ),
                          ),
                  icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                  label: const Text(
                    'Host QR',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
              if (!remoteQrScanSupported) {
                return SizedBox(width: double.infinity, child: hostBtn);
              }
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    scanBtn,
                    const SizedBox(height: 10),
                    hostBtn,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: scanBtn),
                  const SizedBox(width: 8),
                  Expanded(child: hostBtn),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: manualCtrl,
            decoration: const InputDecoration(
              labelText: 'Pairing code or URL',
              hintText: 'Paste code or http://…',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => {},
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: busy.value
                ? null
                : () async {
                    final raw = manualCtrl.text.trim();
                    if (raw.isEmpty) return;
                    final ep = parseRemoteConnectionString(raw);
                    if (ep == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not parse this code or URL'),
                        ),
                      );
                      return;
                    }
                    await runPairing(
                      () => completeBidirectionalPairing(ref, ep),
                    );
                  },
            child: const Text('Pair from text'),
          ),
          const SizedBox(height: 28),
          Text(
            'Paired device',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (settings.remoteHostIp.isEmpty)
            Text(
              'No device paired yet.',
              style: TextStyle(color: cs.onSurfaceVariant),
            )
          else ...[
            Text(
              '${settings.remoteHostIp}:${settings.remotePeerPort}',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 420;
                final controlBtn = Tooltip(
                  message: 'Open remote playback controls',
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    onPressed: busy.value
                        ? null
                        : () {
                            Navigator.of(context, rootNavigator: true)
                                .push<void>(
                              MaterialPageRoute<void>(
                                fullscreenDialog: true,
                                builder: (_) => RemoteScreen(
                                  remoteIp: settings.remoteHostIp,
                                  remotePort: settings.remotePeerPort,
                                ),
                              ),
                            );
                          },
                    icon:
                        const Icon(Icons.play_circle_outline_rounded, size: 22),
                    label: const Text(
                      'Control remote',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
                final forgetBtn = IconButton(
                  tooltip: 'Forget pairing',
                  onPressed: busy.value
                      ? null
                      : () async {
                          await ref
                              .read(localStoreProvider.notifier)
                              .updateSettings({
                            'remoteHostIp': '',
                            'remotePeerPort': RemoteServer.port,
                          });
                        },
                  icon: const Icon(Icons.link_off_rounded),
                );
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      controlBtn,
                      Align(
                        alignment: Alignment.centerRight,
                        child: forgetBtn,
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: controlBtn),
                    const SizedBox(width: 4),
                    forgetBtn,
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
