import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database.dart';
import '../main.dart';

final preservationServiceProvider = Provider((ref) => PreservationService(ref));

/// User-configurable resource limits (stored in preferences)
final preservationSettingsProvider = StateProvider<PreservationSettings>((ref) {
  return PreservationSettings(); // Defaults
});

class PreservationSettings {
  /// Maximum storage (in MB) this client will dedicate to preservation
  final int maxStorageMb;

  /// Maximum concurrent healing operations
  final int maxConcurrentHeals;

  /// How often to run health checks (in minutes)
  final int healthCheckIntervalMinutes;

  PreservationSettings({
    this.maxStorageMb = 500, // Default 500MB
    this.maxConcurrentHeals = 2,
    this.healthCheckIntervalMinutes = 15,
  });
}

enum HealthStatus { healthy, endangered, lost, unknown }

class PreservationService {
  final Ref _ref;
  Timer? _healthCheckTimer;
  bool _isRunning = false;

  // Thresholds
  static const int healthyPeerThreshold = 3;
  static const int endangeredPeerThreshold = 1;

  PreservationService(this._ref);

  AppDatabase get _db => _ref.read(databaseProvider);
  PreservationSettings get _settings => _ref.read(preservationSettingsProvider);

  /// Start the mandatory background preservation loop.
  /// Called automatically when the app starts.
  void startBackgroundPreservation() {
    if (_isRunning) return;
    _isRunning = true;

    // Run immediately on start
    _runPreservationCycle();

    // Schedule periodic checks
    _healthCheckTimer = Timer.periodic(
      Duration(minutes: _settings.healthCheckIntervalMinutes),
      (_) => _runPreservationCycle(),
    );
  }

  void stopBackgroundPreservation() {
    _healthCheckTimer?.cancel();
    _isRunning = false;
  }

  /// Core preservation cycle - runs automatically
  Future<void> _runPreservationCycle() async {
    // 1. Get all endangered content
    final endangered = await getEndangeredContent();
    if (endangered.isEmpty) return;

    // 2. Check resource availability
    final currentUsageMb = await _getCurrentStorageUsageMb();
    final availableMb = _settings.maxStorageMb - currentUsageMb;
    if (availableMb <= 0) return; // At capacity

    // 3. Heal content (up to concurrent limit)
    var healed = 0;
    for (final version in endangered) {
      if (healed >= _settings.maxConcurrentHeals) break;

      // Skip if we've already pinned this
      if (version.isPinned) continue;

      await healContent(version.cid);
      healed++;
    }
  }

  /// Check the health of a specific CID.
  Future<HealthStatus> checkContentHealth(String cid) async {
    final mockPeerCount = _simulatePeerLookup(cid);
    await _updatePeerCount(cid, mockPeerCount);

    if (mockPeerCount >= healthyPeerThreshold) {
      return HealthStatus.healthy;
    } else if (mockPeerCount >= endangeredPeerThreshold) {
      return HealthStatus.endangered;
    } else {
      return HealthStatus.lost;
    }
  }

  /// Heal (re-pin and provide) content - called automatically by preservation cycle
  Future<bool> healContent(String cid) async {
    final version = await _db.getVersionByCid(cid);
    if (version == null) return false;

    // In production:
    // 1. await ipfs.pin.add(cid);
    // 2. await ipfs.dht.provide(cid);

    await _db.updateVersion(
      version.copyWith(
        isPinned: true,
        peerCount: version.peerCount + 1,
        lastHealthCheck: Value(DateTime.now()),
      ),
    );

    return true;
  }

  /// Get all endangered content CIDs (automatic healing targets)
  Future<List<ContentVersion>> getEndangeredContent() async {
    return _db.getEndangeredVersions(healthyPeerThreshold);
  }

  /// Run a full health check on all known content
  Future<Map<String, HealthStatus>> runFullHealthCheck() async {
    final allVersions = await _db.getAllVersions();

    final results = <String, HealthStatus>{};
    for (final v in allVersions) {
      results[v.cid] = await checkContentHealth(v.cid);
    }
    return results;
  }

  // --- Private Helpers ---

  int _simulatePeerLookup(String cid) {
    final hash = cid.hashCode.abs();
    return hash % 6; // Returns 0-5 peers
  }

  Future<void> _updatePeerCount(String cid, int count) async {
    final version = await _db.getVersionByCid(cid);
    if (version == null) return;

    await _db.updateVersion(
      version.copyWith(
        peerCount: count,
        lastHealthCheck: Value(DateTime.now()),
      ),
    );
  }

  Future<int> _getCurrentStorageUsageMb() async {
    // Mock: Return simulated storage usage
    // In production: calculate actual pinned content size
    final pinned = await _db.getPinnedVersions();
    return pinned.fold<int>(
      0,
      (sum, v) => sum + (v.sizeBytes ~/ (1024 * 1024)),
    );
  }
}
