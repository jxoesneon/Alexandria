import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/secure_storage_service.dart';

void main() {
  group('SecureStorageService', () {
    const channel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    late ProviderContainer container;
    final store = <String, String>{};

    setUp(() {
      store.clear();
      container = ProviderContainer();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments as Map<dynamic, dynamic>;
        final key = args['key'] as String?;
        switch (call.method) {
          case 'read':
            return store[key];
          case 'write':
            store[key!] = args['value'] as String;
            return null;
          case 'delete':
            store.remove(key);
            return null;
          case 'deleteAll':
            store.clear();
            return null;
          case 'containsKey':
            return store.containsKey(key);
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      container.dispose();
    });

    test('read returns null when key is absent', () async {
      final service = container.read(secureStorageServiceProvider);
      expect(await service.read('missing'), isNull);
    });

    test('write then read returns the stored value', () async {
      final service = container.read(secureStorageServiceProvider);
      await service.write('key1', 'value1');
      expect(await service.read('key1'), equals('value1'));
    });

    test('delete removes a key', () async {
      final service = container.read(secureStorageServiceProvider);
      await service.write('key2', 'value2');
      expect(await service.containsKey('key2'), isTrue);
      await service.delete('key2');
      expect(await service.containsKey('key2'), isFalse);
      expect(await service.read('key2'), isNull);
    });

    test('deleteAll clears all values', () async {
      final service = container.read(secureStorageServiceProvider);
      await service.write('a', '1');
      await service.write('b', '2');
      await service.deleteAll();
      expect(await service.read('a'), isNull);
      expect(await service.read('b'), isNull);
    });

    test('containsKey returns false for missing key', () async {
      final service = container.read(secureStorageServiceProvider);
      expect(await service.containsKey('absent'), isFalse);
    });
  });
}
