import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/preservation_service.dart';

void main() {
  group('PreservationService', () {
    test('HealthStatus enum has all expected values', () {
      // Verify that our health status enum is complete
      expect(HealthStatus.values.length, 4);
      expect(HealthStatus.values.contains(HealthStatus.healthy), true);
      expect(HealthStatus.values.contains(HealthStatus.endangered), true);
      expect(HealthStatus.values.contains(HealthStatus.lost), true);
      expect(HealthStatus.values.contains(HealthStatus.unknown), true);
    });

    test('Health thresholds are correctly defined', () {
      // Verify thresholds match the plan
      expect(PreservationService.healthyPeerThreshold, 3);
      expect(PreservationService.endangeredPeerThreshold, 1);
    });
  });
}
