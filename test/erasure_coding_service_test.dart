import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/erasure_coding_service.dart';

void main() {
  group('ErasureCodingService Tests', () {
    late ErasureCodingService service;

    setUp(() {
      service = ErasureCodingService();
    });

    test('encodes and decodes data with all shards available', () {
      final original = Uint8List.fromList('Hello Cauchy Reed-Solomon Erasure Coding!'.codeUnits);
      final block = service.encode(blockId: 'blk_1', data: original, k: 4, m: 2);

      expect(block.shards.length, equals(6));
      expect(block.k, equals(4));
      expect(block.m, equals(2));

      final decoded = service.decode(block: block, availableShards: block.shards);
      expect(decoded, equals(original));
    });

    test('decodes data when 2 parity shards are lost', () {
      final original = Uint8List.fromList('Data preservation under high churn mesh!'.codeUnits);
      final block = service.encode(blockId: 'blk_2', data: original, k: 4, m: 2);

      // Keep only first 4 data shards
      final available = block.shards.sublist(0, 4);
      final decoded = service.decode(block: block, availableShards: available);
      expect(decoded, equals(original));
    });

    test('decodes data when 2 data shards are lost (recovering from parity)', () {
      final original = Uint8List.fromList('Recovering from parity shards over Galois Field!'.codeUnits);
      final block = service.encode(blockId: 'blk_3', data: original, k: 4, m: 2);

      // Shards: index 2, 3 (data), 4, 5 (parity)
      final available = [block.shards[2], block.shards[3], block.shards[4], block.shards[5]];
      final decoded = service.decode(block: block, availableShards: available);
      expect(decoded, equals(original));
    });

    test('throws StateError if available valid shards < k', () {
      final original = Uint8List.fromList('Insufficient shards test payload'.codeUnits);
      final block = service.encode(blockId: 'blk_4', data: original, k: 4, m: 2);

      final available = block.shards.sublist(0, 3); // Only 3 shards when 4 are required
      expect(() => service.decode(block: block, availableShards: available), throwsStateError);
    });

    test('repairs missing shards cleanly', () {
      final original = Uint8List.fromList('Peer-to-Peer Resilient Mesh'.codeUnits);
      final block = service.encode(blockId: 'blk_5', data: original, k: 4, m: 2);

      final partialShards = [block.shards[0], block.shards[1], block.shards[4], block.shards[5]];
      final repairedBlock = service.repairShards(block: block, availableShards: partialShards);

      expect(repairedBlock.shards.length, equals(6));
      expect(repairedBlock.shards.every((s) => s.verifyChecksum()), isTrue);
    });
  });
}
