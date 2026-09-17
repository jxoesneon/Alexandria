import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database.dart';
import 'ipfs_service.dart';

final preservationServiceProvider = Provider((ref) => PreservationService(ref));

enum HealthStatus { healthy, endangered, lost, unknown }

class PreservationService {
  final Ref _ref;
  Timer? _timer;
  bool _isRunning = false;

  PreservationService(this._ref) {
    _ref.onDispose(stopBackgroundPreservation);
  }

  static const int healthyPeerThreshold = 3;
  static const int endangeredPeerThreshold = 1;

  bool get isRunning => _isRunning;

  /// Resolves when the startup pin reconcile has finished. Consumers
  /// that read [IpfsService.pinnedCids] at cold start should await this
  /// or they race the reconcile and see an empty pin set.
  Future<void>? get reconciled => _reconcileFuture;
  Future<void>? _reconcileFuture;

  void startBackgroundPreservation() {
    if (_isRunning) return;
    _isRunning = true;
    _reconcileFuture = _reconcileGuarded();
    _timer = Timer.periodic(
        const Duration(minutes: 15), (_) => unawaited(_reconcileGuarded()));
  }

  void stopBackgroundPreservation() {
    _timer?.cancel();
    _isRunning = false;
  }

  Future<HealthStatus> checkContentHealth(String cid) async {
    final ipfs = _ref.read(ipfsServiceProvider);
    final providers = await ipfs.findProviders(cid);
    if (providers.length >= 3) return HealthStatus.healthy;
    if (providers.isNotEmpty) return HealthStatus.endangered;
    return HealthStatus.lost;
  }

  Future<bool> healContent(String cid) async {
    final ipfs = _ref.read(ipfsServiceProvider);
    return await ipfs.pinCid(cid);
  }

  /// Re-pins every locally held version CID the library records as
  /// preserved, healing pin state lost before durable pinning existed
  /// and keeping the engine pin set aligned with the database.
  Future<void> reconcilePinnedContent() async {
    final db = _ref.read(databaseProvider);
    final ipfs = _ref.read(ipfsServiceProvider);
    await ipfs.ensureBlocksReady();
    for (final manifest in await db.getAllManifests()) {
      for (final version in await db.getVersionsForManifest(manifest.id)) {
        if (ipfs.pinnedCids.contains(version.cid)) continue;
        await ipfs.pinCid(version.cid);
      }
    }
  }

  Future<void> _reconcileGuarded() async {
    try {
      await reconcilePinnedContent();
    } catch (_) {
      // Provider scope disposed or storage unavailable mid-cycle.
    }
  }

  Future<void> runPreservationCycle() => _reconcileGuarded();
}
