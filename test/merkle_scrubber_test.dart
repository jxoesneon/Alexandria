import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/erasure_coding_service.dart';
import 'package:alexandria/services/merkle_scrubber_service.dart';

void main() {
  group('MerkleScrubberService Tests', () {
    late ProviderContainer container;
    late ErasureCodingService erasureService;
    late MerkleScrubberService scrubber;

    setUp(() {
      container = ProviderContainer();
      erasureService = container.read(erasureCodingServiceProvider);
      scrubber = container.read(merkleScrubberServiceProvider);
    });

    tearDown(() {
      scrubber.stopScrubbing();
      container.dispose();
    });

    test('scrubs pristine block and reports 0 corrupted shards', () async {
      final data = Uint8List.fromList('Pristine Merkle Tree Block'.codeUnits);
      final block =
          erasureService.encode(blockId: 'blk_scrub_1', data: data, k: 3, m: 2);

      scrubber.registerBlock(block);
      final report = await scrubber.scrubBlock('blk_scrub_1');

      expect(report.corruptedShards, equals(0));
      expect(report.intactShards, equals(5));
      expect(report.wasRepaired, isFalse);
    });
  });
}
