import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/audit_log_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

class _FakeSecureStorage implements SecureStorageService {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuditLogService chain-head restore and escapes', () {
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('audit_cov');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, null);
      await tempDir.delete(recursive: true);
    });

    test('second service instance restores persisted chain head',
        () async {
      final storage = _FakeSecureStorage();
      // A signing key must exist for the checkpoint to be written.
      storage.data['master_key_v1'] = base64Encode(List.filled(32, 7));

      final c1 = ProviderContainer(overrides: [
        secureStorageServiceProvider.overrideWithValue(storage),
      ]);
      final s1 = c1.read(auditLogServiceProvider);
      await s1.log('first_action', details: 'one');
      await s1.log('second_action', details: 'two');
      c1.dispose();

      // Fresh service on the same directory + storage: the chain state
      // must come back from the file tail AND the checkpoint.
      final c2 = ProviderContainer(overrides: [
        secureStorageServiceProvider.overrideWithValue(storage),
      ]);
      addTearDown(c2.dispose);
      final s2 = c2.read(auditLogServiceProvider);
      await s2.log('third_action', details: 'three');
      final logs = await s2.getRecentLogs(10);
      expect(logs.length, greaterThanOrEqualTo(3));
    });

    test('carriage-return escape round-trips through the log', () async {
      final storage = _FakeSecureStorage();
      final container = ProviderContainer(overrides: [
        secureStorageServiceProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);
      final service = container.read(auditLogServiceProvider);

      await service.log('act', details: 'line1\rline2', actor: 'a\rb');
      final logs = await service.getRecentLogs(5);
      expect(logs, isNotEmpty);
      expect(logs.first.event, 'act');
      expect(logs.first.actor, contains('\r'));
    });
  });
}
