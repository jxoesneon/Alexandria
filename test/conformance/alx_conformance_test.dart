import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/cid_service.dart';
import 'package:alexandria/services/erasure_coding_service.dart';

void main() {
  group('ALX Specification Conformance Harness', () {
    test('Conforms to ALX-001 Multihash Standard', () {
      final cidService = CidService();
      final data = Uint8List.fromList('Alexandria Protocol Standard'.codeUnits);
      final cid = cidService.computeCid(data);

      expect(cid.version, 1);
      expect(cid.codec, 0x55);
      expect(cid.hashFunction, 0x12);
      expect(cid.toBase32().startsWith('b'), isTrue);
    });

    test('Conforms to ALX-003 Erasure Reconstruction Threshold', () {
      final erasure = ErasureCodingService();
      final data = Uint8List.fromList('ALX-003 Conformance Test Data'.codeUnits);
      final block = erasure.encode(blockId: 'alx_003', data: data, k: 3, m: 2);

      expect(block.shards.length, 5);
      final decoded = erasure.decode(block: block, availableShards: block.shards.sublist(1, 4));
      expect(decoded, equals(data));
    });
  });
}
