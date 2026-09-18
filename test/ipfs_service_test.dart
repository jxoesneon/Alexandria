import 'dart:io';
import 'dart:typed_data';
import 'package:dart_ipfs/dart_ipfs.dart' show IPFS, IPFSConfig, PubSubMessage;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

/// Minimal Ref adapter so tests can construct IpfsService directly
/// (e.g. with an injected localStoreDir) without a provider override.
class _Ref implements Ref {
  _Ref(this._container);
  final ProviderContainer _container;

  @override
  T read<T>(ProviderListenable<T> provider) => _container.read(provider);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Minimal stand-in for the dart_ipfs engine: returns canned pins,
/// records pin() calls, and mints a deterministic CID for addFile.
class _FakeEngine implements IPFS {
  _FakeEngine({this.persistedPins = const [], this.throwOnPin = false});

  final List<String> persistedPins;
  final bool throwOnPin;
  final List<String> pinCalls = [];

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  String get peerID => 'fakeEnginePeer';

  @override
  Future<List<String>> get pinnedCids async => persistedPins;

  @override
  Future<void> pin(String cid) async {
    if (throwOnPin) throw StateError('pin failed');
    pinCalls.add(cid);
  }

  @override
  Future<String> addFile(Uint8List data) async => 'fakeEngineCid';

  @override
  Stream<PubSubMessage> get pubsubMessages => const Stream.empty();

  @override
  Future<List<String>> get connectedPeers async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSecureStorage implements SecureStorageService {
  @override
  String get keyPrefix => '';
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);

  @override
  Future<void> deleteAll() async => data.clear();

