import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/headless_sdk.dart';

void main() {
  group('HeadlessSdk service coverage', () {
    late ProviderContainer container;
    late HeadlessSdk sdk;

    setUp(() {
      container = ProviderContainer();
      sdk = container.read(headlessSdkProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('DaemonConfig uses provided overrides', () {
      const config = DaemonConfig(
        rpcPort: 8080,
        host: '0.0.0.0',
        maxStorageMb: 1024,
        enableAutoHealing: false,
        dataDirectory: '/tmp/daemon',
      );
      expect(config.rpcPort, 8080);
      expect(config.host, '0.0.0.0');
      expect(config.maxStorageMb, 1024);
      expect(config.enableAutoHealing, isFalse);
      expect(config.dataDirectory, '/tmp/daemon');
    });

    test('HeadlessSdk can be constructed with a custom config', () {
      final customContainer = ProviderContainer(
        overrides: [
          headlessSdkProvider.overrideWith(
            (ref) =>
                HeadlessSdk(ref, config: const DaemonConfig(rpcPort: 7777)),
          ),
        ],
      );
      addTearDown(customContainer.dispose);
      final custom = customContainer.read(headlessSdkProvider);
      expect(custom.config.rpcPort, 7777);
    });

    test('startDaemon and stopDaemon update isRunning', () async {
      expect(sdk.isRunning, isFalse);
      await sdk.startDaemon();
      expect(sdk.isRunning, isTrue);
      await sdk.stopDaemon();
      expect(sdk.isRunning, isFalse);
    });

    test('alexandria.status reports running state and counters', () async {
      await sdk.startDaemon();
      final req = jsonEncode({
        'jsonrpc': '2.0',
        'method': 'alexandria.status',
        'params': {},
        'id': 1,
      });
      final res = await sdk.executeRpc(req);

      expect(res['jsonrpc'], '2.0');
      expect(res['id'], 1);
      expect(res['result']['status'], 'running');
      expect(res['result']['rpcPort'], 9099);
      expect(res['result']['totalQueriesServed'], 1);
      expect(res['result']['uptimeSeconds'], greaterThanOrEqualTo(0));
    });

    test('alexandria.pin and alexandria.unpin succeed with valid cid',
        () async {
      final pinReq = jsonEncode({
        'jsonrpc': '2.0',
        'method': 'alexandria.pin',
        'params': {'cid': 'bafkreihdwdcefgh4dqkjv67la6'},
        'id': 2,
      });
      final pinRes = await sdk.executeRpc(pinReq);
      expect(pinRes['error'], isNull);
      expect(pinRes['result'], isTrue);

      final unpinReq = jsonEncode({
        'jsonrpc': '2.0',
        'method': 'alexandria.unpin',
        'params': {'cid': 'bafkreihdwdcefgh4dqkjv67la6'},
        'id': 3,
      });
      final unpinRes = await sdk.executeRpc(unpinReq);
      expect(unpinRes['result'], isTrue);
    });

    test('alexandria.import returns cid and size for base64 payload', () async {
      final bytes = utf8.encode('hello headless sdk');
      final encoded = base64Encode(bytes);
      final req = jsonEncode({
        'jsonrpc': '2.0',
        'method': 'alexandria.import',
        'params': {'dataBase64': encoded},
        'id': 4,
      });
      final res = await sdk.executeRpc(req);

      expect(res['error'], isNull);
      expect(res['result']['sizeBytes'], bytes.length);
      expect(res['result']['cid'], isA<String>());
    });

    test('alexandria.verify reports health for an imported cid', () async {
      final bytes = utf8.encode('health check');
      final importRes = await sdk.executeRpc(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'alexandria.import',
        'params': {'dataBase64': base64Encode(bytes)},
        'id': 5,
      }));
      final cid = importRes['result']['cid'] as String;

      final verifyRes = await sdk.executeRpc(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'alexandria.verify',
        'params': {'cid': cid},
        'id': 6,
      }));

      expect(verifyRes['error'], isNull);
      expect(verifyRes['result']['cid'], cid);
      expect(verifyRes['result']['isHealthy'], isFalse);
      expect(verifyRes['result']['providerCount'], 2);
    });

    test('returns error when required RPC parameters are missing', () async {
      final cases = [
        ('alexandria.pin', {}),
        ('alexandria.unpin', {}),
        ('alexandria.import', {}),
        ('alexandria.verify', {}),
      ];

      for (final c in cases) {
        final res = await sdk.executeRpc(jsonEncode({
          'jsonrpc': '2.0',
          'method': c.$1,
          'params': c.$2,
          'id': 99,
        }));
        expect(res['error'], isNotNull, reason: '${c.$1} should error');
        expect(res['error']['code'], -32603);
      }
    });

    test('returns error for malformed JSON input', () async {
      final res = await sdk.executeRpc('not-json');
      expect(res['error'], isNotNull);
      expect(res['error']['code'], -32603);
    });

    test('returns error for unknown methods', () async {
      final res = await sdk.executeRpc(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'alexandria.unknown',
        'params': {},
        'id': 7,
      }));
      expect(res['error'], isNotNull);
      expect(res['error']['code'], -32603);
    });
  });
}
