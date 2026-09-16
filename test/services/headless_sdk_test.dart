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
      // Round-3 fix: mutating RPCs need a running daemon + bearer token.
      await sdk.startDaemon();
      final token = sdk.rpcAuthToken;
      // pinCid is honest now (round-2 fix): it only succeeds for content
      // actually held by the node, so import a block first to get a real
      // retrievable CID.
      final importRes = await sdk.executeRpc(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'alexandria.import',
        'params': {
          'dataBase64': base64Encode(utf8.encode('pin me')),
          'authToken': token,
        },
        'id': 1,
      }));
      final cid = importRes['result']['cid'] as String;

      final pinReq = jsonEncode({
        'jsonrpc': '2.0',
        'method': 'alexandria.pin',
        'params': {'cid': cid, 'authToken': token},
        'id': 2,
      });
      final pinRes = await sdk.executeRpc(pinReq);
      expect(pinRes['error'], isNull);
      expect(pinRes['result'], isTrue);

      final unpinReq = jsonEncode({
        'jsonrpc': '2.0',
        'method': 'alexandria.unpin',
        'params': {'cid': cid, 'authToken': token},
        'id': 3,
      });
      final unpinRes = await sdk.executeRpc(unpinReq);
      expect(unpinRes['result'], isTrue);
    });

    test('alexandria.import returns cid and size for base64 payload', () async {
      await sdk.startDaemon();
      final bytes = utf8.encode('hello headless sdk');
      final encoded = base64Encode(bytes);
      final req = jsonEncode({
        'jsonrpc': '2.0',
        'method': 'alexandria.import',
        'params': {'dataBase64': encoded, 'authToken': sdk.rpcAuthToken},
        'id': 4,
      });
      final res = await sdk.executeRpc(req);

      expect(res['error'], isNull);
      expect(res['result']['sizeBytes'], bytes.length);
      expect(res['result']['cid'], isA<String>());
    });

    test('alexandria.verify reports health for an imported cid', () async {
      await sdk.startDaemon();
      final bytes = utf8.encode('health check');
      final importRes = await sdk.executeRpc(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'alexandria.import',
        'params': {
          'dataBase64': base64Encode(bytes),
          'authToken': sdk.rpcAuthToken,
        },
        'id': 5,
      }));
      final cid = importRes['result']['cid'] as String;

      final verifyRes = await sdk.executeRpc(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'alexandria.verify',
        'params': {'cid': cid, 'authToken': sdk.rpcAuthToken},
        'id': 6,
      }));

      expect(verifyRes['error'], isNull);
      expect(verifyRes['result']['cid'], cid);
      expect(verifyRes['result']['isHealthy'], isFalse);
      // Honest provider accounting (round-2 fix): only the local node
      // itself is reported — providers are no longer fabricated.
      expect(verifyRes['result']['providerCount'], 1);
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

    group('bearer token gate (constant-time compare)', () {
      test('rejects a near-miss token differing only in the last char',
          () async {
        await sdk.startDaemon();
        final token = sdk.rpcAuthToken!;
        // Flip the final character — a short-circuiting == would have
        // differed only in timing; the gate must simply reject.
        final last = token[token.length - 1];
        final wrong = token.substring(0, token.length - 1) +
            (last == '0' ? '1' : '0');
        final res = await sdk.executeRpc(jsonEncode({
          'jsonrpc': '2.0',
          'method': 'alexandria.pin',
          'params': {'cid': 'bafy', 'authToken': wrong},
          'id': 10,
        }));
        expect(res['error'], isNotNull);
        expect(res['error']['message'], contains('unauthorized'));
      });

      test('rejects wrong-length and non-string tokens', () async {
        await sdk.startDaemon();
        for (final presented in [
          sdk.rpcAuthToken!.substring(0, 8), // prefix only
          '${sdk.rpcAuthToken}ff', // too long
          12345, // non-string
          true,
        ]) {
          final res = await sdk.executeRpc(jsonEncode({
            'jsonrpc': '2.0',
            'method': 'alexandria.pin',
            'params': {'cid': 'bafy', 'authToken': presented},
            'id': 11,
          }));
          expect(res['error'], isNotNull,
              reason: 'token $presented was accepted');
        }
      });

      test('top-level authToken field is also accepted and compared '
          'constant-time', () async {
        await sdk.startDaemon();
        final ok = await sdk.executeRpc(jsonEncode({
          'jsonrpc': '2.0',
          'method': 'alexandria.pin',
          'params': {'cid': 'bafy_nonexistent'},
          'authToken': sdk.rpcAuthToken,
          'id': 12,
        }));
        // Authorized (passes the gate); pin fails honestly on missing
        // content but the auth gate is what we are probing — the call
        // must reach dispatch rather than return 'unauthorized'.
        expect(
          ok['error']?['message'] ?? '',
          isNot(contains('unauthorized')),
        );

        final bad = await sdk.executeRpc(jsonEncode({
          'jsonrpc': '2.0',
          'method': 'alexandria.pin',
          'params': {'cid': 'bafy_nonexistent'},
          'authToken': 'deadbeef',
          'id': 13,
        }));
        expect(bad['error']['message'], contains('unauthorized'));
      });
    });
  });
}
