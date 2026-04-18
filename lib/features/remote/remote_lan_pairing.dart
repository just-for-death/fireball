import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../core/store/providers.dart';
import '../../remote/remote_client.dart';
import '../../remote/remote_pairing.dart';
import '../../remote/remote_server.dart';

/// Saves [peer] locally and notifies them of this device's address so both
/// sides can open **Control** without re-entering IPs (LAN only; both should
/// enable the remote server).
Future<void> completeBidirectionalPairing(WidgetRef ref, RemoteEndpoint peer) async {
  final store = ref.read(localStoreProvider.notifier);
  await store.updateSettings({
    'remoteHostIp': peer.host,
    'remotePeerPort': peer.port,
  });
  final myIp = RemoteServer.localIp;
  if (myIp == null) {
    throw Exception(
      'Turn on “Remote server” and wait until this device shows a LAN address.',
    );
  }
  final client = RemoteClient(peer.host, port: peer.port);
  await client.registerPair(myIp, RemoteServer.port);
}
