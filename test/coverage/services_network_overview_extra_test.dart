import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/models/network_models.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/mesh_transport_service.dart';
import 'package:alexandria/services/network_overview_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:alexandria/services/sync_service.dart';
import 'package:alexandria/services/tor_service.dart';
import 'package:alexandria/services/web_node_service.dart';

import '../network_test_fakes.dart';

ProviderContainer _createContainer() => ProviderContainer(
      overrides: [
        ipfsServiceProvider.overrideWith((ref) => FakeIpfsService(ref)),
        meshTransportServiceProvider.overrideWith(
          (ref) => FakeMeshTransportService(),
        ),
        webNodeServiceProvider.overrideWith((ref) => FakeWebNodeService(ref)),
        syncServiceProvider.overrideWith((ref) => FakeSyncService(ref)),
        secureStorageServiceProvider.overrideWith(
          (ref) => FakeSecureStorageService(),
        ),
        torServiceProvider.overrideWith(
          (ref) => FakeTorService(ref.read(secureStorageServiceProvider)),
        ),
      ],
    );

void main() {
  group('NetworkOverviewService coverage extras', () {
    late ProviderContainer container;
    late NetworkOverviewService service;

    setUp(() {
      container = _createContainer();
      service = container.read(networkOverviewServiceProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('watchNodeStatus reuses a stored node id from secure storage',
        () async {
      final storage = container.read(secureStorageServiceProvider)
          as FakeSecureStorageService;
      await storage.write('network_node_id', 'persisted-node-42');

      final status = await service.watchNodeStatus().first;
      expect(status.nodeId, 'persisted-node-42');
    });

    test('watchNodeStatus streams later emissions after the initial yield',
        () async {
      final statuses = <NodeStatus>[];
      final sub = service.watchNodeStatus().listen(statuses.add);
      addTearDown(sub.cancel);

      await Future<void>.delayed(Duration.zero);
      await service.startNode();

      await Future<void>.delayed(Duration.zero);
      expect(statuses.length, greaterThanOrEqualTo(2));
      expect(statuses.last.isRunning, isTrue);
    });

    test('bandwidth sampling reports deltas after the baseline', () async {
      final ipfs = container.read(ipfsServiceProvider) as FakeIpfsService;
      final web = container.read(webNodeServiceProvider) as FakeWebNodeService;
      ipfs.setStoredBytes(500);
      web.blockUsage = 250;

      // First sample establishes the baseline (returns zeros).
      final baseline = await service.watchBandwidthUsage().first;
      expect(baseline.uploadBps, 0);
      expect(baseline.downloadBps, 0);

      ipfs.setStoredBytes(800);
      web.blockUsage = 300;

      // Listen so the periodic timer keeps sampling.
      final samples = <BandwidthStats>[];
      final sub = service.watchBandwidthUsage().listen(samples.add);
      addTearDown(sub.cancel);

      // Let the 1s periodic timer fire at least once.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(samples.length, greaterThanOrEqualTo(2));
      // The immediate yield after the byte bump carries the delta;
      // subsequent periodic samples settle back to zero.
      expect(samples.first.uploadBps, 300);
      expect(samples.first.downloadBps, 50);
    });

    test('updateTransport disables IPFS and WebRTC', () async {
      final ipfs = container.read(ipfsServiceProvider) as FakeIpfsService;
      final web = container.read(webNodeServiceProvider) as FakeWebNodeService;

      await service.updateTransport(const TransportConfig(
        protocol: TransportProtocol.ipfs,
        enabled: true,
        port: 4001,
        relay: '',
      ));
      await service.updateTransport(const TransportConfig(
        protocol: TransportProtocol.webrtc,
        enabled: true,
        port: 0,
        relay: '',
      ));
      expect(ipfs.isStarted, isTrue);
      expect(web.state, WebNodeState.connected);

      await service.updateTransport(const TransportConfig(
        protocol: TransportProtocol.ipfs,
        enabled: false,
        port: 4002,
        relay: 'relay-ipfs',
      ));
      expect(ipfs.isStarted, isFalse);

      await service.updateTransport(const TransportConfig(
        protocol: TransportProtocol.webrtc,
        enabled: false,
        port: 9999,
        relay: 'relay-web',
      ));
      expect(web.state, WebNodeState.disconnected);

      final storage = container.read(secureStorageServiceProvider)
          as FakeSecureStorageService;
      expect(await storage.read('transport_webrtc_port'), '9999');
      expect(await storage.read('transport_webrtc_relay'), 'relay-web');
    });

    test('updateTransport changes tor proxy when the port differs', () async {
      final tor = container.read(torServiceProvider) as FakeTorService;
      expect(tor.proxyPort, 9050);

      await service.updateTransport(const TransportConfig(
        protocol: TransportProtocol.tor,
        enabled: true,
        port: 9150,
        relay: '127.0.0.1:9150',
      ));
      expect(tor.proxyPort, 9150);
      expect(tor.isEnabled, isTrue);

      // Same port again — setProxy is skipped, disable still runs.
      await service.updateTransport(const TransportConfig(
        protocol: TransportProtocol.tor,
        enabled: false,
        port: 9150,
        relay: '127.0.0.1:9150',
      ));
      expect(tor.isEnabled, isFalse);
    });

    test('testConnections covers ipfs-stopped and tor-enabled branches',
        () async {
      // IPFS not started → 'IPFS: stopped'.
      final stopped = await service.testConnections();
      expect(stopped, contains('IPFS: stopped'));

      final tor = container.read(torServiceProvider) as FakeTorService;
      await tor.enable();
      final result = await service.testConnections();
      // Tor enabled → a real Socket.connect attempt runs; unreachable in
      // the test sandbox, so it reports unreachable.
      expect(result, contains('Tor: proxy unreachable'));
    });

    test('watchSyncProgress emits periodically once subscribed', () async {
      final progress = <SyncProgress>[];
      final sub = service.watchSyncProgress().listen(progress.add);
      addTearDown(sub.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(progress.length, greaterThanOrEqualTo(2));
      expect(progress.last.overallProgress, 1.0);
    });

    test('watchPeers maps pending and unreachable mesh peers', () async {
      final mesh = container.read(meshTransportServiceProvider)
          as FakeMeshTransportService;
      mesh.addPeer(MeshPeer(
        peerId: 'pending-peer',
        address: '/ip4/9.9.9.9/p2p/pending',
        tier: TransportTier.webrtcDirect,
        latencyMs: 42,
        isPending: true,
      ));
      mesh.addPeer(MeshPeer(
        peerId: 'unreached-peer',
        address: '/ip4/8.8.8.8/p2p/unreached',
        tier: TransportTier.webrtcDirect,
        latencyMs: 100,
      ));

      final peers = await service.watchPeers().first;
      expect(peers, hasLength(2));
      expect(peers[0].status, PeerStatus.pending);
      expect(peers[0].latencyMs, 42);
      expect(peers[1].status, PeerStatus.disconnected);
    });
  });
}
