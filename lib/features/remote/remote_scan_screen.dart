import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../remote/remote_pairing.dart';

/// Whether this platform can use the camera to scan QR codes (mobile only).
bool get remoteQrScanSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Full-screen QR scanner; pops with [RemoteEndpoint] on success.
class RemoteScanScreen extends StatefulWidget {
  const RemoteScanScreen({super.key});

  @override
  State<RemoteScanScreen> createState() => _RemoteScanScreenState();
}

class _RemoteScanScreenState extends State<RemoteScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _tryDecode(String? raw) {
    if (_handled || raw == null || raw.isEmpty) return;
    final ep = parseRemoteConnectionString(raw);
    if (ep == null) return;
    _handled = true;
    _controller.stop();
    if (mounted) Navigator.of(context).pop(ep);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan remote QR'),
        backgroundColor: cs.surface,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (BarcodeCapture capture) {
              for (final b in capture.barcodes) {
                _tryDecode(b.rawValue ?? b.displayValue);
              }
            },
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Point at the QR on the host device (Fireball or “any app” code).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurface, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
