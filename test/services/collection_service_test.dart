import 'dart:convert';
import 'dart:typed_data';

import 'package:alexandria/services/collection_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeIdentityService extends IdentityService {
  final AlexandriaIdentity _identity;

  FakeIdentityService(this._identity) : super(SecureStorageService());

  @override
  Future<AlexandriaIdentity?> getIdentity() async => _identity;

  @override
  Future<Uint8List> sign(Uint8List data) async => Uint8List(64);
}

AlexandriaIdentity _testIdentity() {
  return AlexandriaIdentity(
    publicKey: Uint8List.fromList(List.filled(32, 1)),
    privateKey: Uint8List.fromList(List.filled(32, 2)),
    createdAt: DateTime(2024),
  );
}

HybridLogicalClock _clock(int wallTime) {
  return HybridLogicalClock(
    wallTime: wallTime,
    logical: 0,
    nodeId: Uint8List.fromList(List.filled(32, 1)),
  );
}

void main() {
  group('HybridLogicalClock', () {
    test('now creates a clock from the current time', () {
      final nodeId = Uint8List.fromList(List.filled(32, 1));
      final clock = HybridLogicalClock.now(nodeId);

      expect(clock.wallTime, greaterThan(0));
      expect(clock.logical, 0);
      expect(clock.nodeId, nodeId);
    });

    test('increment increases the logical counter', () {
      final clock = _clock(100);
      final incremented = clock.increment();

      expect(incremented.wallTime, clock.wallTime);
      expect(incremented.logical, clock.logical + 1);
    });

    test('compareTo orders by wall time, logical and node id', () {
      final a = _clock(100);
      final b = _clock(200);

      expect(a.compareTo(b), lessThan(0));
      expect(b.compareTo(a), greaterThan(0));
      expect(a.compareTo(a), 0);
    });

    test('merge uses a newer wall time when available', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final a = _clock(100);
      final b = _clock(50);

      final merged = a.merge(b);

      expect(merged.wallTime, greaterThanOrEqualTo(now));
      expect(merged.logical, 0);
    });

    test('toJson and fromJson round trip', () {
      final clock = _clock(123);
      final json = clock.toJson();
      final restored = HybridLogicalClock.fromJson(json);

      expect(restored.wallTime, clock.wallTime);
      expect(restored.logical, clock.logical);
      expect(restored.nodeId, clock.nodeId);
    });
  });

  group('LWWRegister', () {
    test('merge keeps the value with the higher timestamp', () {
      final clockA = _clock(100);
      final clockB = _clock(200);
      final a = LWWRegister<String>(
        value: 'A',
        timestamp: clockA,
        author: Uint8List(32),
      );
      final b = LWWRegister<String>(
        value: 'B',
        timestamp: clockB,
        author: Uint8List(32),
      );

      expect(a.merge(b).value, 'B');
      expect(b.merge(a).value, 'B');
    });

    test('set updates the value only when the new timestamp is higher', () {
      final oldClock = _clock(100);
      final newClock = _clock(200);
      final register = LWWRegister<String>(
        value: 'Old',
        timestamp: oldClock,
        author: Uint8List(32),
      );

      final updated = register.set(
        'New',
        newClock,
        Uint8List(32),
      );
      expect(updated.value, 'New');

      final stale = updated.set('Stale', oldClock, Uint8List(32));
      expect(stale.value, 'New');
    });

    test('toJson encodes value and timestamp', () {
      final clock = _clock(100);
      final register = LWWRegister<String>(
        value: 'test',
        timestamp: clock,
        author: Uint8List(32),
      );

      final json = register.toJson((v) => v);

      expect(json['value'], 'test');
      expect(json['timestamp'], clock.toJson());
      expect(json['author'], base64Encode(Uint8List(32)));
    });
  });

  group('ORSet', () {
    test('add and remove elements', () {
      final set = ORSet<String>();

      set.add('A', 'id-1');
      set.add('B', 'id-2');
      expect(set.elements, contains('A'));
      expect(set.elements, contains('B'));

      set.remove('id-1');
      expect(set.elements, isNot(contains('A')));
    });

    test('merge combines two sets and respects removals', () {
      final a = ORSet<String>();
      final b = ORSet<String>();

      a.add('A', 'id-1');
      a.add('B', 'id-2');
      b.add('B', 'id-3');
      b.add('C', 'id-4');

      a.merge(b);

      expect(a.elements, contains('A'));
      expect(a.elements, contains('B'));
      expect(a.elements, contains('C'));
    });

    test('toJson encodes elements and removed ids', () {
      final set = ORSet<String>();
      set.add('A', 'id-1');
      set.remove('id-1');

      final json = set.toJson((v) => v);

      expect((json['elements'] as Map<String, dynamic>).isEmpty, isTrue);
      expect(json['removed'], ['id-1']);
    });
  });

  group('GCounter', () {
    test('increment and value', () {
      final counter = GCounter();

      counter.increment('node-1');
      counter.increment('node-1');
      counter.increment('node-2');

      expect(counter.value, 3);
    });

    test('merge takes the maximum per node', () {
      final a = GCounter();
      final b = GCounter();

      a.increment('node-1');
      a.increment('node-1');
      b.increment('node-1');
      b.increment('node-2');

      a.merge(b);

      expect(a.value, 3);
    });

    test('toJson returns the counts', () {
      final counter = GCounter();
      counter.increment('node-1');

      expect(counter.toJson(), {'node-1': 1});
    });
  });

  group('CollectionItem', () {
    test('toJson and fromJson round trip', () {
      final item = CollectionItem(
        contentCid: 'cid-1',
        addedBy: Uint8List.fromList([1, 2, 3]),
        addedAt: DateTime(2024, 1, 1),
        note: 'note',
      );

      final restored = CollectionItem.fromJson(item.toJson());

      expect(restored.contentCid, item.contentCid);
      expect(restored.addedBy, item.addedBy);
      expect(restored.addedAt, item.addedAt);
      expect(restored.note, item.note);
    });
  });

  group('Collection', () {
    test('hasRole checks the access control map', () {
      final identity = _testIdentity();
      final collection = _createTestCollection(identity);

      expect(
        collection.hasRole(identity.publicKey, CollectionRole.viewer),
        isTrue,
      );
      expect(
        collection.hasRole(Uint8List(32), CollectionRole.viewer),
        isFalse,
      );
    });

    test('merge picks the winning name register', () {
      final identity = _testIdentity();
      final local = _createTestCollection(identity);
      final remote = _createTestCollection(
        identity,
        name: 'Remote Name',
        clock: _clock(local.lastModified.wallTime + 1),
      );

      local.merge(remote);

      expect(local.name.value, 'Remote Name');
    });

    test('toJson includes all fields', () {
      final identity = _testIdentity();
      final collection = _createTestCollection(identity);

      final json = collection.toJson();

      expect(json['id'], collection.id);
      expect(json['rootCid'], collection.rootCid);
      expect(json['name'], isA<Map<String, dynamic>>());
      expect(json['items'], isA<Map<String, dynamic>>());
      expect(json['accessControl'], isA<Map<String, dynamic>>());
    });
  });

  group('CollectionService', () {
    late CollectionService service;
    late AlexandriaIdentity identity;

    setUp(() {
      identity = _testIdentity();
      service = CollectionService(FakeIdentityService(identity));
    });

    test('createCollection creates and stores a new collection', () async {
      final collection = await service.createCollection(name: 'Research');

      expect(collection, isNotNull);
      expect(collection.name.value, 'Research');
      expect(
        collection.hasRole(identity.publicKey, CollectionRole.owner),
        isTrue,
      );
      expect(service.getCollection(collection.id), collection);
    });

    test('addItem adds an item to a collection', () async {
      final collection = await service.createCollection(name: 'Papers');

      final added = await service.addItem(
        collectionId: collection.id,
        contentCid: 'cid-1',
        note: 'Important paper',
      );

      expect(added, isTrue);
      expect(collection.items.elements.length, 1);
      final item = collection.items.elements.first;
      expect(item.contentCid, 'cid-1');
      expect(item.note, 'Important paper');
    });

    test('addItem returns false for a missing collection', () async {
      final added = await service.addItem(
        collectionId: 'missing',
        contentCid: 'cid-1',
      );

      expect(added, isFalse);
    });

    test('forkCollection copies a collection and tracks parent id', () async {
      final source = await service.createCollection(name: 'Source');
      await service.addItem(
        collectionId: source.id,
        contentCid: 'cid-1',
      );

      final forked = await service.forkCollection(source.id);

      expect(forked.parentId, source.id);
      expect(forked.name.value, source.name.value);
      expect(forked.items.elements.length, 1);
      expect(service.collections.length, 2);
    });

    test('forkCollection throws for a missing source', () async {
      expect(
        () => service.forkCollection('missing'),
        throwsA(isA<StateError>()),
      );
    });

    test('grantRole allows a new user to access the collection', () async {
      final collection = await service.createCollection(name: 'Shared');
      final otherKey = Uint8List.fromList(List.filled(32, 2));

      expect(collection.hasRole(otherKey, CollectionRole.curator), isFalse);

      final granted = await service.grantRole(
        collectionId: collection.id,
        userKey: otherKey,
        role: CollectionRole.curator,
      );

      expect(granted, isTrue);
      expect(collection.hasRole(otherKey, CollectionRole.curator), isTrue);
    });

    test('createMergeRequest returns a diff between two collections', () async {
      final source = await service.createCollection(name: 'Source');
      final target = await service.createCollection(name: 'Target');
      await service.addItem(
        collectionId: source.id,
        contentCid: 'cid-1',
      );

      final request = await service.createMergeRequest(
        sourceId: source.id,
        targetId: target.id,
      );

      expect(request, isNotNull);
      expect(request!.sourceId, source.id);
      expect(request.targetId, target.id);
      expect(request.diff['name'], 'Source');
      expect((request.diff['addedItems'] as List).length, 1);
      expect(request.signature, isNotEmpty);
    });

    test('createMergeRequest returns null for a missing collection', () async {
      final source = await service.createCollection(name: 'Source');

      final request = await service.createMergeRequest(
        sourceId: source.id,
        targetId: 'missing',
      );

      expect(request, isNull);
    });

    test('mergeRemoteState updates name when remote timestamp is newer',
        () async {
      final collection = await service.createCollection(name: 'Local');
      final remoteKey = base64Encode(identity.publicKey);
      final remoteClock = HybridLogicalClock(
        wallTime: collection.lastModified.wallTime + 1,
        logical: 0,
        nodeId: identity.publicKey,
      );

      await service.mergeRemoteState(collection.id, {
        'name': {
          'value': 'Remote Name',
          'timestamp': remoteClock.toJson(),
          'author': remoteKey,
        },
      });

      expect(collection.name.value, 'Remote Name');
    });

    test('mergeRemoteState does nothing for an unknown collection', () async {
      expect(
        () => service.mergeRemoteState('unknown', {}),
        returnsNormally,
      );
      expect(service.getCollection('unknown'), isNull);
    });
  });
}

Collection _createTestCollection(
  AlexandriaIdentity identity, {
  String name = 'Test Collection',
  HybridLogicalClock? clock,
}) {
  final useClock = clock ??
      HybridLogicalClock(
        wallTime: 1000,
        logical: 0,
        nodeId: identity.publicKey,
      );
  return Collection(
    id: 'test-id',
    rootCid: 'root-cid',
    name: LWWRegister<String>(
      value: name,
      timestamp: useClock,
      author: identity.publicKey,
    ),
    description: LWWRegister<String>(
      value: 'Description',
      timestamp: useClock,
      author: identity.publicKey,
    ),
    tags: ORSet<String>(),
    items: ORSet<CollectionItem>(),
    accessControl: {
      base64Encode(identity.publicKey): CollectionRole.owner,
    },
    created: DateTime(2024),
    lastModified: useClock,
    ownerKey: identity.publicKey,
  );
}
