import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/ipfs_service.dart';

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

    test('storedBytes counts disk-persisted blocks after a restart',
        () async {
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
  });
}
