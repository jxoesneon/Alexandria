import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'credit_models.dart';

/// Provider for PoCHService
final pochServiceProvider = ChangeNotifierProvider<PoCHService>((ref) {
  return PoCHService();
});

/// Provider for current PoCH metrics
final pochMetricsProvider = Provider<PoCHMetrics>((ref) {
  final service = ref.watch(pochServiceProvider);
  return service.metrics;
});

/// Provider for current bandwidth QoS multiplier
final bandwidthMultiplierProvider = Provider<double>((ref) {
  final metrics = ref.watch(pochMetricsProvider);
  return metrics.bandwidthMultiplier;
});

/// Service managing the Proof of Common Heritage (PoCH) baseline resource mandate
class PoCHService extends ChangeNotifier {
  int _allocatedStorageBytes;
  int _dailySeedingBytes;
  int _dailyPoRChallengesAnswered;
  DateTime _lastCalculated;

  PoCHService({
    int initialStorageBytes = PoCHMetrics.minStorageBytes,
    int initialSeedingBytes = PoCHMetrics.minSeedingBytes ~/ 2,
    int initialChallenges = 6,
  })  : _allocatedStorageBytes = initialStorageBytes,
        _dailySeedingBytes = initialSeedingBytes,
        _dailyPoRChallengesAnswered = initialChallenges,
        _lastCalculated = DateTime.now();

  /// Current PoCH evaluation snapshot
  PoCHMetrics get metrics => PoCHMetrics(
        allocatedStorageBytes: _allocatedStorageBytes,
        dailySeedingBytes: _dailySeedingBytes,
        dailyPoRChallengesAnswered: _dailyPoRChallengesAnswered,
        lastCalculated: _lastCalculated,
      );

  /// Current score [0.0, 1.0]
  double get score => metrics.score;

  /// Whether current node meets the mandatory minimum baseline contribution
  bool get isCompliant => metrics.isCompliant;

  /// Bandwidth multiplier applied to swarm ingress
  double get bandwidthMultiplier => metrics.bandwidthMultiplier;

  /// Record updated local storage allocation allocated for archival blocks
  void recordStorageAllocation(int bytes) {
    _allocatedStorageBytes =
        bytes.clamp(0, 100 * 1024 * 1024 * 1024); // Cap at 100GB
    _lastCalculated = DateTime.now();
    notifyListeners();
  }

  /// Record seeding transfer activity (inbound or outbound)
  void recordSeedingActivity(int bytesTransferred) {
    if (bytesTransferred <= 0) return;
    _dailySeedingBytes += bytesTransferred;
    _lastCalculated = DateTime.now();
    notifyListeners();
  }

  /// Record a successfully completed Proof of Retrievability challenge or metadata audit
  void recordPoRChallengeAnswered() {
    _dailyPoRChallengesAnswered += 1;
    _lastCalculated = DateTime.now();
    notifyListeners();
  }

  /// Reset rolling 24-hour counters at epoch rollover
  void resetDailyCounters() {
    _dailySeedingBytes = 0;
    _dailyPoRChallengesAnswered = 0;
    _lastCalculated = DateTime.now();
    notifyListeners();
  }
}