  @override
  Future<bool> containsKey(String key) async => data.containsKey(key);
}

class _ThrowingSecureStorage implements SecureStorageService {
  @override
  String get keyPrefix => '';
  @override
  Future<String?> read(String key) async =>
      throw StateError('keychain unavailable');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('IpfsService (dart_ipfs 1.16.x Engine) Tests', () {
    late ProviderContainer container;
    late IpfsService ipfs;

    setUp(() {
      container = ProviderContainer();
      ipfs = container.read(ipfsServiceProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('starts and stops IPFS node lifecycle', () async {
      expect(ipfs.isStarted, isFalse);
      await ipfs.startNode();
      expect(ipfs.isStarted, isTrue);
      await ipfs.stopNode();
      expect(ipfs.isStarted, isFalse);
    });

    test('adds file, retrieves stream, pins and unpins CIDs', () async {
      final payload =
          Uint8List.fromList('Alexandria P2P Knowledge Block'.codeUnits);
      final cid = await ipfs.addFile(payload);
      expect(cid.startsWith('b'), isTrue);

      final retrieved = await ipfs.getFile(cid).first;
      expect(retrieved, equals(payload));

      final pinRes = await ipfs.pinCid(cid);
      expect(pinRes, isTrue);

      final providers = await ipfs.findProviders(cid);
      expect(providers, contains('peer_local_self'));

      final unpinRes = await ipfs.unpinCid(cid);
      expect(unpinRes, isTrue);
    });

    test('handles pubsub publishing and garbage collection', () async {
      var received = false;
      ipfs.pubsubStream.listen((msg) {
        if (msg['topic'] == '/alexandria/test') received = true;
      });

      await ipfs.publishToPubsub('/alexandria/test', 'hello');
      await Future.delayed(const Duration(milliseconds: 20));
      expect(received, isTrue);

      final gc = await ipfs.runGc();
      expect(gc, isTrue);
    });

    test('local-only mode reports honest empty swarm seams', () async {
      // Under FLUTTER_TEST the engine factory is null - the service is
      // in honest local-only mode. Network-layer seams must report
      // unavailability rather than fabricate connectivity.
      await ipfs.startNode();
      expect(ipfs.isNetworked, isFalse);
      expect(ipfs.nodePeerId, isNull);
      expect(ipfs.listenAddrs, isEmpty);
      expect(await ipfs.provideCid('bafyAnything'), isFalse);
      expect(await ipfs.swarmConnect('/ip4/1.2.3.4/tcp/4001/p2p/12D3KooWX'),
          isFalse);
      expect(ipfs.swarmPeerCount, 0);
    });

    test('local-mode blocks and pins persist across instances', () async {
      final dir = await Directory.systemTemp.createTemp('alx_blocks_test');
      try {
        final svc1 = IpfsService(_Ref(container), localStoreDir: dir.path);
        final payload = Uint8List.fromList('durable block'.codeUnits);
        final cid = await svc1.addFile(payload);
        expect(File('${dir.path}/$cid').existsSync(), isTrue);

        // Simulated restart: a fresh service over the same dir has no
        // memory of the add, but must still serve the block and its pin.
        final svc2 = IpfsService(_Ref(container), localStoreDir: dir.path);
        final retrieved = await svc2.getFile(cid).first;
        expect(retrieved, equals(payload));
        expect(await svc2.pinCid(cid), isTrue);
        await svc2.runGc();
        expect(File('${dir.path}/$cid').existsSync(), isTrue);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('storedBytes counts disk-persisted blocks after a restart', () async {
      final dir = await Directory.systemTemp.createTemp('alx_bytes_test');
      try {
        final svc1 = IpfsService(_Ref(container), localStoreDir: dir.path);
        final payload = Uint8List.fromList('durable block'.codeUnits);
        await svc1.addFile(payload);
        // Present in memory AND on disk - counts once.
        expect(svc1.storedBytes, payload.length);

        // Simulated restart: a fresh service has no memory of the add,
        // but the on-disk block must still count toward stored bytes
        // (the "0 B / 3 docs" Home-card inconsistency).
        final svc2 = IpfsService(_Ref(container), localStoreDir: dir.path);
        await svc2.startNode();
        // The blocks-dir scan is fired asynchronously at startNode.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(svc2.storedBytes, payload.length);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('storedBytes and block lookups cover the engine blockstore', () async {
      final localDir = await Directory.systemTemp.createTemp('alx_local_test');
      final engineDir =
          await Directory.systemTemp.createTemp('alx_engine_test');
      try {
        // Blocks written by the networked engine land in its own
        // blockstore, not local_blocks - a restart must still count
        // them toward storedBytes and see them as retrievable.
        const engineCid =
            'bafkreierpqoli2pbvdv2mcbybb3e24jr3kgxsfalk5nuefgj2avhh3cffa';
        final payload = Uint8List.fromList('engine-held'.codeUnits);
        await File('${engineDir.path}/$engineCid').writeAsBytes(payload);

        final svc = IpfsService(_Ref(container),
            localStoreDir: localDir.path, engineBlocksDir: engineDir.path);
        await svc.startNode();
        await svc.ensureBlocksReady();
        expect(svc.storedBytes, payload.length);
        // A pin on an engine-held block is legitimate - the block is
        // verifiably on this node's disk.
        expect(await svc.pinCid(engineCid), isTrue);
      } finally {
        await localDir.delete(recursive: true);
        await engineDir.delete(recursive: true);
      }
    });

    test('runGc reaps unpinned disk blocks', () async {
      final dir = await Directory.systemTemp.createTemp('alx_blocks_gc');
      try {
        final svc = IpfsService(_Ref(container), localStoreDir: dir.path);
        final cid =
            await svc.addFile(Uint8List.fromList('ephemeral'.codeUnits));
        await svc.unpinCid(cid);
        await svc.runGc();
        expect(File('${dir.path}/$cid').existsSync(), isFalse);
        await expectLater(svc.getFile(cid), emitsDone);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('attach merges persisted engine pins into the pin set', () async {
      final engine = _FakeEngine(persistedPins: [
        'bafkreigh2akiscaildc6zc2vvpd3hfnhjyj2e3aq3xrgh7w2qjvpmw2hny'
      ]);
      final svc = IpfsService(_Ref(container),
          engineFactory: (_) async => engine,
          configBuilder: (_) => IPFSConfig());

      await svc.startNode();
      // _loadEnginePins runs unawaited on attach - let it settle.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
          svc.pinnedCids.contains(
              'bafkreigh2akiscaildc6zc2vvpd3hfnhjyj2e3aq3xrgh7w2qjvpmw2hny'),
          isTrue);
      await svc.stopNode();
    });

    test('networked addFile pins through the engine', () async {
      final engine = _FakeEngine();
      final svc = IpfsService(_Ref(container),
          engineFactory: (_) async => engine,
          configBuilder: (_) => IPFSConfig());

      await svc.startNode();
      final cid = await svc.addFile(Uint8List.fromList('net'.codeUnits));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cid, 'fakeEngineCid');
      expect(engine.pinCalls, contains('fakeEngineCid'));
      expect(svc.pinnedCids.contains(cid), isTrue);
      await svc.stopNode();
    });

    test('engine pin failure during addFile still keeps local pin', () async {
      final engine = _FakeEngine(throwOnPin: true);
      final svc = IpfsService(_Ref(container),
          engineFactory: (_) async => engine,
          configBuilder: (_) => IPFSConfig());

      await svc.startNode();
      final cid = await svc.addFile(Uint8List.fromList('net'.codeUnits));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cid, 'fakeEngineCid');
      expect(svc.pinnedCids.contains(cid), isTrue);
      await svc.stopNode();
    });

    test('libp2p identity seed persists across restarts', () async {
      final storage = _FakeSecureStorage();
      final c = ProviderContainer(overrides: [
        secureStorageServiceProvider.overrideWithValue(storage),
      ]);
      addTearDown(c.dispose);

      IPFSConfig? firstConfig;
      final svc1 = IpfsService(_Ref(c), engineFactory: (cfg) async {
        firstConfig = cfg;
        return _FakeEngine();
      });
      await svc1.startNode();
      await svc1.stopNode();

      IPFSConfig? secondConfig;
      final svc2 = IpfsService(_Ref(c), engineFactory: (cfg) async {
        secondConfig = cfg;
        return _FakeEngine();
      });
      await svc2.startNode();
      await svc2.stopNode();

      expect(firstConfig!.libp2pIdentitySeed, isNotNull);
      expect(firstConfig!.libp2pIdentitySeed, secondConfig!.libp2pIdentitySeed);
    });

    test('unavailable secure storage falls back to ephemeral identity',
        () async {
      final c = ProviderContainer(overrides: [
        secureStorageServiceProvider
            .overrideWithValue(_ThrowingSecureStorage()),
      ]);
      addTearDown(c.dispose);

      IPFSConfig? config;
      final svc = IpfsService(_Ref(c), engineFactory: (cfg) async {
        config = cfg;
        return _FakeEngine();
      });
      await svc.startNode();

      expect(config!.libp2pIdentitySeed, isNull);
      expect(svc.isStarted, isTrue);
      await svc.stopNode();
    });
  });
}
