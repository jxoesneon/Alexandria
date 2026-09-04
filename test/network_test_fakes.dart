import 'dart:async';

import 'package:alexandria/models/network_models.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/mesh_transport_service.dart';
import 'package:alexandria/services/web_node_service.dart';
import 'package:alexandria/services/sync_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:alexandria/services/tor_service.dart';
import 'package:alexandria/services/network_overview_service.dart';

class FakeSecureStorageService extends SecureStorageService {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> deleteAll() async => _data.clear();

  @override
  Future<bool> containsKey(String key) async => _data.containsKey(key);
}

class FakeIpfsService extends IpfsService {
  FakeIpfsService(super.ref);

  bool _started = false;
  int _storedBytes = 0;

  @override
  bool get isStarted => _started;

  @override
  int get storedBytes => _storedBytes;

  @override
  Future<void> startNode() async => _started = true;

  @override
  Future<void> stopNode() async => _started = false;

  @override
  Future<bool> publishToPubsub(String topic, String data) async => true;

  void setStoredBytes(int bytes) => _storedBytes = bytes;
}

class _FakeBlockStore extends IndexedDbBlockStore {
  int _usage = 0;

  @override
  int get currentUsage => _usage;

  set currentUsage(int value) => _usage = value;
}

class FakeWebNodeService extends WebNodeService {
  FakeWebNodeService(super.ref);

  WebNodeState _state = WebNodeState.uninitialized;
  final List<String> _connectedPeers = [];
  final _FakeBlockStore _blockStore = _FakeBlockStore();

  @override
  WebNodeState get state => _state;

  @override
  List<String> get connectedPeers => _connectedPeers;

  @override
  IndexedDbBlockStore get blockStore => _blockStore;

  @override
  Future<void> initializeWebNode() async {
    _state = WebNodeState.connected;
    _connectedPeers.add('web-peer');
  }

  @override
  Future<void> terminate() async {
    _state = WebNodeState.disconnected;
    _connectedPeers.clear();
  }

  set blockUsage(int value) => _blockStore.currentUsage = value;
}

class FakeMeshTransportService extends MeshTransportService {
  final List<MeshPeer> _peers = [];
  final _peerListController = StreamController<List<MeshPeer>>.broadcast();

  @override
  List<MeshPeer> get activePeers => _peers.where((p) => p.isReachable).toList();

  @override
  List<MeshPeer> get peers => List.unmodifiable(_peers);

  @override
  Stream<List<MeshPeer>> watchPeers() async* {
    yield peers;
    yield* _peerListController.stream;
  }

  void addPeer(MeshPeer peer) {
    _peers.add(peer);
    _peerListController.add(peers);
  }

  @override
  void dispose() {
    _peerListController.close();
    super.dispose();
  }
}

class FakeSyncService extends SyncService {
  FakeSyncService(super.ref);

  final List<QueuedOperation> _queue = [];

  @override
  List<QueuedOperation> get offlineQueue => List.unmodifiable(_queue);

  @override
  Future<void> processQueue() async => _queue.clear();

  void enqueue(QueuedOperation op) => _queue.add(op);
}

class FakeTorService extends TorService {
  FakeTorService(super.storage);

  bool _enabled = false;
  String _proxyAddress = '127.0.0.1:9050';
  int _proxyPort = 9050;

  @override
  TorStatus get status => _enabled ? TorStatus.connected : TorStatus.disabled;

  @override
  bool get isEnabled => _enabled;

  @override
  String get proxyAddress => _proxyAddress;

  @override
  int get proxyPort => _proxyPort;

  @override
  Future<bool> enable() async {
    _enabled = true;
    return true;
  }

  @override
  Future<void> disable() async => _enabled = false;

  @override
  Future<void> setProxy(String host, int port) async {
    _proxyAddress = '$host:$port';
    _proxyPort = port;
  }
}

class FakeNetworkOverviewService extends NetworkOverviewService {
  FakeNetworkOverviewService(super.ref);

  final _nodeController = StreamController<NodeStatus>.broadcast();
  final _bandwidthController = StreamController<BandwidthStats>.broadcast();
  final _peersController = StreamController<List<Peer>>.broadcast();
  final _syncController = StreamController<SyncProgress>.broadcast();
  final _transports = <TransportConfig>[
    const TransportConfig(
      protocol: TransportProtocol.ipfs,
      enabled: true,
      port: 4001,
      relay: '',
    ),
    const TransportConfig(
      protocol: TransportProtocol.webrtc,
      enabled: false,
      port: 0,
      relay: '',
    ),
    const TransportConfig(
      protocol: TransportProtocol.tor,
      enabled: false,
      port: 9050,
      relay: '',
    ),
  ];

  @override
  Stream<NodeStatus> watchNodeStatus() async* {
    yield const NodeStatus(
        isRunning: true, connectedPeers: 0, nodeId: 'node-1');
    yield* _nodeController.stream;
  }

  @override
  Stream<BandwidthStats> watchBandwidthUsage() async* {
    yield BandwidthStats(
      uploadBps: 10,
      downloadBps: 20,
      timestamp: DateTime(2024, 1, 1),
    );
    yield* _bandwidthController.stream;
  }

  @override
  Stream<List<Peer>> watchPeers() async* {
    yield const <Peer>[];
    yield* _peersController.stream;
  }

  @override
  Future<List<TransportConfig>> getTransports() async => _transports;

  @override
  Stream<SyncProgress> watchSyncProgress() async* {
    yield const SyncProgress(
      overallProgress: 0.0,
      activeTransfers: <Transfer>[],
      pendingConflicts: <Conflict>[],
      inProgress: false,
    );
    yield* _syncController.stream;
  }

  @override
  Future<void> startNode() async => _nodeController.add(
        const NodeStatus(isRunning: true, connectedPeers: 0, nodeId: 'node-1'),
      );

  @override
  Future<void> stopNode() async => _nodeController.add(
        const NodeStatus(isRunning: false, connectedPeers: 0, nodeId: 'node-1'),
      );

  @override
  Future<void> updateTransport(TransportConfig config) async {
    final index = _transports.indexWhere(
      (t) => t.protocol == config.protocol,
    );
    if (index >= 0) _transports[index] = config;
  }

  @override
  Future<String> testConnections() async => 'fake';

  @override
  Future<void> triggerManualSync() async {}

  @override
  void dispose() {
    _nodeController.close();
    _bandwidthController.close();
    _peersController.close();
    _syncController.close();
    super.dispose();
  }
}
