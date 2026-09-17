import 'dart:async';
import 'dart:io';
import 'package:dart_ipfs/dart_ipfs.dart' show IPFS, IPFSConfig, PubSubMessage;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'cid_service.dart';

/// Injectable engine factory: production wires the real dart_ipfs
/// engine; tests substitute a fake - or none, which leaves the service
/// in its honest local-only mode (local block store, no swarm).
typedef IpfsEngineFactory = Future<IPFS> Function(IPFSConfig config);

/// Builds the engine config for a resolved base directory - injectable
/// so tests can pin paths/ports without touching the real defaults.
typedef IpfsConfigBuilder = IPFSConfig Function(String baseDir);

final ipfsServiceProvider = Provider((ref) {
  // flutter_test exports FLUTTER_TEST=true. Under it the real engine
  // must never start - it would bind live sockets and try to reach the
  // public swarm - so the provider yields the honest local-only mode.
  final underTest = Platform.environment['FLUTTER_TEST'] == 'true';
  return IpfsService(ref,
      engineFactory: underTest ? null : (c) => IPFS.create(config: c));
});

class IpfsService {
  final Ref _ref;
  final IpfsEngineFactory? _engineFactory;
  final IpfsConfigBuilder? _configBuilder;
  bool _isStarted = false;
  IPFS? _node;
  final Map<String, Uint8List> _localStore = {};
  final Set<String> _pinnedCids = {};
  final StreamController<Map<String, String>> _pubsubController =
      StreamController.broadcast();
  StreamSubscription<PubSubMessage>? _pubsubSub;
  Timer? _peerCountTimer;

  /// Why the last real-engine start degraded to local-only mode - null
  /// when networked, when no factory was configured, or before the
  /// first attempt. Kept inspectable so the UI can surface "offline
  /// mode" honestly instead of a silent failure.
  String? lastStartError;

  /// Real swarm size, refreshed from the running engine every few
  /// seconds. Always 0 in local-only mode - never an estimate.
  int swarmPeerCount = 0;

  IpfsService(this._ref,
      {IpfsEngineFactory? engineFactory, IpfsConfigBuilder? configBuilder})
      : _engineFactory = engineFactory,
        _configBuilder = configBuilder;

  bool get isStarted => _isStarted;

  /// True only while the real dart_ipfs engine runs (DHT, bitswap,
  /// pubsub, swarm connections). False in local-only mode.
  bool get isNetworked => _node != null;

  /// The engine's libp2p peer id when networked; null in local mode.
  String? get nodePeerId => _node?.peerID;

  /// The engine's libp2p listen multiaddrs when networked - the
  /// addresses swarm peers can actually dial. Empty in local mode.
  List<String> get listenAddrs => _node?.addresses ?? const [];

  Stream<Map<String, String>> get pubsubStream => _pubsubController.stream;
  Set<String> get pinnedCids => _pinnedCids;

  int get storedBytes =>
      _localStore.values.fold<int>(0, (sum, data) => sum + data.length);

  Future<void> startNode() async {
    if (_isStarted) return;
    final factory = _engineFactory;
    if (factory != null) {
      try {
        final dir = await _dataDir();
        final node = await factory((_configBuilder ?? _defaultConfig)(dir));
        await node.start();
        _node = node;
        lastStartError = null;
        _attachNode(node);
        debugPrint('dart_ipfs node started (peerID ${node.peerID})');
      } catch (e) {
        // The engine could not start (sandbox, no sockets, no fs).
        // Degrade to honest local-only mode rather than crash: content
        // ops still work against the local store, and the reason stays
        // inspectable via lastStartError/isNetworked.
        _node = null;
        lastStartError = e.toString();
        debugPrint('dart_ipfs engine unavailable, local-only mode: $e');
      }
    }
    _isStarted = true;
  }

  Future<void> stopNode() async {
    _peerCountTimer?.cancel();
    _peerCountTimer = null;
    await _pubsubSub?.cancel();
    _pubsubSub = null;
    final node = _node;
    _node = null;
    swarmPeerCount = 0;
    if (node != null) {
      try {
        await node.stop();
      } catch (_) {}
    }
    _isStarted = false;
  }

  static IPFSConfig _defaultConfig(String baseDir) => IPFSConfig(
        offline: false,
        debug: false,
        verboseLogging: false,
        datastorePath: '$baseDir/datastore',
        keystorePath: '$baseDir/keystore',
        blockStorePath: '$baseDir/blocks',
        dataPath: baseDir,
      );

