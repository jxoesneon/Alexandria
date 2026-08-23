import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/mesh_transport_service.dart';

void main() {
  group('MeshTransportService Tests', () {
    late MeshTransportService mesh;

    setUp(() {
      mesh = MeshTransportService();
    });

    tearDown(() {
      mesh.dispose();
    });

    test('registers peers and retrieves active reachable peers', () {
      final p1 = MeshPeer(
        peerId: 'peer_1',
        address: '192.168.1.50:4001',
        tier: TransportTier.lanMdns,
        latencyMs: 5,
      );

      mesh.registerPeer(p1);
      expect(mesh.activePeers.length, equals(1));
      expect(mesh.activePeers.first.peerId, equals('peer_1'));
    });

    test('selects best transport tier based on priority and availability', () {
      final p1 = MeshPeer(
        peerId: 'peer_ble',
        address: 'ble://device-addr',
        tier: TransportTier.bleProximity,
        latencyMs: 80,
      );

      mesh.registerPeer(p1);
      final best = mesh.selectBestTransport('peer_ble');
      expect(best, equals(TransportTier.bleProximity));
    });
  });
}
