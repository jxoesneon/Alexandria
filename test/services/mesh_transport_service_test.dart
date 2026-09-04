import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/mesh_transport_service.dart';

void main() {
  group('MeshTransportService (test/services)', () {
    late MeshTransportService mesh;

    setUp(() {
      mesh = MeshTransportService();
    });

    tearDown(() {
      mesh.dispose();
    });

    test('provider exposes a service instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(meshTransportServiceProvider),
          isA<MeshTransportService>());
    });

    test('registerPeer emits on discovery and peer list streams', () async {
      final peer = MeshPeer(
        peerId: 'p1',
        address: '/ip4/1.2.3.4/p2p/p1',
        tier: TransportTier.lanMdns,
        latencyMs: 5,
      );

      final discovered = expectLater(mesh.onPeerDiscovered, emits(peer));
      final listed = expectLater(mesh.peerListStream, emits(hasLength(1)));

      mesh.registerPeer(peer);
      await discovered;
      await listed;
    });

    test('unregisterPeer removes peer and emits updated list', () {
      mesh.registerPeer(MeshPeer(
        peerId: 'p2',
        address: '/ip4/1.2.3.4/p2p/p2',
        tier: TransportTier.wifiDirect,
        latencyMs: 10,
      ));

      mesh.unregisterPeer('p2');
      expect(mesh.peers, isEmpty);
      expect(mesh.activePeers, isEmpty);
    });

    test('tier toggling and isTierEnabled reflect state', () {
      expect(mesh.isTierEnabled(TransportTier.webrtcDirect), isTrue);

      mesh.setTierEnabled(TransportTier.webrtcDirect, false);
      expect(mesh.isTierEnabled(TransportTier.webrtcDirect), isFalse);

      mesh.setTierEnabled(TransportTier.webrtcDirect, true);
      expect(mesh.isTierEnabled(TransportTier.webrtcDirect), isTrue);
    });

    test('selectBestTransport returns peer tier when active', () {
      mesh.registerPeer(MeshPeer(
        peerId: 'p3',
        address: '/ip4/1.2.3.4/p2p/p3',
        tier: TransportTier.bleProximity,
        latencyMs: 15,
      ));

      expect(
          mesh.selectBestTransport('p3'), equals(TransportTier.bleProximity));
    });

    test('selectBestTransport falls back to highest priority active tier', () {
      mesh.setTierEnabled(TransportTier.bleProximity, false);
      mesh.registerPeer(MeshPeer(
        peerId: 'p4',
        address: '/ip4/1.2.3.4/p2p/p4',
        tier: TransportTier.bleProximity,
        latencyMs: 15,
      ));

      final best = mesh.selectBestTransport('p4');
      expect(best, equals(TransportTier.lanMdns));
    });

    test('selectBestTransport returns null for missing or unreachable peer',
        () {
      expect(mesh.selectBestTransport('missing'), isNull);

      mesh.registerPeer(MeshPeer(
        peerId: 'p5',
        address: '/ip4/1.2.3.4/p2p/p5',
        tier: TransportTier.lanMdns,
        latencyMs: 5,
        isReachable: false,
      ));
      expect(mesh.selectBestTransport('p5'), isNull);
    });

    test('sendPayload returns false when no transport is available', () async {
      mesh.registerPeer(MeshPeer(
        peerId: 'p6',
        address: '/ip4/1.2.3.4/p2p/p6',
        tier: TransportTier.bleProximity,
        latencyMs: 5,
      ));
      for (final tier in TransportTier.values) {
        mesh.setTierEnabled(tier, false);
      }
      final ok = await mesh.sendPayload('p6', Uint8List.fromList([1, 2, 3]));
      expect(ok, isFalse);
    });

    test('sendPayload returns true for a valid peer and tier', () async {
      mesh.registerPeer(MeshPeer(
        peerId: 'p7',
        address: '/ip4/1.2.3.4/p2p/p7',
        tier: TransportTier.lanMdns,
        latencyMs: 5,
      ));
      final ok = await mesh.sendPayload('p7', Uint8List.fromList([1, 2, 3]));
      expect(ok, isTrue);
    });

    test('connectToPeer updates an existing peer', () async {
      const multiaddr = '/ip4/1.2.3.4/tcp/4001/p2p/existing';
      mesh.registerPeer(MeshPeer(
        peerId: 'existing',
        address: multiaddr,
        tier: TransportTier.webrtcDirect,
        latencyMs: 100,
        isReachable: false,
      ));

      final ok = await mesh.connectToPeer(multiaddr);
      expect(ok, isTrue);

      final peer = mesh.peers.firstWhere((p) => p.peerId == 'existing');
      expect(peer.isReachable, isTrue);
      expect(peer.isPending, isFalse);
    });

    test('disconnectPeer marks an existing peer unreachable', () async {
      const multiaddr = '/ip4/1.2.3.4/tcp/4001/p2p/dc';
      await mesh.connectToPeer(multiaddr);

      await mesh.disconnectPeer('dc');
      final peer = mesh.peers.firstWhere((p) => p.peerId == 'dc');
      expect(peer.isReachable, isFalse);
      expect(peer.isPending, isFalse);
    });

    test('dispose closes all broadcast streams', () async {
      mesh.dispose();
      await expectLater(mesh.onPeerDiscovered, emitsDone);
      await expectLater(mesh.onPayloadReceived, emitsDone);
      await expectLater(mesh.peerListStream, emitsDone);
    });
  });
}
