import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/mesh_transport_service.dart';

void main() {
  group('MeshTransportService extra tests', () {
    late MeshTransportService mesh;

    setUp(() {
      mesh = MeshTransportService();
    });

    tearDown(() {
      mesh.dispose();
    });

    test('watchPeers yields current peers and further updates', () async {
      final peer = MeshPeer(
        peerId: 'p1',
        address: '/ip4/1.2.3.4/p2p/p1',
        tier: TransportTier.lanMdns,
        latencyMs: 10,
      );
      mesh.registerPeer(peer);

      final peers = await mesh.watchPeers().first;
      expect(peers, hasLength(1));
      expect(peers.first.peerId, equals('p1'));
    });

    test('connectToPeer creates a reachable peer from a multiaddr', () async {
      // Simulated successful handshake — the default probe requires a
      // real endpoint (round-2 fix).
      final probedMesh =
          MeshTransportService(handshakeProbe: (_) async => true);
      addTearDown(probedMesh.dispose);
      const multiaddr = '/ip4/1.2.3.4/tcp/4001/p2p/new-peer';
      final ok = await probedMesh.connectToPeer(multiaddr);
      expect(ok, isTrue);

      final peer = probedMesh.peers.firstWhere((p) => p.peerId == 'new-peer');
      expect(peer.isReachable, isTrue);
      expect(peer.isPending, isFalse);
      expect(peer.address, equals(multiaddr));
    });

    test('connectToPeer returns false for invalid multiaddr', () async {
      final ok = await mesh.connectToPeer('/ip4/1.2.3.4/tcp/4001');
      expect(ok, isFalse);
    });

    test('disconnectPeer marks the peer unreachable', () async {
      const multiaddr = '/ip4/1.2.3.4/tcp/4001/p2p/peer-dc';
      await mesh.connectToPeer(multiaddr);

      await mesh.disconnectPeer('peer-dc');
      final peer = mesh.peers.firstWhere((p) => p.peerId == 'peer-dc');
      expect(peer.isReachable, isFalse);
      expect(mesh.activePeers, isEmpty);
    });
  });
}
