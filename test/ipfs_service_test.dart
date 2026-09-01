import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/ipfs_service.dart';

void main() {
  group('IpfsService (dart_ipfs ^1.11.7 Engine) Tests', () {
    late ProviderContainer container;
    late IpfsService ipfs;

    setUp(() {
      container = ProviderContainer();
      ipfs = container.read(ipfsServiceProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('starts and stops IPFS node lifecycle', () async {
      expect(ipfs.isStarted, isFalse);
      await ipfs.startNode();
      expect(ipfs.isStarted, isTrue);
      await ipfs.stopNode();
      expect(ipfs.isStarted, isFalse);
    });

    test('adds file, retrieves stream, pins and unpins CIDs', () async {
      final payload =
          Uint8List.fromList('Alexandria P2P Knowledge Block'.codeUnits);
      final cid = await ipfs.addFile(payload);
      expect(cid.startsWith('b'), isTrue);

      final retrieved = await ipfs.getFile(cid).first;
      expect(retrieved, equals(payload));

      final pinRes = await ipfs.pinCid(cid);
      expect(pinRes, isTrue);

      final providers = await ipfs.findProviders(cid);
      expect(providers, contains('peer_local_self'));

      final unpinRes = await ipfs.unpinCid(cid);
      expect(unpinRes, isTrue);
    });

    test('handles pubsub publishing and garbage collection', () async {
      var received = false;
      ipfs.pubsubStream.listen((msg) {
        if (msg['topic'] == '/alexandria/test') received = true;
      });

      await ipfs.publishToPubsub('/alexandria/test', 'hello');
      await Future.delayed(const Duration(milliseconds: 20));
      expect(received, isTrue);

      final gc = await ipfs.runGc();
      expect(gc, isTrue);
    });
  });
}
