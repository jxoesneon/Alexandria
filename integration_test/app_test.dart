import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alexandria/main.dart';
import 'package:alexandria/services/biometric_service.dart';
import 'package:alexandria/services/preservation_service.dart';
import 'package:alexandria/data/database.dart';

// Fakes
class FakePreservationService extends PreservationService {
  FakePreservationService(super.ref);
  @override
  void startBackgroundPreservation() {}
  @override
  void stopBackgroundPreservation() {}
}

class FakeBiometricService extends BiometricService {
  @override
  Future<bool> authenticate({String reason = ''}) async => true;
  @override
  Future<bool> isBiometricsAvailable() async => true;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('verify app startup and empty state', (tester) async {
    // Use in-memory DB for integration test to ensure clean state
    final inMemoryDb = AppDatabase();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preservationServiceProvider.overrideWith(
            (ref) => FakePreservationService(ref),
          ),
          biometricServiceProvider.overrideWith(
            (ref) => FakeBiometricService(),
          ),
          databaseProvider.overrideWithValue(inMemoryDb),
        ],
        child: const AlexandriaApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify app title
    expect(find.text('ALEXANDRIA'), findsOneWidget);

    // Verify empty state message
    expect(find.textContaining('Library is Empty'), findsOneWidget);

    await inMemoryDb.close();
  });
}
