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
  group('NetworkOverviewService', () {
    late ProviderContainer container;
    late NetworkOverviewService service;

    setUp(() {
      container = _createContainer();
      service = container.read(networkOverviewServiceProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('watchNodeStatus emits a status with a generated nodeId', () async {
      final status = await service.watchNodeStatus().first;
      expect(status, isA<NodeStatus>());
      expect(status.nodeId, isNotEmpty);
    });

    test('startNode and stopNode toggle ipfs state', () async {
      final ipfs = container.read(ipfsServiceProvider) as FakeIpfsService;

      expect(ipfs.isStarted, isFalse);
      await service.startNode();
      expect(ipfs.isStarted, isTrue);

      final status = await service.watchNodeStatus().first;
      expect(status.isRunning, isTrue);

      await service.stopNode();
      expect(ipfs.isStarted, isFalse);
    });

    test('watchBandwidthUsage emits an initial sample', () async {
      final stats = await service.watchBandwidthUsage().first;
      expect(stats, isA<BandwidthStats>());
    });

    test('watchPeers maps mesh peers to Peer list', () async {
      final mesh = container.read(meshTransportServiceProvider)
          as FakeMeshTransportService;
      mesh.addPeer(
        MeshPeer(
          peerId: 'peer-1',
          address: '/ip4/1.2.3.4/p2p/peer-1',
          tier: TransportTier.lanMdns,
          latencyMs: 5,
          // Round-3: isReachable defaults to false (proof, not a flag) -
          // the fake inserts directly, so declare the handshake-proven
          // state it is simulating.
          isReachable: true,
        ),
      );

      final peers = await service.watchPeers().first;
      expect(peers, hasLength(1));
      expect(peers.first.peerId, equals('peer-1'));
      expect(peers.first.status, equals(PeerStatus.connected));
    });

    test('getTransports returns the three default transports', () async {
      final transports = await service.getTransports();
      expect(transports, hasLength(3));
      expect(
        transports.map((t) => t.protocol).toList(),
        equals([
          TransportProtocol.ipfs,
          TransportProtocol.webrtc,
          TransportProtocol.tor
        ]),
      );
      expect(transports.first.port, equals(4001));
    });

    test('updateTransport enables IPFS when asked', () async {
      final ipfs = container.read(ipfsServiceProvider) as FakeIpfsService;
      const config = TransportConfig(
        protocol: TransportProtocol.ipfs,
        enabled: true,
        port: 4001,
        relay: '',
      );

      await service.updateTransport(config);
      expect(ipfs.isStarted, isTrue);
      final storage = container.read(secureStorageServiceProvider)
          as FakeSecureStorageService;
      expect(await storage.read('transport_ipfs_port'), equals('4001'));
    });

    test('testConnections reports IPFS ok and Tor disabled', () async {
      await service.startNode();
      final result = await service.testConnections();
      expect(result, contains('IPFS: ok'));
      expect(result, contains('WebRTC: disconnected'));
      expect(result, contains('Tor: disabled'));
    });

    test('addConflict and resolveConflict update sync progress', () async {
      final conflict = Conflict(
        id: 'c1',
        documentName: 'doc',
        localVersion: 'v1',
        remoteVersion: 'v2',
        timestamp: DateTime(2024),
      );

      service.addConflict(conflict);
      final progress1 = await service.watchSyncProgress().first;
      expect(progress1.pendingConflicts, hasLength(1));

      final resolved = await service.resolveConflict(conflict);
      expect(resolved, isTrue);

      final progress2 = await service.watchSyncProgress().first;
      expect(progress2.pendingConflicts, isEmpty);
    });

    test('triggerManualSync completes', () async {
      final sync = container.read(syncServiceProvider) as FakeSyncService;
      sync.enqueue(
        QueuedOperation(
          id: 'op-1',
          collectionId: 'col',
          operation: 'put',
          data: {'x': 1},
          timestamp: DateTime(2024),
        ),
      );

      await service.triggerManualSync();
      final progress = await service.watchSyncProgress().first;
      expect(progress, isA<SyncProgress>());
      expect(progress.inProgress, isFalse);
    });

    test('updateTransport toggles webrtc and tor', () async {
      final web = container.read(webNodeServiceProvider) as FakeWebNodeService;
      final tor = container.read(torServiceProvider) as FakeTorService;

      const webrtc = TransportConfig(
        protocol: TransportProtocol.webrtc,
        enabled: true,
        port: 8080,
        relay: '',
      );
      await service.updateTransport(webrtc);
      expect(web.state, equals(WebNodeState.connected));

      const torConfig = TransportConfig(
        protocol: TransportProtocol.tor,
        enabled: true,
        port: 9051,
        relay: '127.0.0.1:9051',
      );
      await service.updateTransport(torConfig);
      expect(tor.isEnabled, isTrue);
      expect(tor.proxyPort, equals(9051));
    });
  });

  group('CrdtService', () {
    late ProviderContainer container;
    late NetworkOverviewService service;
    late CrdtService crdt;

    setUp(() {
      container = _createContainer();
      service = container.read(networkOverviewServiceProvider);
      crdt = CrdtService(service);
    });

    tearDown(() {
      container.dispose();
    });

    test('resolveMergeConflict returns Resolution on success', () async {
      final conflict = Conflict(
        id: 'c1',
        documentName: 'doc',
        localVersion: 'v1',
        remoteVersion: 'v2',
        timestamp: DateTime(2024),
      );

      service.addConflict(conflict);
      final resolution = await crdt.resolveMergeConflict(conflict);
      expect(resolution.id, equals('c1'));
      expect(resolution.success, isTrue);
    });
  });
}
