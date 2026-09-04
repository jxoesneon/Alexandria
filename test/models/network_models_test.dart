import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/models/network_models.dart';

void main() {
  group('PeerStatus enum', () {
    test('has connected, disconnected and pending values', () {
      expect(PeerStatus.values, hasLength(3));
      expect(PeerStatus.values, contains(PeerStatus.connected));
      expect(PeerStatus.values, contains(PeerStatus.disconnected));
      expect(PeerStatus.values, contains(PeerStatus.pending));
    });
  });

  group('TransportProtocol enum', () {
    test('displayName returns human readable labels', () {
      expect(TransportProtocol.ipfs.displayName, equals('IPFS'));
      expect(TransportProtocol.webrtc.displayName, equals('WebRTC'));
      expect(TransportProtocol.tor.displayName, equals('Tor'));
    });
  });

  group('NodeStatus', () {
    test('constructor and fields', () {
      const status = NodeStatus(
        isRunning: true,
        connectedPeers: 5,
        nodeId: 'node-1',
      );
      expect(status.isRunning, isTrue);
      expect(status.connectedPeers, equals(5));
      expect(status.nodeId, equals('node-1'));
    });

    test('default nodeId is empty', () {
      const status = NodeStatus(isRunning: false, connectedPeers: 0);
      expect(status.nodeId, isEmpty);
    });

    test('copyWith updates values and keeps unchanged fields', () {
      const status = NodeStatus(
        isRunning: false,
        connectedPeers: 1,
        nodeId: 'id',
      );
      final updated = status.copyWith(connectedPeers: 10);
      expect(updated.isRunning, isFalse);
      expect(updated.connectedPeers, equals(10));
      expect(updated.nodeId, equals('id'));
    });

    test('toString output', () {
      const status = NodeStatus(
        isRunning: true,
        connectedPeers: 3,
        nodeId: 'abc',
      );
      expect(
        status.toString(),
        equals('NodeStatus(isRunning: true, connectedPeers: 3, nodeId: abc)'),
      );
    });
  });

  group('BandwidthStats', () {
    test('constructor and fields', () {
      final now = DateTime.now();
      final stats = BandwidthStats(
        uploadBps: 100,
        downloadBps: 200,
        timestamp: now,
      );
      expect(stats.uploadBps, equals(100));
      expect(stats.downloadBps, equals(200));
      expect(stats.timestamp, equals(now));
    });

    test('copyWith', () {
      final stats = BandwidthStats(
        uploadBps: 1,
        downloadBps: 2,
        timestamp: DateTime(2024),
      );
      final updated = stats.copyWith(uploadBps: 99);
      expect(updated.uploadBps, equals(99));
      expect(updated.downloadBps, equals(2));
      expect(updated.timestamp, equals(stats.timestamp));
    });
  });

  group('Peer', () {
    test('constructor and fields', () {
      const peer = Peer(
        peerId: 'p1',
        multiaddr: '/ip4/1.2.3.4',
        latencyMs: 12,
        status: PeerStatus.connected,
      );
      expect(peer.peerId, equals('p1'));
      expect(peer.multiaddr, equals('/ip4/1.2.3.4'));
      expect(peer.latencyMs, equals(12));
      expect(peer.status, equals(PeerStatus.connected));
    });

    test('copyWith', () {
      const peer = Peer(
        peerId: 'p1',
        multiaddr: '/ip4/1.2.3.4',
        latencyMs: 12,
        status: PeerStatus.connected,
      );
      final updated = peer.copyWith(latencyMs: 50, status: PeerStatus.pending);
      expect(updated.peerId, equals('p1'));
      expect(updated.multiaddr, equals('/ip4/1.2.3.4'));
      expect(updated.latencyMs, equals(50));
      expect(updated.status, equals(PeerStatus.pending));
    });
  });

  group('TransportConfig', () {
    test('constructor and fields', () {
      const config = TransportConfig(
        protocol: TransportProtocol.webrtc,
        enabled: true,
        port: 1234,
      );
      expect(config.protocol, equals(TransportProtocol.webrtc));
      expect(config.enabled, isTrue);
      expect(config.port, equals(1234));
      expect(config.relay, isEmpty);
    });

    test('default relay is empty', () {
      const config = TransportConfig(
        protocol: TransportProtocol.tor,
        enabled: false,
        port: 0,
      );
      expect(config.relay, isEmpty);
    });

    test('copyWith', () {
      const config = TransportConfig(
        protocol: TransportProtocol.ipfs,
        enabled: false,
        port: 4001,
        relay: '',
      );
      final updated = config.copyWith(enabled: true, port: 5001);
      expect(updated.protocol, equals(TransportProtocol.ipfs));
      expect(updated.enabled, isTrue);
      expect(updated.port, equals(5001));
    });
  });

  group('Transfer', () {
    test('constructor and fields', () {
      const transfer = Transfer(
        name: 'file',
        bytesTransferred: 512,
        totalBytes: 1024,
      );
      expect(transfer.name, equals('file'));
      expect(transfer.bytesTransferred, equals(512));
      expect(transfer.totalBytes, equals(1024));
    });

    test('progress helper', () {
      const half = Transfer(
        name: 'x',
        bytesTransferred: 1,
        totalBytes: 2,
      );
      expect(half.progress, closeTo(0.5, 0.0001));
    });

    test('progress is zero when total is zero', () {
      const empty = Transfer(
        name: 'x',
        bytesTransferred: 0,
        totalBytes: 0,
      );
      expect(empty.progress, equals(0.0));
    });

    test('copyWith', () {
      const transfer = Transfer(
        name: 'file',
        bytesTransferred: 100,
        totalBytes: 1000,
      );
      final updated = transfer.copyWith(bytesTransferred: 500);
      expect(updated.name, equals('file'));
      expect(updated.bytesTransferred, equals(500));
      expect(updated.totalBytes, equals(1000));
    });
  });

  group('Conflict', () {
    test('constructor and fields', () {
      final now = DateTime.now();
      final conflict = Conflict(
        id: 'c1',
        documentName: 'doc',
        localVersion: 'v1',
        remoteVersion: 'v2',
        timestamp: now,
      );
      expect(conflict.id, equals('c1'));
      expect(conflict.documentName, equals('doc'));
      expect(conflict.localVersion, equals('v1'));
      expect(conflict.remoteVersion, equals('v2'));
      expect(conflict.timestamp, equals(now));
    });

    test('copyWith', () {
      final conflict = Conflict(
        id: 'c1',
        documentName: 'doc',
        localVersion: 'v1',
        remoteVersion: 'v2',
        timestamp: DateTime(2024),
      );
      final updated = conflict.copyWith(remoteVersion: 'v3');
      expect(updated.id, equals('c1'));
      expect(updated.remoteVersion, equals('v3'));
      expect(updated.timestamp, equals(conflict.timestamp));
    });
  });

  group('Resolution', () {
    test('constructor with default success', () {
      const res = Resolution(id: 'r1');
      expect(res.id, equals('r1'));
      expect(res.success, isTrue);
    });

    test('constructor with explicit success', () {
      const res = Resolution(id: 'r2', success: false);
      expect(res.success, isFalse);
    });

    test('copyWith', () {
      const res = Resolution(id: 'r1');
      final updated = res.copyWith(success: false);
      expect(updated.id, equals('r1'));
      expect(updated.success, isFalse);
    });
  });

  group('SyncProgress', () {
    test('constructor and default inProgress', () {
      const progress = SyncProgress(
        overallProgress: 0.5,
        activeTransfers: [],
        pendingConflicts: [],
      );
      expect(progress.overallProgress, equals(0.5));
      expect(progress.activeTransfers, isEmpty);
      expect(progress.pendingConflicts, isEmpty);
      expect(progress.inProgress, isFalse);
    });

    test('copyWith preserves lists', () {
      const progress = SyncProgress(
        overallProgress: 0.0,
        activeTransfers: [],
        pendingConflicts: [],
      );
      const transfers = [
        Transfer(
          name: 't',
          bytesTransferred: 0,
          totalBytes: 1,
        )
      ];
      final conflicts = [
        Conflict(
          id: 'c',
          documentName: 'd',
          localVersion: 'l',
          remoteVersion: 'r',
          timestamp: DateTime(2025),
        )
      ];
      final updated = progress.copyWith(
        overallProgress: 1.0,
        activeTransfers: transfers,
        pendingConflicts: conflicts,
        inProgress: true,
      );
      expect(updated.overallProgress, equals(1.0));
      expect(updated.activeTransfers, equals(transfers));
      expect(updated.pendingConflicts, equals(conflicts));
      expect(updated.inProgress, isTrue);
    });
  });
}
