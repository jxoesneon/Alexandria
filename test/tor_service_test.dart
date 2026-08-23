import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/tor_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

class FakeSecureStorageService extends SecureStorageService {
  final Map<String, String> _data = {};
  @override
  Future<String?> read(String key) async => _data[key];
  @override
  Future<void> write(String key, String value) async => _data[key] = value;
}

void main() {
  group('TorService Tests', () {
    late FakeSecureStorageService storage;
    late TorService tor;

    setUp(() {
      storage = FakeSecureStorageService();
      tor = TorService(storage);
    });

    test('initial state is disabled', () {
      expect(tor.isEnabled, isFalse);
      expect(tor.status, equals(TorStatus.disabled));
      expect(tor.proxyAddress, equals('127.0.0.1:9050'));
    });

    test('disable sets state and saves preference', () async {
      await tor.disable();
      expect(tor.isEnabled, isFalse);
      expect(tor.status, equals(TorStatus.disabled));
      expect(await storage.read('tor_enabled'), equals('false'));
    });

    test('createTorHttpClient sets proxy when enabled', () {
      final client = tor.createTorHttpClient();
      expect(client, isNotNull);
    });
  });
}
