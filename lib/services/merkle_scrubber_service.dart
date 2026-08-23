import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'erasure_coding_service.dart';

final merkleScrubberServiceProvider = Provider((ref) => MerkleScrubberService(ref));

class MerkleScrubReport {
  final String blockId;
  final int totalShards;
  final int intactShards;
  final int corruptedShards;
  final bool wasRepaired;
  final DateTime timestamp;

  MerkleScrubReport({
    required this.blockId,
    required this.totalShards,
    required this.intactShards,
    required this.corruptedShards,
    required this.wasRepaired,
    required this.timestamp,
  });
}

class MerkleScrubberService {
  final Ref _ref;
  Timer? _scrubTimer;
  final Map<String, ErasureBlock> _monitoredBlocks = {};

  MerkleScrubberService(this._ref);

  void registerBlock(ErasureBlock block) {
    _monitoredBlocks[block.blockId] = block;
  }

  void unregisterBlock(String blockId) {
    _monitoredBlocks.remove(blockId);
  }

  Future<MerkleScrubReport> scrubBlock(String blockId) async {
    final block = _monitoredBlocks[blockId];
    if (block == null) throw ArgumentError('Block $blockId is not monitored');

    final intact = <ErasureShard>[];
    final corrupted = <ErasureShard>[];

    for (final shard in block.shards) {
      if (shard.verifyChecksum()) {
        intact.add(shard);
      } else {
        corrupted.add(shard);
      }
    }

    var wasRepaired = false;
    if (corrupted.isNotEmpty && intact.length >= block.k) {
      final erasureService = _ref.read(erasureCodingServiceProvider);
      final repairedBlock = erasureService.repairShards(block: block, availableShards: intact);
      _monitoredBlocks[blockId] = repairedBlock;
      wasRepaired = true;
    }

    return MerkleScrubReport(
      blockId: blockId,
      totalShards: block.shards.length,
      intactShards: intact.length,
      corruptedShards: corrupted.length,
      wasRepaired: wasRepaired,
      timestamp: DateTime.now(),
    );
  }

  Future<List<MerkleScrubReport>> scrubAll() async {
    final reports = <MerkleScrubReport>[];
    for (final blockId in _monitoredBlocks.keys) {
      reports.add(await scrubBlock(blockId));
    }
    return reports;
  }

  void startPeriodicScrubbing({Duration cadence = const Duration(hours: 1)}) {
    _scrubTimer?.cancel();
    _scrubTimer = Timer.periodic(cadence, (_) => scrubAll());
  }

  void stopScrubbing() {
    _scrubTimer?.cancel();
  }
}
