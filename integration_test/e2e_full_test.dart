import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alexandria/main.dart';
import 'package:alexandria/services/biometric_service.dart';
import 'package:alexandria/services/preservation_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:alexandria/data/database.dart';
import 'package:drift/native.dart';

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
  Future<bool> authenticate() async => true;
  @override
  Future<bool> isBiometricsAvailable() async => true;
}

class FakeSecureStorageService implements SecureStorageService {
  final Map<String, String> _storage = {};

  @override
  Future<String?> read(String key) async => _storage[key];

  @override
  Future<void> write(String key, String value) async => _storage[key] = value;

  @override
  Future<void> delete(String key) async => _storage.remove(key);

  @override
  Future<void> deleteAll() async => _storage.clear();

  @override
  Future<bool> containsKey(String key) async => _storage.containsKey(key);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Full onboarding to home flow', (tester) async {
    // Use in-memory DB for integration test to ensure clean state
    final inMemoryDb = AppDatabase();
    final fakeStorage = FakeSecureStorageService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preservationServiceProvider.overrideWith(
            (ref) => FakePreservationService(ref),
          ),
          biometricServiceProvider.overrideWith(
            (ref) => FakeBiometricService(),
          ),
          secureStorageServiceProvider.overrideWithValue(fakeStorage),
          databaseProvider.overrideWithValue(inMemoryDb),
        ],
        child: const AlexandriaApp(),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify Welcome Screen
    expect(find.text('ALEXANDRIA'), findsOneWidget);
    expect(find.text('BEGIN'), findsOneWidget);

    // 2. Start Onboarding
    await tester.tap(find.text('BEGIN'));
    await tester.pumpAndSettle();

    // 3. Identity Step
    expect(find.text('Create New Identity'), findsOneWidget);
    await tester.tap(find.text('Create New Identity'));
    await tester.pumpAndSettle();

    // 4. Save Keys Step (Wait for key generation)
    // Key generation might take a moment, pumpAndSettle should handle it
    expect(find.text('Your Safety is Paramount'), findsOneWidget);
    expect(find.text('I HAVE SAVED MY KEYS'), findsOneWidget);

    await tester.tap(find.text('I HAVE SAVED MY KEYS'));
    await tester.pumpAndSettle();

    // 5. Mnemonic Step
    expect(find.text('Write This Down'), findsOneWidget);
    expect(find.text('I HAVE WRITTEN THEM DOWN'), findsOneWidget);

    await tester.tap(find.text('I HAVE WRITTEN THEM DOWN'));
    await tester.pumpAndSettle();

    // 6. Biometric Step
    expect(find.text('Enable Biometrics'), findsOneWidget);
    await tester.tap(find.text('ENABLE BIOMETRICS'));
    await tester.pumpAndSettle();

    // 7. Completion Step
    expect(find.text('Welcome, Archivist'), findsOneWidget);
    await tester.tap(find.text('ENTER THE ARCHIVE'));
    await tester.pumpAndSettle();

    // 8. Verify Home Screen
    // AppBar title "ALEXANDRIA" (uppercase in AppBar usually, or check specifically)
    // The home screen body likely has "Library is Empty" for a fresh DB
    expect(find.text('Library is Empty'), findsOneWidget);

    // Check for bottom nav items
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.person), findsOneWidget);

    await inMemoryDb.close();
  });
}
