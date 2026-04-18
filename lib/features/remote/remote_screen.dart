import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/store/providers.dart';
import '../../remote/remote_client.dart';
import '../../remote/remote_pairing.dart';
import '../../remote/remote_server.dart';

/// Two-mode remote control screen.
///
/// **Host mode** (default when no [remoteIp] is given):
///   Shows QR code(s), a pairing code, and the LAN URL.
///
/// **Control mode** (when [remoteIp] is provided):
///   Polls the remote `/state` endpoint about once per second; shows play/pause,
///   next/prev, and seek.
class RemoteScreen extends HookConsumerWidget {
  const RemoteScreen({super.key, this.remoteIp, this.remotePort});

  /// When set, the screen operates in control mode pointing at this host.
  final String? remoteIp;

  /// Port for control mode (defaults to [RemoteServer.port]).
  final int? remotePort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useEffect(() {
      ref.read(remoteScreenCoversShellProvider.notifier).state = true;
      return () {
        ref.read(remoteScreenCoversShellProvider.notifier).state = false;
      };
    }, const []);
    final isControlMode = remoteIp != null && remoteIp!.isNotEmpty;
    return isControlMode
        ? _ControlMode(
            remoteIp: remoteIp!,
            remotePort: remotePort ?? RemoteServer.port,
          )
        : const _HostMode();
  }
}

// ── Host mode ─────────────────────────────────────────────────────────────────

class _HostMode extends HookWidget {
  const _HostMode();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Poll until the remote server has resolved a local IP address.
    // This handles the race where the user opens this screen immediately
    // after toggling "Enable Remote Server" (HttpServer.bind is async).
    final localIp = useState(RemoteServer.localIp);
    // True for ~1.5 s after mount while waiting for the server to bind.
    final waitingForStart = useState(true);

    useEffect(() {
      // After 1.5 s we stop showing "Starting…" regardless.
      final timeout = Timer(const Duration(milliseconds: 1500), () {
        waitingForStart.value = false;
      });

      final poll = Timer.periodic(const Duration(milliseconds: 300), (_) {
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
    }, const []);

    final serverUrl = localIp.value != null
        ? 'http://${localIp.value}:${RemoteServer.port}'
        : null;
    final pairingCode = localIp.value != null
        ? encodeRemotePairing(localIp.value!, RemoteServer.port)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote Control — Host'),
        backgroundColor: cs.surface,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
              if (serverUrl != null && pairingCode != null) ...[
                Text(
                  'Scan this code',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                QrImageView(
                  data: serverUrl,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(12),
                ),
                const SizedBox(height: 16),
                Text(
                  'Pairing code',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                SelectableText(
                  formatPairingCodeDisplay(pairingCode),
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(
                        fontFamily: 'monospace',
                        letterSpacing: 2,
                      ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: pairingCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Pairing code copied')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy code'),
                ),
                const SizedBox(height: 20),
                Text(
                  serverUrl,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: serverUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('URL copied')),
                    );
                  },
                  icon: const Icon(Icons.link_rounded, size: 16),
                  label: const Text('Copy URL'),
                ),
              ] else if (waitingForStart.value) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Starting server…',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ] else ...[
                Icon(Icons.wifi_off_rounded, size: 64, color: cs.outline),
                const SizedBox(height: 16),
                Text(
                  'Remote server is not running.\nEnable it in the Remote tab or Settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'On the other device: open the Remote tab, scan this QR or enter the pairing code. Both devices should enable the remote server.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Control mode ──────────────────────────────────────────────────────────────

class _ControlMode extends HookWidget {
  const _ControlMode({
    required this.remoteIp,
    required this.remotePort,
  });
  final String remoteIp;
  final int remotePort;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final client = useMemoized(
      () => RemoteClient(remoteIp, port: remotePort),
      [remoteIp, remotePort],
    );

    final remoteState = useState<RemoteState?>(null);
    final error = useState<String?>(null);
    final seeking = useState(false);
    final seekValue = useState<double>(0);

    useEffect(() {
      Timer? timer;
      Future<void> poll() async {
        try {
          final s = await client.getState();
          if (context.mounted) {
            remoteState.value = s;
            error.value = null;
          }
        } catch (_) {
          if (context.mounted) {
            error.value = 'Cannot reach $remoteIp';
          }
        }
      }

      poll();
      timer = Timer.periodic(const Duration(seconds: 1), (_) => poll());
      return timer.cancel;
    }, [remoteIp]);

    final s = remoteState.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          remotePort == RemoteServer.port
              ? 'Controlling $remoteIp'
              : 'Controlling $remoteIp:$remotePort',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: cs.surface,
      ),
      // LayoutBuilder + SingleChildScrollView + ConstrainedBox combination
      // prevents overflow on small screens while keeping content centred on
      // large screens.
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (error.value != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_off_rounded,
                            size: 16, color: cs.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            error.value!,
                            style: TextStyle(color: cs.error),
                            textAlign: TextAlign.center,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (s != null) ...[
                  // Artwork
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: s.trackArtwork != null &&
                              s.trackArtwork!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: s.trackArtwork!,
                              width: 200,
                              height: 200,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  _artPlaceholder(cs, size: 200),
                            )
                          : _artPlaceholder(cs, size: 200),
                    ),
                  ),
                  // Title + artist
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      s.trackTitle ?? 'Nothing playing',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (s.trackArtist != null && s.trackArtist!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 4),
                      child: Text(
                        s.trackArtist!,
                        style: TextStyle(color: cs.onSurfaceVariant),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(height: 16),
                  // Progress bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        Slider(
                          value: seeking.value
                              ? seekValue.value
                              : (s.durationMs > 0
                                  ? s.positionMs
                                      .clamp(0, s.durationMs)
                                      .toDouble()
                                  : 0),
                          max: s.durationMs > 0
                              ? s.durationMs.toDouble()
                              : 1,
                          // Disable all interactions when duration is unknown
                          // to prevent sending semantically wrong seek values.
                          onChangeStart:
                              s.durationMs > 0 ? (_) => seeking.value = true : null,
                          onChanged:
                              s.durationMs > 0 ? (v) => seekValue.value = v : null,
                          onChangeEnd: s.durationMs > 0
                              ? (v) async {
                                  // Send seek first; clear seeking flag after so
                                  // the slider doesn't snap back prematurely.
                                  await _send(context, cs,
                                      () => client.sendCommand('seek', value: v));
                                  seeking.value = false;
                                }
                              : null,
                          activeColor: cs.primary,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmt(s.position),
                                style: const TextStyle(fontSize: 12)),
                            Text(_fmt(s.duration),
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 40,
                        onPressed: () => _send(context, cs,
                            () => client.sendCommand('prev')),
                        icon: const Icon(Icons.skip_previous_rounded),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _send(context, cs,
                            () => client.sendCommand('toggle')),
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: cs.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            s.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: cs.onPrimary,
                            size: 36,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        iconSize: 40,
                        onPressed: () => _send(context, cs,
                            () => client.sendCommand('next')),
                        icon: const Icon(Icons.skip_next_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ] else if (error.value == null)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Executes [cmd] and shows a SnackBar on failure so the user knows
  /// a command didn't reach the host.
  static Future<void> _send(
    BuildContext context,
    ColorScheme cs,
    Future<void> Function() cmd,
  ) async {
    try {
      await cmd();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not reach remote device'),
          backgroundColor: cs.error,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  static Widget _artPlaceholder(ColorScheme cs, {required double size}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.06),
      child: Image.asset(
        'assets/icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: cs.surfaceContainerHighest,
          child: Icon(Icons.music_note_rounded,
              size: size * 0.4, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
