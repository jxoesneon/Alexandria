import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/audit_log_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

class _FakeSecureStorage implements SecureStorageService {
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
  group('AuditLogService', () {
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    late ProviderContainer container;
    late AuditLogService service;
    late _FakeSecureStorage storage;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('audit_log_test');
      storage = _FakeSecureStorage();
      container = ProviderContainer(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(storage),
        ],
      );
      service = container.read(auditLogServiceProvider);

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
      container.dispose();
      await tempDir.delete(recursive: true);
    });

    test('init is idempotent', () async {
      await service.init();
      final file = File('${tempDir.path}/audit_trail.log');
      expect(await file.exists(), isFalse);
      await service.init();
      expect(await file.exists(), isFalse);
    });

    test('log writes an unverified entry when no master key is set', () async {
      await service.log(
        'access_granted',
        details: 'CID: abc',
        actor: 'did:alex:alice',
      );

      final file = File('${tempDir.path}/audit_trail.log');
      final lines = await file.readAsLines();
      expect(lines.length, equals(1));
      final parts = lines.single.split('|');
      expect(parts.length, equals(6));
      expect(parts[3], equals('nosig'));
    });

    test('log writes a signed entry when a master key is set', () async {
      await storage.write(
          'master_key_v1', base64Encode(List<int>.generate(32, (i) => i)));

      await service.log(
        'key_rotation',
        details: 'Rotated master key',
        actor: 'did:alex:guardian',
        status: 'Success',
      );

      final file = File('${tempDir.path}/audit_trail.log');
      final lines = await file.readAsLines();
      expect(lines.length, equals(1));
      final parts = lines.single.split('|');
      expect(parts.length, equals(6));
      expect(parts[3], isNot(equals('nosig')));
    });

    test('getRecentLogs returns entries in reverse order and respects limit',
        () async {
      await service.log('action_1', details: 'd1', actor: 'a1');
      await service.log('action_2', details: 'd2', actor: 'a2');
      await service.log('action_3', details: 'd3', actor: 'a3');

      final logs = await service.getRecentLogs(2);
      expect(logs.length, equals(2));
      expect(logs[0].event, equals('action_3'));
      expect(logs[1].event, equals('action_2'));
      expect(logs[0].actor, equals('a3'));
      expect(logs[1].actor, equals('a2'));
    });

    test('getRecentLogs falls back to details when actor is empty', () async {
      await service.log('no_actor', details: 'fallback details');

      final logs = await service.getRecentLogs(1);
      expect(logs.length, equals(1));
      expect(logs.single.actor, equals('fallback details'));
      expect(logs.single.status, equals('Success'));
    });

    test('getRecentLogs marks unsigned four-part entries as Unverified',
        () async {
      final file = File('${tempDir.path}/audit_trail.log');
      await file.writeAsString(
        '2021-01-01T00:00:00.000|orphan_event|some details|nosig\n',
      );

      final logs = await service.getRecentLogs(1);
      expect(logs.length, equals(1));
      expect(logs.single.event, equals('orphan_event'));
      expect(logs.single.actor, equals('some details'));
      expect(logs.single.status, equals('Unverified'));
    });

    test('getRecentLogs skips empty and malformed lines', () async {
      await service.log('valid', details: 'ok', actor: 'actor');

      final file = File('${tempDir.path}/audit_trail.log');
      await file.writeAsString('\n\nnot_enough|parts\n', mode: FileMode.append);

      final logs = await service.getRecentLogs(10);
      expect(logs.length, equals(1));
      expect(logs.single.event, equals('valid'));
    });

    test('getRecentLogs returns success status for signed entries', () async {
      await storage.write(
          'master_key_v1', base64Encode(List<int>.generate(32, (i) => i)));
      await service.log('signed_event',
          details: 'x', actor: 'y', status: 'Success');

      final logs = await service.getRecentLogs(1);
      expect(logs.single.status, equals('Success'));
    });

    test('getRecentLogs returns empty list when path provider is unavailable',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, null);

      final fallbackService = container.read(auditLogServiceProvider);
      await fallbackService.log('orphan');
      final logs = await fallbackService.getRecentLogs(5);
      expect(logs, isEmpty);
    });
  });
}
