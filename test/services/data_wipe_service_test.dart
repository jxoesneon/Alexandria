import 'package:alexandria/data/database.dart';
import 'package:alexandria/services/data_wipe_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/network_overview_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSecureStorage implements SecureStorageService {
  @override
  String get keyPrefix => '';
  _FakeSecureStorage(this.calls);

  final List<String> calls;
  final Map<String, String> map = {};

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async => map[key] = value;

  @override
  Future<void> delete(String key) async => map.remove(key);

  @override
  Future<void> deleteAll() async {
    calls.add('storage');
    map.clear();
  }

  @override
  Future<bool> containsKey(String key) async => map.containsKey(key);
}

class _FakeIpfs implements IpfsService {
  _FakeIpfs(this.calls);

  final List<String> calls;

  @override
  Future<void> wipeLocalData() async => calls.add('ipfs');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNetworkOverview implements NetworkOverviewService {
  _FakeNetworkOverview(this.calls);

  final List<String> calls;

  @override
  Future<void> stopNode() async => calls.add('stopNode');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('wipe stops the node, then empties db, repo and keychain in order',
      () async {
    final calls = <String>[];
    final db = AppDatabase();
    final storage = _FakeSecureStorage(calls)..map['identity_key'] = 'secret';
    await db.insertManifest({
      'uuid': 'uuid-1',
      'title': 'Doc',
      'category': 'other',
      'isEncrypted': false,
      'lastUpdated': DateTime.now(),
    });

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        ipfsServiceProvider.overrideWithValue(_FakeIpfs(calls)),
        networkOverviewServiceProvider
            .overrideWithValue(_FakeNetworkOverview(calls)),
        secureStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    await container.read(dataWipeServiceProvider).wipe();

    // The node stops BEFORE the repo is deleted; the keychain is last.
    expect(calls, equals(['stopNode', 'ipfs', 'storage']));
    expect(await db.getAllManifests(), isEmpty);
    expect(storage.map, isEmpty);
  });

  test('a failing step propagates so the UI reports an incomplete wipe',
      () async {
    final calls = <String>[];
    final db = AppDatabase();
    final storage = _ThrowingStorage(calls);

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        ipfsServiceProvider.overrideWithValue(_FakeIpfs(calls)),
        networkOverviewServiceProvider
            .overrideWithValue(_FakeNetworkOverview(calls)),
        secureStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    await expectLater(
      container.read(dataWipeServiceProvider).wipe(),
      throwsStateError,
    );
    expect(calls, equals(['stopNode', 'ipfs']));
  });
}

class _ThrowingStorage extends _FakeSecureStorage {
  _ThrowingStorage(super.calls);

  @override
  Future<void> deleteAll() async => throw StateError('keychain unavailable');
}
