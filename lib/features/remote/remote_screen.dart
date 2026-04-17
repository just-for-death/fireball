import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../remote/remote_client.dart';
import '../../remote/remote_server.dart';

/// Two-mode remote control screen.
///
/// **Host mode** (default when no [remoteIp] is given):
///   Shows a QR code + text URL that the controller device can scan/enter.
///
/// **Control mode** (when [remoteIp] is provided):
///   Polls the remote /state endpoint every 2 s and shows a mini player UI
///   with play/pause, next/prev, and a seek bar.
class RemoteScreen extends StatelessWidget {
  const RemoteScreen({super.key, this.remoteIp});

  /// When set, the screen operates in control mode pointing at this IP.
  final String? remoteIp;

  @override
  Widget build(BuildContext context) {
    final isControlMode = remoteIp != null && remoteIp!.isNotEmpty;
    return isControlMode
        ? _ControlMode(remoteIp: remoteIp!)
        : const _HostMode();
  }
}

// ── Host mode ─────────────────────────────────────────────────────────────────

class _HostMode extends StatelessWidget {
  const _HostMode();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final localIp = RemoteServer.localIp;
    final serverUrl = localIp != null
        ? 'http://$localIp:${RemoteServer.port}'
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote Control — Host'),
        backgroundColor: cs.surface,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (serverUrl != null) ...[
                QrImageView(
                  data: serverUrl,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(12),
                ),
                const SizedBox(height: 24),
                Text(
                  serverUrl,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: serverUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy URL'),
                ),
              ] else ...[
                Icon(Icons.wifi_off_rounded, size: 64, color: cs.outline),
                const SizedBox(height: 16),
                Text(
                  'Remote server is not running.\nEnable it in Settings → Remote Control.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 32),
              Text(
                'Scan the QR code or enter the URL on the controller device.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Control mode ──────────────────────────────────────────────────────────────

class _ControlMode extends HookWidget {
  const _ControlMode({required this.remoteIp});
  final String remoteIp;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final client = useMemoized(() => RemoteClient(remoteIp), [remoteIp]);

    final state = useState<RemoteState?>(null);
    final error = useState<String?>(null);
    final seeking = useState(false);
    final seekValue = useState<double>(0);

    useEffect(() {
      Timer? timer;
      Future<void> poll() async {
        try {
          final s = await client.getState();
          if (context.mounted) {
            state.value = s;
            error.value = null;
          }
        } catch (e) {
          if (context.mounted) {
            error.value = 'Cannot reach $remoteIp';
          }
        }
      }

      poll();
      timer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
      return timer.cancel;
    }, [remoteIp]);

    final s = state.value;

    return Scaffold(
      appBar: AppBar(
        title: Text('Controlling $remoteIp'),
        backgroundColor: cs.surface,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (error.value != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                error.value!,
                style: TextStyle(color: cs.error),
                textAlign: TextAlign.center,
              ),
            ),
          if (s != null) ...[
            // Artwork
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: s.trackArtwork != null && s.trackArtwork!.isNotEmpty
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
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
                            ? s.positionMs.clamp(0, s.durationMs).toDouble()
                            : 0),
                    max: s.durationMs > 0 ? s.durationMs.toDouble() : 1,
                    onChangeStart: (_) => seeking.value = true,
                    onChanged: (v) => seekValue.value = v,
                    onChangeEnd: (v) async {
                      seeking.value = false;
                      await client.sendCommand('seek', value: v);
                    },
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
                  onPressed: () => client.sendCommand('prev'),
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => client.sendCommand('toggle'),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      s.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: cs.onPrimary,
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  iconSize: 40,
                  onPressed: () => client.sendCommand('next'),
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ],
            ),
          ] else if (error.value == null)
            const CircularProgressIndicator(),
        ],
      ),
    );
  }

  static Widget _artPlaceholder(ColorScheme cs, {required double size}) {
    return Container(
      width: size,
      height: size,
      color: cs.surfaceContainerHighest,
      child: Icon(Icons.music_note_rounded,
          size: size * 0.4, color: cs.onSurfaceVariant),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
