import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/logger_service.dart';

void main() {
  group('LoggerService Tests', () {
    test('provides a logger service instance via provider', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final logger = container.read(loggerServiceProvider);
      expect(logger, isA<LoggerService>());
    });

    test('invokes debug, info, warning, and error logging without error', () {
      final logger = LoggerService();

      expect(() => logger.d('Debug test message'), returnsNormally);
      expect(() => logger.i('Info test message'), returnsNormally);
      expect(() => logger.w('Warning test message'), returnsNormally);
      expect(
        () => logger.e('Error test message', 'SampleError', StackTrace.empty),
        returnsNormally,
      );
    });
  });
}
