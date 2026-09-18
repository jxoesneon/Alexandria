import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../app_network.dart';
import '../models/network_models.dart';
import 'ipfs_service.dart';
import 'mesh_transport_service.dart';
import 'rendezvous_service.dart';
import 'secure_storage_service.dart';
import 'sync_service.dart';
import 'tor_service.dart';
import 'web_node_service.dart';

final networkOverviewServiceProvider = Provider<NetworkOverviewService>((ref) {
  final service = NetworkOverviewService(ref);
  ref.onDispose(service.dispose);
  return service;
});

class NetworkOverviewService {
  NetworkOverviewService(this._ref);

  final Ref _ref;

  // Node status
  String? _nodeId;
  final _nodeStatusController = StreamController<NodeStatus>.broadcast();

  // Bandwidth telemetry
  final _bandwidthController = StreamController<BandwidthStats>.broadcast();
  Timer? _bandwidthTimer;
  bool _bandwidthStarted = false;
  int _prevIpfsBytes = 0;
  int _prevWebNodeBytes = 0;

  // Sync progress
  final _syncProgressController = StreamController<SyncProgress>.broadcast();
  Timer? _syncTimer;
  final List<Conflict> _pendingConflicts = <Conflict>[];
  bool _manualSyncInProgress = false;
  int _manualSyncTotal = 0;

  void dispose() {
    _meshRetryTimer?.cancel();
    _nodeStatusController.close();
    _bandwidthController.close();
    _syncProgressController.close();
    _bandwidthTimer?.cancel();
    _syncTimer?.cancel();
  }

  // --- Node status ---

  Future<String> _ensureNodeId() async {
    if (_nodeId != null && _nodeId!.isNotEmpty) return _nodeId!;
    final storage = _ref.read(secureStorageServiceProvider);
    final stored = await storage.read('network_node_id');
    if (stored != null && stored.isNotEmpty) {
      _nodeId = stored;
    } else {
      _nodeId = const Uuid().v4();
      await storage.write('network_node_id', _nodeId!);
    }
    return _nodeId!;
  }

  NodeStatus _buildNodeStatus() {
    final ipfs = _ref.read(ipfsServiceProvider);
    final mesh = _ref.read(meshTransportServiceProvider);
    final web = _ref.read(webNodeServiceProvider);
    final connectedPeers = mesh.activePeers.length +
        web.connectedPeers.length +
        ipfs.swarmPeerCount;
    return NodeStatus(
      isRunning: ipfs.isStarted,
      connectedPeers: connectedPeers,
      nodeId: _nodeId ?? '',
    );
  }

  void _emitNodeStatus() {
    if (!_nodeStatusController.isClosed) {
      _nodeStatusController.add(_buildNodeStatus());
    }
  }

  Stream<NodeStatus> watchNodeStatus() async* {
    await _ensureNodeId();
    yield _buildNodeStatus();
    yield* _nodeStatusController.stream;
  }

  Future<void> startNode() async {
    final ipfs = _ref.read(ipfsServiceProvider);
    final mesh = _ref.read(meshTransportServiceProvider);
    await ipfs.startNode();
    // Outbound dials need no identity - bootstrap candidates and
    // registered peers are dialed anonymously (responder-authenticated)
    // right away.
    unawaited(mesh.dialPending());
    await _ensureListenerAndRendezvous();
    _emitNodeStatus();
  }

  // The inbound listener and rendezvous announce need a local identity
  // to sign with. On first run none exists until onboarding creates
  // one - so retry on a bounded cadence rather than leaving the node
  // permanently outbound-only until restart.
  Timer? _meshRetryTimer;
  int _meshRetries = 0;
  static const int _maxMeshRetries = 45; // ~15 min at 20s cadence

