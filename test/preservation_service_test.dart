import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/preservation_service.dart';

void main() {
  group('PreservationService Health & Healing Tests', () {
    late ProviderContainer container;
    late PreservationService preservation;

    setUp(() {
      container = ProviderContainer();
      preservation = container.read(preservationServiceProvider);
    });

    tearDown(() {
      preservation.stopBackgroundPreservation();
      container.dispose();
    });

    test('background preservation lifecycle starts and stops cleanly', () {
      expect(preservation.isRunning, isFalse);
      preservation.startBackgroundPreservation();
      expect(preservation.isRunning, isTrue);
      preservation.stopBackgroundPreservation();
      expect(preservation.isRunning, isFalse);
    });

    test('checks content health and heals pinned items', () async {
      final health = await preservation.checkContentHealth('bafy_sample_test');
      expect(
          health,
          isIn([
            HealthStatus.healthy,
            HealthStatus.endangered,
            HealthStatus.lost
          ]));

      final heal = await preservation.healContent('bafy_sample_test');
      expect(heal, isTrue);
    });
  });
}
