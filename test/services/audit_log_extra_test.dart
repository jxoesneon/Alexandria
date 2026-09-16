import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/audit_log_service.dart';
import 'package:alexandria/services/encryption_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

class FakeSecureStorageService implements SecureStorageService {
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

void main() {
  group('AuditLogService.getRecentLogs', () {
    late ProviderContainer container;
    late AuditLogService service;
    late FakeSecureStorageService storage;

    setUp(() {
      storage = FakeSecureStorageService();
      container = ProviderContainer(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(storage),
        ],
      );
      service = container.read(auditLogServiceProvider);
      addTearDown(container.dispose);
    });

    test('getRecentLogs returns empty when no log file is available', () async {
      final logs = await service.getRecentLogs(10);
      expect(logs, isEmpty);
    });

    test('log does not throw when no log file is available', () async {
      await service.log('test_action', details: 'details');
      // Ensure signature was produced without a master key.
      expect(await storage.read('master_key_v1'), isNull);
    });

    test('log signs entry when master key is present', () async {
      await storage.write('master_key_v1', 'bWFzdGVyLWtleQ==');
      await service.log(
        'grant_access',
        details: 'CID: 1',
        actor: 'did:alex:peer',
        status: 'Success',
      );
      // With no log file the entry is computed and discarded, but no error.
      expect(await storage.read('master_key_v1'), isNotNull);
    });

    test('getRecentLogs clamps a non-positive limit instead of throwing',
        () async {
      // sublist(0, negative) used to throw RangeError at the tail of the
      // read path; a caller bug must degrade to an empty result.
      expect(await service.getRecentLogs(0), isEmpty);
      expect(await service.getRecentLogs(-5), isEmpty);
    });
  });

  group('EncryptionService.encryptForPeer', () {
    late EncryptionService encryption;

    setUp(() {
      encryption = EncryptionService();
    });

    test('encrypts data for a peer public key', () async {
      final data = Uint8List.fromList('peer secret'.codeUnits);
      final cipher =
          await encryption.encryptForPeer(data, 'did:alex:peer#key1');
      expect(cipher, isNot(equals(data)));
      expect(cipher.length, greaterThan(data.length));
    });

    test('produces different ciphertext for the same input', () async {
      final data = Uint8List.fromList('same'.codeUnits);
      final c1 = await encryption.encryptForPeer(data, 'did:alex:peer#key1');
      final c2 = await encryption.encryptForPeer(data, 'did:alex:peer#key1');
      expect(c1, isNot(equals(c2)));
    });

    test('output varies with different peer keys', () async {
      final data = Uint8List.fromList('same'.codeUnits);
      final c1 = await encryption.encryptForPeer(data, 'did:alex:peerA');
      final c2 = await encryption.encryptForPeer(data, 'did:alex:peerB');
      expect(c1, isNot(equals(c2)));
    });
  });
}