  Future<void> _ensureListenerAndRendezvous() async {
    final mesh = _ref.read(meshTransportServiceProvider);
    try {
      if (!mesh.isListening) await mesh.startListening();
    } catch (_) {
      // Bind failure - stays outbound-only; isListening reports truth.
    }
    if (mesh.isListening) {
      _meshRetryTimer?.cancel();
      unawaited(_ref.read(rendezvousServiceProvider).start());
      return;
    }
    if (_meshRetries++ < _maxMeshRetries) {
      _meshRetryTimer?.cancel();
      _meshRetryTimer = Timer(const Duration(seconds: 20),
          () => unawaited(_ensureListenerAndRendezvous()));
    }
  }

  Future<void> stopNode() async {
    final ipfs = _ref.read(ipfsServiceProvider);
    final mesh = _ref.read(meshTransportServiceProvider);
    _meshRetryTimer?.cancel();
    await _ref.read(rendezvousServiceProvider).stop();
    await mesh.stopListening();
    await ipfs.stopNode();
    _emitNodeStatus();
  }

  // --- Bandwidth telemetry ---

  Stream<BandwidthStats> watchBandwidthUsage() async* {
    _startBandwidthTimer();
    yield _sampleBandwidth();
    yield* _bandwidthController.stream;
  }

