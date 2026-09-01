import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/sync_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

// --- Fakes ---

class FakeIpfsService implements IpfsService {
  String? lastTopic;
  String? lastData;

  @override
  Future<bool> publishToPubsub(String topic, String data) async {
    lastTopic = topic;
    lastData = data;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSecureStorageService implements SecureStorageService {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('SyncService publishes to IPFS', () async {
    final ipfs = FakeIpfsService();
    final storage = FakeSecureStorageService();

    final container = ProviderContainer(
      overrides: [
        ipfsServiceProvider.overrideWithValue(ipfs),
        secureStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    final syncService = container.read(syncServiceProvider);
    await syncService.init();

    await syncService.queueOperation(
      collectionId: 'test-col',
      operation: 'update',
      data: {'foo': 'bar'},
    );

    expect(ipfs.lastTopic, '/alexandria/sync/v1/test-col');
    final decoded = jsonDecode(ipfs.lastData!);
    expect(decoded['foo'], 'bar');
  });
}
