import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/erasure_coding_service.dart';
import 'package:alexandria/services/merkle_scrubber_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  group('Byzantine Fault & Swarm Attack Resilience', () {
    test('detects tampered Cauchy shard checksums and reconstructs data', () {
      final service = ErasureCodingService();
      final original = Uint8List.fromList('Mission Critical Preservation Data'.codeUnits);
      final block = service.encode(blockId: 'byzantine_1', data: original, k: 4, m: 2);

      // Tamper with shard 0
      final tamperedData = Uint8List.fromList(block.shards[0].data);
      tamperedData[0] ^= 0xFF; // Bit flip
      final tamperedShard = ErasureShard(
        index: 0,
        isParity: false,
        data: tamperedData,
        checksum: block.shards[0].checksum, // Stale/forged checksum
      );

      final available = [tamperedShard, ...block.shards.sublist(1)];
      final valid = available.where((s) => s.verifyChecksum()).toList();
      expect(valid.length, 5); // 5 out of 6 valid

      final recovered = service.decode(block: block, availableShards: valid);
      expect(recovered, equals(original));
    });
  });
}
