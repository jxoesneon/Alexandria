import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/collection_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

class _FakeIdentityService extends IdentityService {
  _FakeIdentityService([this._identity]) : super(SecureStorageService());

  final AlexandriaIdentity? _identity;

  @override
  Future<AlexandriaIdentity?> getIdentity() async => _identity;

  @override
  Future<Uint8List> sign(Uint8List data) async => Uint8List(64);
}

AlexandriaIdentity _identity(int fill) => AlexandriaIdentity(
      publicKey: Uint8List.fromList(List.filled(32, fill)),
      privateKey: Uint8List.fromList(List.filled(32, fill + 1)),
      createdAt: DateTime(2024),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('collectionServiceProvider', () {
    test('resolves a CollectionService through Riverpod', () {
      final container = ProviderContainer(overrides: [
        identityServiceProvider
            .overrideWithValue(_FakeIdentityService(_identity(1))),
      ]);
      addTearDown(container.dispose);

      expect(
          container.read(collectionServiceProvider), isA<CollectionService>());
    });
  });

  group('HybridLogicalClock coverage', () {
    final node = Uint8List.fromList([9, 9]);

    test('merge takes fresh wall-clock branch', () {
      final a = HybridLogicalClock(wallTime: 1000, logical: 5, nodeId: node);
      final b = HybridLogicalClock(wallTime: 2000, logical: 7, nodeId: node);
      // Both timestamps far in the past - 'now' wins outright.
      final merged = a.merge(b);
      expect(
          merged.wallTime, greaterThan(2000)); // fresh wall time, logical reset
      expect(merged.logical, 0);
    });

    test('merge keeps local when local wallTime is in the future', () {
      final future = DateTime.now().millisecondsSinceEpoch + 60000;
      final a = HybridLogicalClock(wallTime: future, logical: 3, nodeId: node);
      final b =
          HybridLogicalClock(wallTime: future - 10, logical: 9, nodeId: node);
      final merged = a.merge(b);
      expect(merged.wallTime, future);
      expect(merged.logical, 4);
    });

    test('merge adopts remote when remote wallTime is in the future', () {
      final future = DateTime.now().millisecondsSinceEpoch + 60000;
      final a =
          HybridLogicalClock(wallTime: future - 10, logical: 3, nodeId: node);
      final b = HybridLogicalClock(wallTime: future, logical: 9, nodeId: node);
      final merged = a.merge(b);
      expect(merged.wallTime, future);
      expect(merged.logical, 10);
    });

    test('merge on equal wallTime keeps the higher logical', () {
      final future = DateTime.now().millisecondsSinceEpoch + 60000;
      final a = HybridLogicalClock(wallTime: future, logical: 3, nodeId: node);
      final b = HybridLogicalClock(wallTime: future, logical: 9, nodeId: node);
      expect(a.merge(b).logical, 10);
      expect(b.merge(a).logical, 10);
    });

    test('compareTo orders by wallTime then logical then nodeId', () {
      final early = HybridLogicalClock(wallTime: 1, logical: 0, nodeId: node);
      final late = HybridLogicalClock(wallTime: 2, logical: 0, nodeId: node);
      expect(early.compareTo(late), lessThan(0));
      expect(late.compareTo(early), greaterThan(0));

      final lowLogical =
          HybridLogicalClock(wallTime: 5, logical: 1, nodeId: node);
      final highLogical =
          HybridLogicalClock(wallTime: 5, logical: 2, nodeId: node);
      expect(lowLogical.compareTo(highLogical), lessThan(0));

      // Equal wall+logical - node id bytes break the tie.
      final nodeA = HybridLogicalClock(
          wallTime: 5, logical: 1, nodeId: Uint8List.fromList([1]));
      final nodeB = HybridLogicalClock(
          wallTime: 5, logical: 1, nodeId: Uint8List.fromList([2]));
      expect(nodeA.compareTo(nodeB), lessThan(0));
      expect(nodeB.compareTo(nodeA), greaterThan(0));

      // Prefix-equal node ids - length breaks the tie.
      final short = HybridLogicalClock(
          wallTime: 5, logical: 1, nodeId: Uint8List.fromList([7]));
      final long = HybridLogicalClock(
          wallTime: 5, logical: 1, nodeId: Uint8List.fromList([7, 7]));
      expect(short.compareTo(long), lessThan(0));
    });

    test('toJson/fromJson round-trips', () {
      final clock = HybridLogicalClock(
          wallTime: 4242, logical: 7, nodeId: Uint8List.fromList([1, 2, 3]));
      final json = clock.toJson();
      final restored = HybridLogicalClock.fromJson(json);
      expect(restored.wallTime, 4242);
      expect(restored.logical, 7);
      expect(restored.nodeId, [1, 2, 3]);
    });

    test('fromJson rejects malformed wire input', () {
      expect(
          () => HybridLogicalClock.fromJson(const {}), throwsFormatException);
      expect(
          () => HybridLogicalClock.fromJson(
              const {'wallTime': 'not-an-int', 'logical': 1, 'nodeId': 'eA=='}),
          throwsFormatException);
      expect(
          () => HybridLogicalClock.fromJson(const {
                'wallTime': 1,
                'logical': 1,
                'nodeId': '%%%not-base64%%%'
              }),
          throwsFormatException);
      expect(
          () => HybridLogicalClock.fromJson(
              const {'wallTime': 1, 'logical': 1, 'nodeId': ''}),
          throwsFormatException);
    });
  });

  group('MergeRequest serialization', () {
    test('toJson emits base64 signature and ISO timestamp', () {
      final req = MergeRequest(
        id: 'mr-1',
        sourceId: 'src',
        targetId: 'tgt',
        diff: const {'name': 'x'},
        signature: Uint8List.fromList([1, 2, 3]),
        timestamp: DateTime.utc(2024, 5, 6),
        status: 'approved',
      );
      final json = req.toJson();
      expect(json['id'], 'mr-1');
      expect(json['sourceId'], 'src');
      expect(json['targetId'], 'tgt');
      expect(json['diff'], {'name': 'x'});
      expect(json['signature'], base64Encode([1, 2, 3]));
      expect(json['timestamp'], '2024-05-06T00:00:00.000Z');
      expect(json['status'], 'approved');
    });
  });

  group('CollectionService uncovered branches', () {
    test('createCollection and forkCollection throw without identity',
        () async {
      final service = CollectionService(_FakeIdentityService(null));
      await expectLater(service.createCollection(name: 'X'), throwsStateError);
      await expectLater(service.forkCollection('missing'), throwsStateError);
    });

    test('createMergeRequest reports diffs for name, description, and items',
        () async {
      final service = CollectionService(_FakeIdentityService(_identity(1)));
      final source = await service.createCollection(
          name: 'Source Name', description: 'source desc');
      final target = await service.createCollection(
          name: 'Target Name', description: 'target desc');

      await service.addItem(
          collectionId: source.id, contentCid: 'cid-only-in-source');

      final request = await service.createMergeRequest(
          sourceId: source.id, targetId: target.id);
      expect(request, isNotNull);
      expect(request!.diff['name'], 'Source Name');
      expect(request.diff['description'], 'source desc');
      final added = request.diff['addedItems'] as List;
      expect(added.length, 1);
      expect(added.first['contentCid'], 'cid-only-in-source');
      expect(request.signature.length, 64);
    });

    test('mergeRemoteState adopts a newer authorized name and description',
        () async {
      final identity = _identity(3);
      final service = CollectionService(_FakeIdentityService(identity));
      final collection =
          await service.createCollection(name: 'Old', description: 'old desc');

      final authorB64 = base64Encode(identity.publicKey);
      // Owner already holds editor-or-higher authority.
      final now = DateTime.now().millisecondsSinceEpoch;
      final remoteState = {
        'name': {
          'value': 'New Remote Name',
          'author': authorB64,
          'timestamp': {
            'wallTime': now + 1000,
            'logical': 5,
            'nodeId': authorB64,
          },
        },
        'description': {
          'value': 'new remote desc',
          'author': authorB64,
          'timestamp': {
            'wallTime': now + 1000,
            'logical': 5,
            'nodeId': authorB64,
          },
        },
      };

      await service.mergeRemoteState(collection.id, remoteState);
      expect(collection.name.value, 'New Remote Name');
      expect(collection.description.value, 'new remote desc');
    });

    test('mergeRemoteState ignores malformed, unauthorized, and stale writes',
        () async {
      final identity = _identity(4);
      final service = CollectionService(_FakeIdentityService(identity));
      final collection =
          await service.createCollection(name: 'Keep', description: 'keep');
      final authorB64 = base64Encode(identity.publicKey);
      final otherAuthor = base64Encode(Uint8List.fromList(List.filled(32, 9)));
      final now = DateTime.now().millisecondsSinceEpoch;

      await service.mergeRemoteState(collection.id, {
        // malformed: not a map
        'name': 'just-a-string',
        // unauthorized author (no editor role)
        'description': {
          'value': 'hijacked',
          'author': otherAuthor,
          'timestamp': {
            'wallTime': now + 1000,
            'logical': 1,
            'nodeId': otherAuthor
          },
        },
      });
      expect(collection.name.value, 'Keep');
      expect(collection.description.value, 'keep');

      // far-future forged clock is dropped
      await service.mergeRemoteState(collection.id, {
        'name': {
          'value': 'future forged',
          'author': authorB64,
          'timestamp': {
            'wallTime': now + const Duration(hours: 1).inMilliseconds,
            'logical': 0,
            'nodeId': authorB64,
          },
        },
      });
      expect(collection.name.value, 'Keep');

      // stale (older) authorized write does not win the LWW
      await service.mergeRemoteState(collection.id, {
        'name': {
          'value': 'stale write',
          'author': authorB64,
          'timestamp': {
            'wallTime': collection.name.timestamp.wallTime - 100000,
            'logical': 0,
            'nodeId': authorB64,
          },
        },
      });
      expect(collection.name.value, 'Keep');
    });

    test('mergeRemoteState on an unknown collection only logs', () async {
      final service = CollectionService(_FakeIdentityService(_identity(5)));
      await service.mergeRemoteState('no-such-collection', {
        'name': {'value': 'x'}
      });
    });
  });
}
