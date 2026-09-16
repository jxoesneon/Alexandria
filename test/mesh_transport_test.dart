import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/mesh_transport_service.dart';

void main() {
  group('MeshTransportService Tests', () {
    late MeshTransportService mesh;

    setUp(() {
      // Injected handshake probe simulates a completed ALX-MESH/1
      // HELLO/ACK exchange - registration alone is no longer proof of
      // reachability (round-3 red finding).
      mesh = MeshTransportService(handshakeProbe: (_) async => true);
    });

    tearDown(() {
      mesh.dispose();
    });

    test('registered peers are unreachable until a handshake proves them',
        () async {
      const addr = '/ip4/192.168.1.50/tcp/4001/p2p/peer_1';
      mesh.registerPeer(MeshPeer(
        peerId: 'peer_1',
        address: addr,
        tier: TransportTier.lanMdns,
        latencyMs: 5,
        isReachable: true, // forged - must be clamped off
      ));
      expect(mesh.activePeers, isEmpty);

      final ok = await mesh.connectToPeer(addr);
      expect(ok, isTrue);
      expect(mesh.activePeers.length, equals(1));
      expect(mesh.activePeers.first.peerId, equals('peer_1'));
    });

    test('selects best transport tier for a handshake-proven peer', () async {
      const addr = '/ip4/192.168.1.60/tcp/4001/p2p/peer_ble';
      mesh.registerPeer(MeshPeer(
        peerId: 'peer_ble',
        address: addr,
        tier: TransportTier.bleProximity,
        latencyMs: 80,
      ));

      // Unproven: no transport is selected
      expect(mesh.selectBestTransport('peer_ble'), isNull);

      await mesh.connectToPeer(addr);
      final best = mesh.selectBestTransport('peer_ble');
      expect(best, equals(TransportTier.bleProximity));
    });
  });
}
