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

      // The emitted object is the clamped copy (round-3 fix: caller's
      // isReachable is never trusted), so match on peerId + state.
      final discovered = expectLater(
          mesh.onPeerDiscovered,
          emits(predicate<MeshPeer>(
              (p) => p.peerId == 'p1' && !p.isReachable && p.isPending)));
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

    test('selectBestTransport returns peer tier when active', () async {
      // Probe simulates a completed handshake - registration alone is
      // no longer proof of reachability (round-3 fix).
      final probedMesh =
          MeshTransportService(handshakeProbe: (_) async => true);
      addTearDown(probedMesh.dispose);
      const addr3 = '/ip4/1.2.3.4/tcp/4001/p2p/p3';
      probedMesh.registerPeer(MeshPeer(
        peerId: 'p3',
        address: addr3,
        tier: TransportTier.bleProximity,
        latencyMs: 15,
      ));

      expect(probedMesh.selectBestTransport('p3'), isNull);
      await probedMesh.connectToPeer(addr3);
      expect(probedMesh.selectBestTransport('p3'),
          equals(TransportTier.bleProximity));
    });

    test('selectBestTransport falls back to highest priority active tier',
        () async {
      final probedMesh =
          MeshTransportService(handshakeProbe: (_) async => true);
      addTearDown(probedMesh.dispose);
      probedMesh.setTierEnabled(TransportTier.bleProximity, false);
      const addr4 = '/ip4/1.2.3.4/tcp/4001/p2p/p4';
      probedMesh.registerPeer(MeshPeer(
        peerId: 'p4',
        address: addr4,
        tier: TransportTier.bleProximity,
        latencyMs: 15,
      ));

      await probedMesh.connectToPeer(addr4);
      final best = probedMesh.selectBestTransport('p4');
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

    test('sendPayload returns true for a handshake-proven peer', () async {
      final probedMesh =
          MeshTransportService(handshakeProbe: (_) async => true);
      addTearDown(probedMesh.dispose);
      const addr7 = '/ip4/1.2.3.4/tcp/4001/p2p/p7';
      probedMesh.registerPeer(MeshPeer(
        peerId: 'p7',
        address: addr7,
        tier: TransportTier.lanMdns,
        latencyMs: 5,
      ));
      await probedMesh.connectToPeer(addr7);
      final ok =
          await probedMesh.sendPayload('p7', Uint8List.fromList([1, 2, 3]));
      expect(ok, isTrue);
    });

    test('connectToPeer updates an existing peer', () async {
      // Inject a probe that simulates a completed handshake - the
      // default probe performs a real TCP connect (round-2 fix).
      final probedMesh =
          MeshTransportService(handshakeProbe: (_) async => true);
      addTearDown(probedMesh.dispose);
      const multiaddr = '/ip4/1.2.3.4/tcp/4001/p2p/existing';
      probedMesh.registerPeer(MeshPeer(
        peerId: 'existing',
        address: multiaddr,
        tier: TransportTier.webrtcDirect,
        latencyMs: 100,
        isReachable: false,
      ));

      final ok = await probedMesh.connectToPeer(multiaddr);
      expect(ok, isTrue);

      final peer = probedMesh.peers.firstWhere((p) => p.peerId == 'existing');
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

    test('bootstrap peers start unproven until a real handshake', () async {
      final bootstrapped = MeshTransportService(
        bootstrap: true,
        handshakeProbe: (_) async => true,
      );
      addTearDown(bootstrapped.dispose);

      // Seeded candidates are pending/unproven - never claimed reachable
      expect(bootstrapped.peers.length, equals(4));
      expect(bootstrapped.activePeers, isEmpty);
      for (final p in bootstrapped.peers) {
        expect(p.isReachable, isFalse);
        expect(p.isPending, isTrue);
      }

      // Ordinary payload sends to unproven peers are refused
      final refused = await bootstrapped.sendPayload(
        'QmBootstrapNode1AlexandriaAlpha',
        Uint8List.fromList([1, 2, 3]),
      );
      expect(refused, isFalse);
      expect(
          bootstrapped.selectBestTransport('QmBootstrapNode1AlexandriaAlpha'),
          isNull);

      // A real handshake proves the peer
      const addr =
          '/dns4/node1.alexandria.network/tcp/4001/p2p/QmBootstrapNode1AlexandriaAlpha';
      final connected = await bootstrapped.connectToPeer(addr);
      expect(connected, isTrue);

      final peer = bootstrapped.peers
          .firstWhere((p) => p.peerId == 'QmBootstrapNode1AlexandriaAlpha');
      expect(peer.isReachable, isTrue);
      expect(peer.isPending, isFalse);
      expect(bootstrapped.activePeers.length, equals(1));
      expect(
          await bootstrapped.sendPayload(
              'QmBootstrapNode1AlexandriaAlpha', Uint8List.fromList([1])),
          isTrue);
    });

    test('dispose closes all broadcast streams', () async {
      mesh.dispose();
      await expectLater(mesh.onPeerDiscovered, emitsDone);
      await expectLater(mesh.onPayloadReceived, emitsDone);
      await expectLater(mesh.peerListStream, emitsDone);
    });
  });
}
