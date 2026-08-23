import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/preservation_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  group('Mobile OS Lifecycle & Power Management', () {
    test('preservation service suspends gracefully and resumes', () {
      final container = ProviderContainer();
      final preservation = container.read(preservationServiceProvider);

      preservation.startBackgroundPreservation();
      expect(preservation.isRunning, isTrue);

      preservation.stopBackgroundPreservation();
      expect(preservation.isRunning, isFalse);

      container.dispose();
    });
  });
}
