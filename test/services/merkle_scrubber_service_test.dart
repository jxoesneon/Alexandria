import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/erasure_coding_service.dart';
import 'package:alexandria/services/merkle_scrubber_service.dart';

class _FakeErasureCodingService extends ErasureCodingService {
  @override
  ErasureBlock repairShards({
    required ErasureBlock block,
    required List<ErasureShard> availableShards,
  }) {
    return block;
  }
}

ErasureBlock _makeBlock({
  required String blockId,
  required int k,
  required int m,
  required List<bool> valid,
}) {
  final shardSize = 4;
  final dataShards = List.generate(k, (i) => Uint8List.fromList([i, 1, 2, 3]));
  final parityShards =
      List.generate(m, (i) => Uint8List.fromList([i + k, 1, 2, 3]));
  final all = <ErasureShard>[];

  for (var i = 0; i < dataShards.length; i++) {
    all.add(ErasureShard(
      index: i,
      isParity: false,
      data: dataShards[i],
      checksum: valid[i] ? sha256.convert(dataShards[i]).toString() : 'bad',
    ));
  }

  for (var i = 0; i < parityShards.length; i++) {
    all.add(ErasureShard(
      index: k + i,
      isParity: true,
      data: parityShards[i],
      checksum:
          valid[k + i] ? sha256.convert(parityShards[i]).toString() : 'bad',
    ));
  }

  return ErasureBlock(
    blockId: blockId,
    originalSize: k * shardSize,
    k: k,
    m: m,
    shardSize: shardSize,
    shards: all,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MerkleScrubberService', () {
    late ProviderContainer container;
    late MerkleScrubberService service;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          erasureCodingServiceProvider
              .overrideWithValue(_FakeErasureCodingService()),
        ],
      );
      service = container.read(merkleScrubberServiceProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('scrubs an intact block without repairing', () async {
      final block = _makeBlock(
        blockId: 'b1',
        k: 2,
        m: 1,
        valid: const [true, true, true],
      );
      service.registerBlock(block);

      final report = await service.scrubBlock('b1');

      expect(report.blockId, 'b1');
      expect(report.totalShards, 3);
      expect(report.intactShards, 3);
      expect(report.corruptedShards, 0);
      expect(report.wasRepaired, isFalse);
    });

    test('repairs a corrupted block when enough shards are intact', () async {
      final block = _makeBlock(
        blockId: 'b2',
        k: 2,
        m: 1,
        valid: const [true, true, false],
      );
      service.registerBlock(block);

      final report = await service.scrubBlock('b2');

      expect(report.totalShards, 3);
      expect(report.intactShards, 2);
      expect(report.corruptedShards, 1);
      expect(report.wasRepaired, isTrue);
    });

    test('does not repair when too few shards are intact', () async {
      final block = _makeBlock(
        blockId: 'b3',
        k: 2,
        m: 0,
        valid: const [true, false],
      );
      service.registerBlock(block);

      final report = await service.scrubBlock('b3');

      expect(report.totalShards, 2);
      expect(report.intactShards, 1);
      expect(report.corruptedShards, 1);
      expect(report.wasRepaired, isFalse);
    });

    test('throws for an unmonitored block', () async {
      expect(
        () => service.scrubBlock('missing'),
        throwsArgumentError,
      );
    });

    test('scrubs all registered blocks', () async {
      service.registerBlock(_makeBlock(
        blockId: 'b4',
        k: 1,
        m: 0,
        valid: const [true],
      ));
      service.registerBlock(_makeBlock(
        blockId: 'b5',
        k: 1,
        m: 0,
        valid: const [true],
      ));

      final reports = await service.scrubAll();

      expect(reports, hasLength(2));
      expect(reports.map((r) => r.blockId), containsAll(['b4', 'b5']));
    });

    test('start and stop periodic scrubbing', () async {
      service.registerBlock(_makeBlock(
        blockId: 'b6',
        k: 1,
        m: 0,
        valid: const [true],
      ));

      service.startPeriodicScrubbing(cadence: const Duration(hours: 1));
      service.stopScrubbing();

      expect(service, isNotNull);
    });
  });
}
