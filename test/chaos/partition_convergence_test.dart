import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CRDT Partition Convergence Tests', () {
    test('LWW-Element-Set resolves split-brain concurrent additions', () {
      final partitionA = {'doc_1': 100, 'doc_2': 200};
      final partitionB = {'doc_2': 250, 'doc_3': 300};

      // Merge partitions
      final merged = <String, int>{};
      for (final k in {...partitionA.keys, ...partitionB.keys}) {
        final tA = partitionA[k] ?? -1;
        final tB = partitionB[k] ?? -1;
        merged[k] = tA > tB ? tA : tB;
      }

      expect(merged['doc_1'], equals(100));
      expect(merged['doc_2'], equals(250)); // Higher timestamp wins
      expect(merged['doc_3'], equals(300));
    });
  });
}
