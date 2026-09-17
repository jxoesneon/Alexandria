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

/// Awaits the disk-block scan before reporting stored bytes - a sync
/// read at startup would report 0 B while persisted blocks still scan.
final storedBytesProvider = FutureProvider.autoDispose<int>((ref) async {
  final ipfs = ref.watch(ipfsServiceProvider);
  await ipfs.ensureBlocksReady();
  return ipfs.storedBytes;
});

class IpfsService {
  final Ref _ref;
  final IpfsEngineFactory? _engineFactory;
  final IpfsConfigBuilder? _configBuilder;
  bool _isStarted = false;
  IPFS? _node;
  final String? _localStoreDirOverride;
  final String? _engineBlocksDirOverride;
  late final bool _persistLocal;
  final Map<String, Uint8List> _localStore = {};
  final Set<String> _pinnedCids = {};
  // Disk-persisted block sizes, keyed by CID (the filename). Tracked so
  // storedBytes reflects blocks that survive restarts - the in-memory
  // map alone reported 0 B for a populated local store.
  final Map<String, int> _diskBlockBytes = {};
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
      {IpfsEngineFactory? engineFactory,
      IpfsConfigBuilder? configBuilder,
      String? localStoreDir,
      String? engineBlocksDir})
      : _engineFactory = engineFactory,
        _configBuilder = configBuilder,
        _localStoreDirOverride = localStoreDir,
        _engineBlocksDirOverride = engineBlocksDir {
    // Disk persistence is production behavior. Under FLUTTER_TEST the
    // zone is FakeAsync: real file I/O awaited from a test body
    // deadlocks (its continuations queue on fake microtasks that only
    // flush during pump), and tests would otherwise share a real
    // ~/.local/share blocks dir across runs. Tests that exercise the
    // durable store opt in explicitly via localStoreDir.
    _persistLocal =
        localStoreDir != null || Platform.environment['FLUTTER_TEST'] != 'true';
  }

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

  /// Completes once the on-disk block store has been scanned - `.pins`
  /// loaded into [pinnedCids] and disk block sizes into [storedBytes].
  /// Consumers reading either at startup must await this or they see
  /// the stale pre-scan empty state. A no-op when disk persistence is
  /// off (in-memory-only mode has nothing to await - and under
  /// FLUTTER_TEST the real file I/O would deadlock the fake zone).
  Future<void> ensureBlocksReady() async {
    if (_persistLocal) await _blocksDir();
  }

  /// Bytes this node holds: the in-memory store plus the on-disk block
  /// cache, deduplicated by CID so a block present in both counts once.
  int get storedBytes {
    var total = 0;
    final seen = <String>{};
    for (final entry in _localStore.entries) {
      if (seen.add(entry.key)) total += entry.value.length;
    }
    for (final entry in _diskBlockBytes.entries) {
      if (seen.add(entry.key)) total += entry.value;
    }
    return total;
  }

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
    // Populate pins + disk-block accounting early so storedBytes is
    // correct before the first content op on a restart.
    if (_persistLocal) unawaited(_blocksDir());
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

  /// Emergency data wipe: drops the in-memory stores and deletes the
  /// on-disk repo (`datastore`, `keystore`, `blocks`, `local_blocks`)
  /// under `<dataDir>`. Call only after [stopNode] - deleting a live
  /// repo leaves the engine writing to unlinked paths.
  Future<void> wipeLocalData() async {
    _localStore.clear();
    _pinnedCids.clear();
    _diskBlockBytes.clear();
    _blocksDirFuture = null;
    final dir = Directory(await _dataDir());
    if (dir.existsSync()) await dir.delete(recursive: true);
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

  // Local-mode blocks persist on disk under `<dataDir>/local_blocks/`
  // so content added while the engine is down survives restarts - a
  // manifest must never outlive the payload it points at (that gap is
  // what produced "CID integrity check failed: content unavailable"
  // for blocks that only ever lived in the in-memory map).
  // Cache the FUTURE, not the directory: assigning _localBlocksDir
  // before the awaits would let a second caller return early while the
  // pins/byte scan is still in flight - exactly the stale-read race
  // ensureBlocksReady exists to close.
  Future<Directory>? _blocksDirFuture;

  Future<Directory> _blocksDir() => _blocksDirFuture ??= _initBlocksDir();

  Future<Directory> _initBlocksDir() async {
    final dir =
        Directory(_localStoreDirOverride ?? '${await _dataDir()}/local_blocks');
    if (!dir.existsSync()) await dir.create(recursive: true);
    await _loadPins(dir);
    await _scanDiskBlocks(dir);
    // The engine blockstore is a second on-disk store: networked-mode
    // addFile writes there (not local_blocks), so without this scan
    // storedBytes reports 0 B for blocks the node verifiably holds.
    await _scanDiskBlocks(
        Directory(_engineBlocksDirOverride ?? '${await _dataDir()}/blocks'));
    return dir;
  }

  /// Sizes every persisted block so storedBytes counts them. Runs once
  /// per blocks-dir creation; writes/deletes keep the map current.
  Future<void> _scanDiskBlocks(Directory dir) async {
    try {
      await for (final entity in dir.list()) {
        final name = entity.uri.pathSegments.last;
        if (entity is File && !name.startsWith('.')) {
          _diskBlockBytes[name] = await entity.length();
        }
      }
    } catch (_) {}
  }

  /// Pin state is as durable as the blocks it protects: a restart
  /// must not let runGc reap every disk block as "unpinned". Stored
  /// as a dotfile inside the blocks dir (never a valid CID, skipped
  /// by GC listing).
  Future<void> _loadPins(Directory dir) async {
    try {
      final f = File('${dir.path}/.pins');
      if (f.existsSync()) {
        _pinnedCids.addAll((await f.readAsLines()).where((l) => l.isNotEmpty));
      }
    } catch (_) {}
  }

  Future<void> _savePins() async {
    if (!_persistLocal) return;
    try {
      final f = File('${(await _blocksDir()).path}/.pins');
      await f.writeAsString(_pinnedCids.join('\n'), flush: true);
    } catch (_) {}
  }

  /// Filenames are derived from CIDs - gate on structural validity so
  /// an arbitrary string can never become a filesystem path.
  bool _persistableCid(String cid) =>
      _ref.read(cidServiceProvider).isValidCid(cid);

  Future<void> _writeLocalBlock(String cid, Uint8List data) async {
    if (!_persistLocal || !_persistableCid(cid)) return;
    try {
      final file = File('${(await _blocksDir()).path}/$cid');
      await file.writeAsBytes(data, flush: true);
      _diskBlockBytes[cid] = data.length;
    } catch (_) {
      // Disk write failed - the in-memory copy still serves this
      // session; persistence degrades, correctness does not.
    }
  }

  Future<Uint8List?> _readLocalBlock(String cid) async {
    if (!_persistLocal || !_persistableCid(cid)) return null;
    try {
      final file = File('${(await _blocksDir()).path}/$cid');
      if (!file.existsSync()) return null;
      final data = await file.readAsBytes();
      if (data.isEmpty) return null;
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _localBlockExists(String cid) async {
    if (_localStore.containsKey(cid)) return true;
    // Scanned disk stores (local_blocks + the engine blockstore) - a
    // block verifiably on disk is retrievable without a network hop.
    if (_diskBlockBytes.containsKey(cid)) return true;
    if (!_persistLocal || !_persistableCid(cid)) return false;
    try {
      return File('${(await _blocksDir()).path}/$cid').existsSync();
    } catch (_) {
      return false;
    }
  }

  void _attachNode(IPFS node) {
    // Engine pins are durable (datastore/pins.hive) - merge them into
    // the local view so a restart sees networked-mode pins instead of
    // reporting an empty "No content preserved" for a populated store.
    unawaited(_loadEnginePins(node));
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

  /// Pulls the engine's persisted pin list into [_pinnedCids]. Runs
  /// once per attach - later pin/unpin calls update both views.
  Future<void> _loadEnginePins(IPFS node) async {
    try {
      final pins = await node.pinnedCids;
      if (pins.isNotEmpty) {
        _pinnedCids.addAll(pins);
        unawaited(_savePins());
      }
    } catch (_) {}
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
        // Persist the pin on BOTH stores: the engine's pins.hive
        // protects the block from engine GC, and .pins lets a cold
        // start see the pin before the engine finishes attaching.
        unawaited(() async {
          try {
            await node.pin(cid);
          } catch (_) {}
        }());
        unawaited(_savePins());
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
    await _writeLocalBlock(cid, data);
    unawaited(_savePins());
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
    final local = _localStore[cid] ?? await _readLocalBlock(cid);
    if (local != null) {
      _localStore[cid] = local; // hydrate the memory cache
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
    if (!await _localBlockExists(cid)) return false;
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
    unawaited(_savePins());
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
    unawaited(_savePins());
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
        if (await _localBlockExists(cid) && !out.contains('peer_local_self')) {
          out.add('peer_local_self');
        }
        return out;
      } catch (_) {
        // Query failed - fall through to the honest local answer.
      }
    }
    if (await _localBlockExists(cid)) return ['peer_local_self'];
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
    if (!_persistLocal) return true;
    try {
      // Disk blocks follow the same pin gate - GC removes exactly what
      // is unpinned, in memory and on disk alike.
      final dir = await _blocksDir();
      await for (final entity in dir.list()) {
        final name = entity.uri.pathSegments.last;
        if (entity is File &&
            !name.startsWith('.') &&
            !_pinnedCids.contains(name)) {
          await entity.delete();
          _diskBlockBytes.remove(name);
        }
      }
    } catch (_) {}
    return true;
  }
}