  void _startBandwidthTimer() {
    if (_bandwidthStarted) return;
    _bandwidthStarted = true;
    _sampleBandwidth(); // establish baseline
    _bandwidthTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_bandwidthController.isClosed) {
        _bandwidthController.add(_sampleBandwidth());
      }
    });
  }

  BandwidthStats _sampleBandwidth() {
    final ipfs = _ref.read(ipfsServiceProvider);
    final web = _ref.read(webNodeServiceProvider);
    final ipfsBytes = ipfs.storedBytes;
    final webBytes = web.blockStore.currentUsage;

    if (_prevIpfsBytes == 0 && _prevWebNodeBytes == 0) {
      _prevIpfsBytes = ipfsBytes;
      _prevWebNodeBytes = webBytes;
      return BandwidthStats(
        uploadBps: 0,
        downloadBps: 0,
        timestamp: DateTime.now(),
      );
    }

    final uploadDelta = (ipfsBytes - _prevIpfsBytes).clamp(0, ipfsBytes);
    final downloadDelta = (webBytes - _prevWebNodeBytes).clamp(0, webBytes);
    _prevIpfsBytes = ipfsBytes;
    _prevWebNodeBytes = webBytes;

    return BandwidthStats(
      uploadBps: uploadDelta,
      downloadBps: downloadDelta,
      timestamp: DateTime.now(),
    );
  }

  // --- Peer discovery ---

  Stream<List<Peer>> watchPeers() {
    final mesh = _ref.read(meshTransportServiceProvider);
    return mesh.watchPeers().map((meshPeers) {
      return meshPeers.map(_mapMeshPeer).toList();
    });
  }

  static Peer _mapMeshPeer(MeshPeer mesh) {
    final pending = mesh.isPending;
    final status = pending
        ? PeerStatus.pending
        : (mesh.isReachable ? PeerStatus.connected : PeerStatus.disconnected);
    return Peer(
      peerId: mesh.peerId,
      multiaddr: mesh.address,
      latencyMs: mesh.latencyMs,
      status: status,
    );
  }

  // --- Transport configuration ---

  Future<List<TransportConfig>> getTransports() async {
    final ipfs = _ref.read(ipfsServiceProvider);
    final web = _ref.read(webNodeServiceProvider);
    final tor = _ref.read(torServiceProvider);
    final storage = _ref.read(secureStorageServiceProvider);

    final ipfsPort =
        int.tryParse(await storage.read('transport_ipfs_port') ?? '') ?? 4001;
    final ipfsRelay = await storage.read('transport_ipfs_relay') ?? '';

    final webrtcPort =
        int.tryParse(await storage.read('transport_webrtc_port') ?? '') ?? 0;
    final webrtcRelay = await storage.read('transport_webrtc_relay') ?? '';

    final torPort =
        int.tryParse(await storage.read('transport_tor_port') ?? '') ??
            tor.proxyPort;
    final torRelay =
        await storage.read('transport_tor_relay') ?? tor.proxyAddress;

    return [
      TransportConfig(
        protocol: TransportProtocol.ipfs,
        enabled: ipfs.isStarted,
        port: ipfsPort,
        relay: ipfsRelay,
      ),
      TransportConfig(
        protocol: TransportProtocol.webrtc,
        enabled: web.state == WebNodeState.connected,
        port: webrtcPort,
        relay: webrtcRelay,
      ),
      TransportConfig(
        protocol: TransportProtocol.tor,
        enabled: tor.isEnabled,
        port: torPort,
        relay: torRelay,
      ),
    ];
  }

  Future<void> updateTransport(TransportConfig config) async {
    final ipfs = _ref.read(ipfsServiceProvider);
    final web = _ref.read(webNodeServiceProvider);
    final tor = _ref.read(torServiceProvider);
    final storage = _ref.read(secureStorageServiceProvider);

    switch (config.protocol) {
      case TransportProtocol.ipfs:
        if (config.enabled && !ipfs.isStarted) {
          await ipfs.startNode();
        } else if (!config.enabled && ipfs.isStarted) {
          await ipfs.stopNode();
        }
        await storage.write('transport_ipfs_port', config.port.toString());
        await storage.write('transport_ipfs_relay', config.relay);
        _emitNodeStatus();
        return;
      case TransportProtocol.webrtc:
        if (config.enabled && web.state != WebNodeState.connected) {
          await web.initializeWebNode();
        } else if (!config.enabled && web.state == WebNodeState.connected) {
          await web.terminate();
        }
        await storage.write('transport_webrtc_port', config.port.toString());
        await storage.write('transport_webrtc_relay', config.relay);
        return;
      case TransportProtocol.tor:
        if (config.port != tor.proxyPort) {
          await tor.setProxy(_parseHost(config.relay), config.port);
        }
        if (config.enabled && !tor.isEnabled) {
          await tor.enable();
        } else if (!config.enabled && tor.isEnabled) {
          await tor.disable();
        }
        await storage.write('transport_tor_port', config.port.toString());
        await storage.write('transport_tor_relay', config.relay);
        return;
    }
  }

  /// (round-6 red finding) Parses a relay address into the host half.
  /// Handles `host`, `host:port`, bracketed IPv6 `[::1]` / `[::1]:9050`,
  /// and bare IPv6 literals (`::1`, returned bracketed to match
  /// [TorService.setProxy]'s host grammar). The previous `split(':')`
  /// returned `'['` for `'[::1]:9050'`. Malformed input fails closed to
  /// the loopback default rather than feeding a garbage host to
  /// setProxy/Socket.connect.
  String _parseHost(String address) {
    final a = address.trim();
    if (a.isEmpty) return '127.0.0.1';
    if (a.startsWith('[')) {
      // Bracketed IPv6: [::1] or [::1]:port - anything after ']'
      // must be a numeric port or absent.
      final close = a.indexOf(']');
      if (close <= 1) return '127.0.0.1';
      final rest = a.substring(close + 1);
      if (rest.isNotEmpty && !RegExp(r'^:\d{1,5}$').hasMatch(rest)) {
        return '127.0.0.1';
      }
      return a.substring(0, close + 1);
    }
    final firstColon = a.indexOf(':');
    if (firstColon < 0) return a; // bare host
    if (a.indexOf(':', firstColon + 1) < 0) {
      // host:port - the port must be numeric to be a real port.
      final host = a.substring(0, firstColon);
      final port = a.substring(firstColon + 1);
      if (host.isEmpty || int.tryParse(port) == null) return '127.0.0.1';
      return host;
    }
    // Multiple colons: an unbracketed IPv6 literal carries no port -
    // return it bracketed so setProxy's grammar accepts it.
    if (RegExp(r'^[0-9a-fA-F:]+$').hasMatch(a)) return '[$a]';
    return '127.0.0.1';
  }

  Future<String> testConnections() async {
    final ipfs = _ref.read(ipfsServiceProvider);
    final web = _ref.read(webNodeServiceProvider);
    final tor = _ref.read(torServiceProvider);
    final results = <String>[];

    if (ipfs.isStarted) {
      final ok = await ipfs.publishToPubsub(
          AppNetwork.testnet ? 'network_test_testnet' : 'network_test', 'ping');
      results.add('IPFS: ${ok ? 'ok' : 'failed'}');
    } else {
      results.add('IPFS: stopped');
    }

    results.add(
      'WebRTC: ${web.state == WebNodeState.connected ? 'connected' : 'disconnected'}',
    );

    if (tor.isEnabled) {
      // (round-5 red finding) use the structured accessors - splitting
      // the 'host:port' display string on ':' mangles bracketed IPv6
      // ('[::1]:9050'.split(':')[0] == '[').
      final host = tor.proxyHost;
      final port = tor.proxyPort;
      try {
        final socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(seconds: 2),
        );
        await socket.close();
        results.add('Tor: proxy reachable');
      } catch (_) {
        results.add('Tor: proxy unreachable');
      }
    } else {
      results.add('Tor: disabled');
    }

    return results.join(' • ');
  }

  // --- Sync & conflict resolution ---

  Stream<SyncProgress> watchSyncProgress() async* {
    _startSyncTimer();
    yield _buildSyncProgress();
    yield* _syncProgressController.stream;
  }

  void _startSyncTimer() {
    if (_syncTimer != null && _syncTimer!.isActive) return;
    _syncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _emitSyncProgress();
    });
  }

  Future<void> triggerManualSync() async {
    final sync = _ref.read(syncServiceProvider);
    final initial = List<QueuedOperation>.from(sync.offlineQueue);

    _manualSyncInProgress = true;
    _manualSyncTotal = initial.length;
    _emitSyncProgress();

    // (slot-C sweep) a throwing processQueue must not wedge the
    // progress state - without the finally, inProgress would stay
    // latched true forever after a transport error.
    try {
      await sync.processQueue();
    } finally {
      _manualSyncInProgress = false;
      _emitSyncProgress();
    }
  }

  Future<bool> resolveConflict(Conflict conflict) async {
    final before = _pendingConflicts.length;
    _pendingConflicts.removeWhere((c) => c.id == conflict.id);
    _emitSyncProgress();
    return _pendingConflicts.length < before;
  }

  void addConflict(Conflict conflict) {
    _pendingConflicts.add(conflict);
    _emitSyncProgress();
  }

  SyncProgress _buildSyncProgress() {
    final sync = _ref.read(syncServiceProvider);
    final active = _manualSyncInProgress
        ? sync.offlineQueue.map(_operationToTransfer).toList()
        : sync.offlineQueue.map(_operationToTransfer).toList();

    final total = _manualSyncTotal;
    final remaining = _manualSyncInProgress ? active.length : active.length;
    final progress = _manualSyncInProgress
        ? (total > 0 ? (total - remaining) / total : 0.0)
        : (active.isEmpty ? 1.0 : 0.0);

    return SyncProgress(
      overallProgress: progress.clamp(0.0, 1.0),
      activeTransfers: active,
      pendingConflicts: List.unmodifiable(_pendingConflicts),
      inProgress: _manualSyncInProgress,
    );
  }

  Transfer _operationToTransfer(QueuedOperation op) {
    final totalBytes = _estimateBytes(op.data);
    return Transfer(
      name: '${op.collectionId}:${op.operation}',
      bytesTransferred: 0,
      totalBytes: totalBytes,
    );
  }

  int _estimateBytes(Map<String, dynamic> data) {
    try {
      return data.toString().length;
    } catch (_) {
      return 0;
    }
  }

  void _emitSyncProgress() {
    if (!_syncProgressController.isClosed) {
      _syncProgressController.add(_buildSyncProgress());
    }
  }
}

class CrdtService {
  CrdtService(this._networkOverviewService);

  final NetworkOverviewService _networkOverviewService;

  Future<Resolution> resolveMergeConflict(Conflict conflict) async {
    final success = await _networkOverviewService.resolveConflict(conflict);
    return Resolution(id: conflict.id, success: success);
  }
}
