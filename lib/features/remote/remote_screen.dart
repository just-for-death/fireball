import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/store/providers.dart';
import '../../remote/remote_client.dart';
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

  final String? remoteIp;
  final int? remotePort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    // Use provided parameters or fallback to settings
    final ip = remoteIp ?? settings.remoteHostIp;
    final port = remotePort ?? settings.remotePeerPort;

    // We no longer need to manually set remoteScreenCoversShellProvider
    // because ShellScaffold automatically hides the mini player when
    // shell.currentIndex == kRemoteShellTabIndex.

    final isControlMode = ip.isNotEmpty;
    if (!isControlMode) {
      final cs = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Remote'),
          backgroundColor: cs.surface,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cast_connected_rounded, size: 64, color: cs.outline),
              const SizedBox(height: 16),
              Text(
                'No device paired.\nGo to Settings to pair a remote device.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.go('/settings'),
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      );
    }

    return _ControlMode(
      remoteIp: ip,
      remotePort: port,
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
                        Icon(Icons.wifi_off_rounded, size: 16, color: cs.error),
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
                      child:
                          s.trackArtwork != null && s.trackArtwork!.isNotEmpty
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
                          max: s.durationMs > 0 ? s.durationMs.toDouble() : 1,
                          // Disable all interactions when duration is unknown
                          // to prevent sending semantically wrong seek values.
                          onChangeStart: s.durationMs > 0
                              ? (_) => seeking.value = true
                              : null,
                          onChanged: s.durationMs > 0
                              ? (v) => seekValue.value = v
                              : null,
                          onChangeEnd: s.durationMs > 0
                              ? (v) async {
                                  // Send seek first; clear seeking flag after so
                                  // the slider doesn't snap back prematurely.
                                  await _send(
                                      context,
                                      cs,
                                      () =>
                                          client.sendCommand('seek', value: v));
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
                        onPressed: () => _send(
                            context, cs, () => client.sendCommand('prev')),
                        icon: const Icon(Icons.skip_previous_rounded),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _send(
                            context, cs, () => client.sendCommand('toggle')),
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
                        onPressed: () => _send(
                            context, cs, () => client.sendCommand('next')),
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
