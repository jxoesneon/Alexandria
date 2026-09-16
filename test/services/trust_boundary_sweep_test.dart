// Slot-C sweep tests: trust-boundary fixes in tor_service,
// web_node_service, sync_service, network_overview_service.
import 'dart:typed_data';

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

class _ThrowingSyncService extends FakeSyncService {
  _ThrowingSyncService(super.ref);

  @override
  Future<void> processQueue() async =>
      throw StateError('simulated transport failure');
}

class _ThrowingIpfsService extends FakeIpfsService {
  _ThrowingIpfsService(super.ref);

  @override
  Future<bool> publishToPubsub(String topic, String data) async =>
      throw StateError('simulated publish failure');
}

void main() {
  group('TorService init re-validates stored proxy (sweep)', () {
    late FakeSecureStorageService storage;
    late TorService tor;

    setUp(() {
      storage = FakeSecureStorageService();
      tor = TorService(storage);
    });

    test('a hostile stored host cannot smuggle findProxy directives', () async {
      await storage.write('tor_enabled', 'false');
      // A ';' / space payload would split the findProxy directive list
      // ('PROXY x; DIRECT' would bypass the proxy entirely).
      await storage.write('tor_host', '127.0.0.1; DIRECT');
      await storage.write('tor_port', '9050');

      await tor.init();

      expect(tor.proxyHost, equals('127.0.0.1'),
          reason: 'stored host bypassed setProxy validation — must fail '
              'closed to the loopback default');
      expect(tor.proxyPort, equals(9050));
    });

    test('a stored out-of-range port falls back to the default', () async {
      await storage.write('tor_host', '10.0.0.5');
      await storage.write('tor_port', '99999');

      await tor.init();

      expect(tor.proxyHost, equals('10.0.0.5'));
      expect(tor.proxyPort, equals(9050));
    });
  });

  group('WebNodeService content-addressing integrity (sweep)', () {
    late ProviderContainer container;
    late WebNodeService webNode;

    setUp(() {
      container = ProviderContainer(overrides: [
        webNodeServiceProvider.overrideWith((ref) => WebNodeService(ref,
            blockStore: IndexedDbBlockStore(maxCapacityBytes: 64))),
      ]);
      webNode = container.read(webNodeServiceProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('preserveInBrowser throws when the store refuses the block', () async {
      // A block larger than the store capacity is refused by putBlock
      // - the service must not hand back a CID for content it never
      // stored.
      final oversized = Uint8List(1024);
      await expectLater(webNode.preserveInBrowser(oversized), throwsStateError);
    });

    test('retrieveFromBrowser refuses a CID aliased to foreign bytes',
        () async {
      final data = Uint8List.fromList('real content'.codeUnits);
      final cid = await webNode.preserveInBrowser(data);
      expect(await webNode.retrieveFromBrowser(cid), equals(data));

      // Poison the caller-keyed store directly: a block stored under a
      // CID it does not hash to must not be served.
      final foreign = Uint8List.fromList('attacker bytes'.codeUnits);
      await webNode.blockStore.putBlock('bnotarealcid', foreign);
      expect(await webNode.retrieveFromBrowser('bnotarealcid'), isNull);
    });
  });

  group('SyncService poison-op + topic-shape guards (sweep)', () {
    late ProviderContainer container;
    late FakeSecureStorageService storage;
    late SyncService sync;

    setUp(() {
      storage = FakeSecureStorageService();
      container = ProviderContainer(overrides: [
        ipfsServiceProvider.overrideWith((ref) => FakeIpfsService(ref)),
        secureStorageServiceProvider.overrideWithValue(storage),
      ]);
      sync = container.read(syncServiceProvider);
    });

    tearDown(() {
      sync.dispose();
      container.dispose();
    });

    test('queueOperation rejects topic-escaping field shapes', () async {
      await sync.init();
      await expectLater(
        sync.queueOperation(
          collectionId: 'evil/../../other',
          operation: 'put',
          data: {},
        ),
        throwsArgumentError,
      );
      await expectLater(
        sync.queueOperation(
          collectionId: 'ok',
          operation: 'bad op with spaces',
          data: {},
        ),
        throwsArgumentError,
      );
      expect(sync.offlineQueue, isEmpty);
    });

    test(
        'an unencodable op is refused at enqueue, not wedged in the '
        'queue', () async {
      await sync.init();
      // jsonEncode throws on non-encodable values - this op is poison
      // for both the persistence and publish paths, so it must be
      // refused up front.
      await expectLater(
        sync.queueOperation(
          collectionId: 'col',
          operation: 'put',
          data: {'bad': Object()},
        ),
        throwsArgumentError,
      );
      expect(sync.offlineQueue, isEmpty);

      // A normal op still flows afterwards.
      await sync.queueOperation(
        collectionId: 'col',
        operation: 'put',
        data: {'good': 1},
      );
      expect(sync.offlineQueue, isEmpty);
    });

    test('a throwing transport ages the op out instead of wedging', () async {
      final c2 = ProviderContainer(overrides: [
        ipfsServiceProvider.overrideWith((ref) => _ThrowingIpfsService(ref)),
        secureStorageServiceProvider.overrideWithValue(storage),
      ]);
      addTearDown(c2.dispose);
      final sync2 = c2.read(syncServiceProvider);
      addTearDown(sync2.dispose);
      await sync2.init();

      // publishToPubsub throws for every op - queueOperation must not
      // propagate, and the op must age out at the retry bound.
      await sync2.queueOperation(
        collectionId: 'col',
        operation: 'put',
        data: {'good': 1},
      );
      expect(sync2.offlineQueue, hasLength(1));
      for (var i = 0; i < 4; i++) {
        await sync2.processQueue();
      }
      expect(sync2.offlineQueue, isEmpty);
    });
  });

  group('NetworkOverviewService.triggerManualSync failure (sweep)', () {
    test('a throwing processQueue still clears inProgress', () async {
      final container = ProviderContainer(overrides: [
        ipfsServiceProvider.overrideWith((ref) => FakeIpfsService(ref)),
        meshTransportServiceProvider
            .overrideWith((ref) => FakeMeshTransportService()),
        webNodeServiceProvider.overrideWith((ref) => FakeWebNodeService(ref)),
        syncServiceProvider.overrideWith((ref) => _ThrowingSyncService(ref)),
        secureStorageServiceProvider
            .overrideWith((ref) => FakeSecureStorageService()),
        torServiceProvider.overrideWith(
            (ref) => FakeTorService(ref.read(secureStorageServiceProvider))),
      ]);
      addTearDown(container.dispose);
      final service = container.read(networkOverviewServiceProvider);

      await expectLater(service.triggerManualSync(), throwsStateError);

      final progress = await service.watchSyncProgress().first;
      expect(progress.inProgress, isFalse,
          reason: 'a failed manual sync must not leave the progress state '
              'latched in progress');
      expect(progress, isA<SyncProgress>());
    });
  });
}