  Future<String> _dataDir() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return '${dir.path}/ipfs';
    } on MissingPluginException {
      // No platform channel (e.g. a test driving an injected factory):
      // a stable temp path keeps the node identity persistent per host.
      return '${Directory.systemTemp.path}/alexandria_ipfs';
    }
  }

  void _attachNode(IPFS node) {
    // Bridge real swarm pubsub into the legacy map shape callers use.
    _pubsubSub = node.pubsubMessages.listen((m) {
      if (!_pubsubController.isClosed) {
        _pubsubController
            .add({'topic': m.topic, 'data': m.content, 'sender': m.sender});
      }
    });
    _peerCountTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => unawaited(_refreshPeerCount()));
    unawaited(_refreshPeerCount());
  }

  Future<void> _refreshPeerCount() async {
    final node = _node;
    if (node == null) return;
    try {
      swarmPeerCount = (await node.connectedPeers).length;
    } catch (_) {}
  }

  /// Announces this node as a DHT provider for [cid] - the immediate
  /// counterpart to [findProviders]. Best-effort: returns false when
  /// local-only or when the announce fails, and the engine's periodic
  /// Reprovider re-announces pinned content regardless.
  Future<bool> provideCid(String cid) async {
    final node = _node;
    if (node == null) return false;
    try {
      await node.provide(cid);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Dials a swarm peer by full multiaddr at the IPFS layer - bitswap,
  /// DHT, and gossipsub connectivity independent of the ALX-MESH
  /// channel. Returns false in local mode or on dial failure; never
  /// throws.
  Future<bool> swarmConnect(String multiaddr) async {
    final node = _node;
    if (node == null) return false;
    try {
      await node.connectToPeer(multiaddr);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> addFile(Uint8List data) async {
    final node = _node;
    if (node != null) {
      try {
        // The engine's CID is canonical both locally and on the wire -
        // bitswap serves exactly what it announced.
        final cid = await node.addFile(data);
        _localStore[cid] = data;
        _pinnedCids.add(cid);
        unawaited(provideCid(cid));
        return cid;
      } catch (_) {
        // Engine add failed - fall through to the local store so the
        // caller still gets a valid locally-retrievable CID.
      }
    }
    final cid = _ref.read(cidServiceProvider).computeCid(data).toBase32();
    _localStore[cid] = data;
    _pinnedCids.add(cid);
    return cid;
  }

  /// Streams the block for [cid], or NOTHING when the block is absent
  /// (round-2 red finding): the previous implementation yielded an
  /// empty chunk for unknown CIDs, making "content missing" and
  /// "zero-byte file" indistinguishable. Callers detect absence via an
  /// empty stream (aggregate chunk count == 0).
  ///
  /// When networked, a local miss escalates to a real bitswap fetch
  /// ([IPFS.get]); a fetched block is cached locally, so this node
  /// becomes an honest provider for it thereafter.
  Stream<Uint8List> getFile(String cid) async* {
    final local = _localStore[cid];
    if (local != null) {
      yield local;
      return;
    }
    final node = _node;
    if (node != null) {
      try {
        final remote = await node.get(cid).timeout(const Duration(seconds: 30));
        if (remote != null) {
          _localStore[cid] = remote;
          // We now honestly hold the block - announce it so other
          // nodes can fetch it from us.
          unawaited(provideCid(cid));
          yield remote;
        }
      } catch (_) {
        // Absent or unreachable - yield nothing.
      }
    }
  }

  /// Pins [cid] ONLY when the identifier is structurally valid and the
  /// block is actually retrievable from this node's store (round-2 red
  /// finding): claiming a pin for an arbitrary string let preservation
  /// accounting count phantom content. When networked the pin is a real
  /// engine pin.
  Future<bool> pinCid(String cid) async {
    if (!_ref.read(cidServiceProvider).isValidCid(cid)) return false;
    if (!_localStore.containsKey(cid)) return false;
    final node = _node;
    if (node != null) {
      try {
        await node.pin(cid);
        unawaited(provideCid(cid));
      } catch (_) {
        return false;
      }
    }
    _pinnedCids.add(cid);
    return true;
  }

  Future<bool> unpinCid(String cid) async {
    final node = _node;
    if (node != null) {
      try {
        await node.unpin(cid);
      } catch (_) {}
    }
    _pinnedCids.remove(cid);
    return true;
  }

  /// Reports providers for [cid]. When networked this is a real DHT
  /// provider query; when local-only it honestly reports only this
  /// node, and only when it actually holds the block (round-2 red
  /// finding: a previous stub fabricated a `peer_dht_node_1` provider
  /// for ANY cid, which made PreservationService report nonexistent
  /// content as 'endangered' instead of 'lost').
  Future<List<String>> findProviders(String cid) async {
    final node = _node;
    if (node != null) {
      try {
        final providers =
            await node.findProviders(cid).timeout(const Duration(seconds: 20));
        final out = <String>[...providers];
        if (_localStore.containsKey(cid) && !out.contains('peer_local_self')) {
          out.add('peer_local_self');
        }
        return out;
      } catch (_) {
        // Query failed - fall through to the honest local answer.
      }
    }
    if (_localStore.containsKey(cid)) return ['peer_local_self'];
    return const [];
  }

  /// Subscribes the engine to a real gossipsub topic. No-op in
  /// local-only mode (there is no swarm to subscribe to).
  Future<void> subscribeTopic(String topic) async {
    final node = _node;
    if (node != null) await node.subscribe(topic);
  }

  Future<bool> publishToPubsub(String topic, String data) async {
    final node = _node;
    if (node != null) {
      try {
        await node.publish(topic, data);
        return true;
      } catch (_) {
        return false;
      }
    }
    _pubsubController.add({'topic': topic, 'data': data, 'sender': 'self'});
    return true;
  }

  Future<bool> runGc() async {
    _localStore.removeWhere((key, _) => !_pinnedCids.contains(key));
    return true;
  }
}
