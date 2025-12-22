import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:alexandria/main.dart';
import 'package:alexandria/services/preservation_service.dart';
import 'package:alexandria/services/biometric_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:alexandria/data/database.dart';

// Mock HttpOverrides
class TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

// Fake PreservationService
class FakePreservationService extends PreservationService {
  FakePreservationService(super.ref);

  @override
  void startBackgroundPreservation() {}
  @override
  void stopBackgroundPreservation() {}
}

// Fake BiometricService
class FakeBiometricService extends BiometricService {
  @override
  Future<bool> authenticate() async => true;
  @override
  Future<bool> isBiometricsAvailable() async => true;
}

// Fake SecureStorageService
class FakeSecureStorageService extends SecureStorageService {
  @override
  Future<String?> read(String key) async => null; // Simulate fresh install

  @override
  Future<void> write(String key, String value) async {}
}

void main() {
  setUpAll(() {
    HttpOverrides.global = TestHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  testWidgets('Alexandria UI Smoke Test', (WidgetTester tester) async {
    // Use in-memory database for testing
    final inMemoryDb = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preservationServiceProvider.overrideWith(
            (ref) => FakePreservationService(ref),
          ),
          biometricServiceProvider.overrideWith(
            (ref) => FakeBiometricService(),
          ),
          secureStorageServiceProvider.overrideWith(
            (ref) => FakeSecureStorageService(),
          ),
          databaseProvider.overrideWithValue(inMemoryDb),
        ],
        child: const AlexandriaApp(),
      ),
    );

    await tester.pump();
    // Pump frames to allow entry animations to complete
    // We cannot use pumpAndSettle because the logo has an infinite loop animation
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('ALEXANDRIA'), findsOneWidget);

    // Cleanup
    await inMemoryDb.close();
  });
}
