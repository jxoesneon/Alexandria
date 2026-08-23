import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/web_node_service.dart';

void main() {
  group('WebNodeService (Browser PWA) Tests', () {
    late ProviderContainer container;
    late WebNodeService webNode;

    setUp(() {
      container = ProviderContainer();
      webNode = container.read(webNodeServiceProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('initializes and manages browser peer lifecycle', () async {
      expect(webNode.state, equals(WebNodeState.uninitialized));
      await webNode.initializeWebNode();
      expect(webNode.state, equals(WebNodeState.connected));

      webNode.registerPeer('webrtc_peer_1');
      expect(webNode.connectedPeers, contains('webrtc_peer_1'));

      webNode.deregisterPeer('webrtc_peer_1');
      expect(webNode.connectedPeers.isEmpty, isTrue);

      await webNode.terminate();
      expect(webNode.state, equals(WebNodeState.disconnected));
    });

    test('stores and retrieves blocks in IndexedDbBlockStore', () async {
      final data = Uint8List.fromList('Browser PWA Block Data'.codeUnits);
      final cid = await webNode.preserveInBrowser(data);

      expect(cid.isNotEmpty, isTrue);
      final retrieved = await webNode.retrieveFromBrowser(cid);
      expect(retrieved, equals(data));
    });
  });
}
