import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:alexandria/services/tor_service.dart';

class _FakeSecureStorageService extends SecureStorageService {
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
  group('TorService (test/services)', () {
    late _FakeSecureStorageService storage;
    late TorService tor;

    setUp(() {
      storage = _FakeSecureStorageService();
      tor = TorService(storage);
    });

    test('initial state and proxy getters', () {
      expect(tor.status, equals(TorStatus.disabled));
      expect(tor.isEnabled, isFalse);
      expect(tor.proxyHost, equals('127.0.0.1'));
      expect(tor.proxyPort, equals(9050));
      expect(tor.proxyAddress, equals('127.0.0.1:9050'));
    });

    test('setProxy stores host and port, rejecting invalid input', () async {
      await tor.setProxy('192.168.1.1', 9051);
      expect(tor.proxyHost, equals('192.168.1.1'));
      expect(tor.proxyPort, equals(9051));
      expect(await storage.read('tor_host'), equals('192.168.1.1'));
      expect(await storage.read('tor_port'), equals('9051'));

      // Proxy host/port are validated now (round-2 hardening): empty or
      // malformed hosts and out-of-range ports are rejected outright
      // instead of silently flowing into Socket.connect / proxy strings.
      await expectLater(tor.setProxy('', 9090), throwsArgumentError);
      await expectLater(tor.setProxy('bad host;', 9050), throwsArgumentError);
      await expectLater(tor.setProxy('127.0.0.1', 0), throwsArgumentError);
      await expectLater(tor.setProxy('127.0.0.1', 70000), throwsArgumentError);
      // Rejected input must not clobber the previously stored proxy.
      expect(tor.proxyHost, equals('192.168.1.1'));
    });

    test('disable saves false preference and resets status', () async {
      await tor.disable();
      expect(tor.isEnabled, isFalse);
      expect(tor.status, equals(TorStatus.disabled));
      expect(await storage.read('tor_enabled'), equals('false'));
    });

    test('enable returns true when proxy is reachable', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      await tor.setProxy('127.0.0.1', port);
      final result = await tor.enable();

      expect(result, isTrue);
      expect(tor.isEnabled, isTrue);
      expect(tor.status, equals(TorStatus.connected));
      expect(await storage.read('tor_enabled'), equals('true'));

      await server.close();
    });

    test('enable returns false when proxy is not reachable', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();

      await tor.setProxy('127.0.0.1', port);
      final result = await tor.enable();

      expect(result, isFalse);
      expect(tor.isEnabled, isFalse);
      expect(tor.status, equals(TorStatus.error));
    });

    test('init restores stored preferences and enables tor when requested',
        () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      await storage.write('tor_enabled', 'true');
      await storage.write('tor_host', '127.0.0.1');
      await storage.write('tor_port', port.toString());

      await tor.init();

      expect(tor.proxyPort, equals(port));
      expect(tor.isEnabled, isTrue);
      expect(tor.status, equals(TorStatus.connected));

      await server.close();
    });

    test('createTorHttpClient configures proxy only when enabled', () async {
      final client = tor.createTorHttpClient();
      addTearDown(client.close);
      expect(client, isNotNull);

      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      await tor.setProxy('127.0.0.1', server.port);
      await tor.enable();

      final configured = tor.createTorHttpClient();
      addTearDown(configured.close);
      expect(configured, isNotNull);
      expect(configured.connectionTimeout, equals(const Duration(seconds: 30)));

      await server.close();
    });

    test('provider uses overridden fake secure storage', () {
      final container = ProviderContainer(overrides: [
        secureStorageServiceProvider.overrideWith((ref) => storage),
      ]);
      addTearDown(container.dispose);

      final svc = container.read(torServiceProvider);
      expect(svc, isA<TorService>());
      expect(svc.proxyAddress, equals('127.0.0.1:9050'));
    });

    test('torStatusProvider returns default disabled state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(torStatusProvider), equals(TorStatus.disabled));
    });
  });
}
