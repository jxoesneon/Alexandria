import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/headless_sdk.dart';

void main() {
  group('HeadlessSdk JSON-RPC 2.0 Tests', () {
    late ProviderContainer container;
    late HeadlessSdk sdk;

    setUp(() {
      container = ProviderContainer();
      sdk = container.read(headlessSdkProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('daemon start and stop lifecycle', () async {
      expect(sdk.isRunning, isFalse);
      await sdk.startDaemon();
      expect(sdk.isRunning, isTrue);
      await sdk.stopDaemon();
      expect(sdk.isRunning, isFalse);
    });

    test('executes alexandria.status RPC method', () async {
      final req = jsonEncode({
        'jsonrpc': '2.0',
        'method': 'alexandria.status',
        'params': {},
        'id': 1
      });
      final res = await sdk.executeRpc(req);

      expect(res['jsonrpc'], equals('2.0'));
      expect(res['id'], equals(1));
      expect(res['result']['status'], equals('stopped'));
    });

    test('handles unknown RPC methods with error code', () async {
      final req = jsonEncode({
        'jsonrpc': '2.0',
        'method': 'invalid.method',
        'params': {},
        'id': 2
      });
      final res = await sdk.executeRpc(req);

      expect(res['error'], isNotNull);
      expect(res['error']['code'], equals(-32603));
    });
  });
}
