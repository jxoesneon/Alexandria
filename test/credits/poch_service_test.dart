import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/credits/credit_models.dart';
import 'package:alexandria/services/credits/poch_service.dart';

void main() {
  group('Proof of Common Heritage (PoCH - ALX-005 §3) Tests', () {
    test('calculates normalized PoCH score and compliance accurately', () {
      // 1000MB storage (100% of 1GB), 500MB seeding (100% of 500MB), 12 challenges (100% of 12)
      final fullMetrics = PoCHMetrics(
        allocatedStorageBytes: 1000 * 1024 * 1024,
        dailySeedingBytes: 500 * 1024 * 1024,
        dailyPoRChallengesAnswered: 12,
        lastCalculated: DateTime.now(),
      );

      expect(fullMetrics.score, closeTo(1.0, 0.001));
      expect(fullMetrics.isCompliant, isTrue);
      // At score = 1.0, bandwidth multiplier = 1.0 + 0.5 * log10(1 + 1.0 - 0.5)
      expect(fullMetrics.bandwidthMultiplier, greaterThan(1.0));
    });

    test(
        'enforces quadratic bandwidth throttling for non-compliant freeloader nodes',
        () {
      // Very low contributions: 100MB storage, 0 seeding, 0 challenges
      final lowMetrics = PoCHMetrics(
        allocatedStorageBytes: 100 * 1024 * 1024,
        dailySeedingBytes: 0,
        dailyPoRChallengesAnswered: 0,
        lastCalculated: DateTime.now(),
      );

      // Score = 0.4 * 0.1 = 0.04 (< 0.50 threshold)
      expect(lowMetrics.score, closeTo(0.04, 0.005));
      expect(lowMetrics.isCompliant, isFalse);
      // Floor throttling: 0.10 * (0.04 / 0.5)^2 ~ 0.00064
      expect(lowMetrics.bandwidthMultiplier, lessThan(0.01));
    });

    test(
        'PoCHService records storage, seeding, and challenge updates dynamically',
        () {
      final service = PoCHService(
        initialStorageBytes: 500 * 1024 * 1024, // 50%
        initialSeedingBytes: 250 * 1024 * 1024, // 50%
        initialChallenges: 6, // 50%
      );

      expect(service.score, closeTo(0.50, 0.01));
      expect(service.isCompliant, isTrue);

      // Increase storage allocation
      service.recordStorageAllocation(1000 * 1024 * 1024);
      expect(service.score, greaterThan(0.65));

      // Record additional seeding transfer
      service.recordSeedingActivity(250 * 1024 * 1024);
      service.recordPoRChallengeAnswered();

      expect(service.metrics.dailyPoRChallengesAnswered, 7);

      // Test daily reset
      service.resetDailyCounters();
      expect(service.metrics.dailySeedingBytes, 0);
      expect(service.metrics.dailyPoRChallengesAnswered, 0);
    });
  });
}
