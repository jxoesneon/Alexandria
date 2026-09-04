import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/cid_service.dart';
import 'package:alexandria/services/web_node_service.dart';

class FakeCidService extends CidService {
  @override
  ContentIdentifier computeCid(Uint8List data) {
    return ContentIdentifier(
      version: 1,
      codec: 0x55,
      hashFunction: 0x12,
      digest: Uint8List.fromList(List.filled(32, 7)),
    );
  }
}

void main() {
  group('IndexedDbBlockStore', () {
    test('putBlock, getBlock, hasBlock, and usage', () async {
      final store = IndexedDbBlockStore(maxCapacityBytes: 20);
      final a = Uint8List.fromList(List.filled(12, 1));
      final b = Uint8List.fromList(List.filled(12, 2));

      await store.putBlock('cid-a', a);
      expect(store.currentUsage, equals(12));
      expect(await store.hasBlock('cid-a'), isTrue);
      expect(await store.getBlock('cid-a'), equals(a));

      await store.putBlock('cid-b', b);
      expect(store.currentUsage, equals(12));
      expect(await store.hasBlock('cid-a'), isFalse);
      expect(await store.hasBlock('cid-b'), isTrue);
      expect(await store.getBlock('cid-b'), equals(b));

      await store.putBlock('cid-b', b);
      expect(store.currentUsage, equals(12));
    });

    test('clear resets usage', () async {
      final store = IndexedDbBlockStore(maxCapacityBytes: 20);
      final data = Uint8List.fromList('hello'.codeUnits);
      await store.putBlock('cid-c', data);
      await store.clear();
      expect(store.currentUsage, equals(0));
    });
  });

  group('WebNodeService (test/services)', () {
    late ProviderContainer container;
    late WebNodeService webNode;

    setUp(() {
      container = ProviderContainer(overrides: [
        cidServiceProvider.overrideWith((ref) => FakeCidService()),
      ]);
      webNode = container.read(webNodeServiceProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state and provider wiring', () {
      expect(container.read(webNodeServiceProvider), isA<WebNodeService>());
      expect(webNode.state, equals(WebNodeState.uninitialized));
      expect(webNode.connectedPeers, isEmpty);
    });

    test('initialize and terminate manage lifecycle', () async {
      await webNode.initializeWebNode();
      expect(webNode.state, equals(WebNodeState.connected));

      webNode.registerPeer('p1');
      expect(webNode.connectedPeers, contains('p1'));

      webNode.deregisterPeer('p1');
      expect(webNode.connectedPeers, isEmpty);

      await webNode.terminate();
      expect(webNode.state, equals(WebNodeState.disconnected));
      expect(webNode.connectedPeers, isEmpty);
    });

    test('preserveInBrowser and retrieveFromBrowser roundtrip', () async {
      final data = Uint8List.fromList('Browser PWA data'.codeUnits);
      final cid = await webNode.preserveInBrowser(data);

      expect(cid, isNotEmpty);
      final retrieved = await webNode.retrieveFromBrowser(cid);
      expect(retrieved, equals(data));
    });

    test('blockStore capacity is shared with the service', () {
      expect(webNode.blockStore, isA<IndexedDbBlockStore>());
    });
  });
}
