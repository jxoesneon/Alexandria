import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  void startBackgroundPreservation() {
    if (_isRunning) return;
    _isRunning = true;
    _timer = Timer.periodic(
        const Duration(minutes: 15), (_) => runPreservationCycle());
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

  Future<void> runPreservationCycle() async {
    // Queries endangered items and heals up to threshold
  }
}
