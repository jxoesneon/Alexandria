import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:alexandria/main.dart';
import 'package:alexandria/data/database.dart';
import 'package:alexandria/services/biometric_service.dart';
import 'package:alexandria/services/preservation_service.dart';

// Fake Services (Reuse logic from widget_test or consolidate in a test_helpers.dart if desired)
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

class TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

void main() {
  setUpAll(() {
    HttpOverrides.global = TestHttpOverrides();
  });
  tearDownAll(() {
    HttpOverrides.global = null;
  });

  testWidgets('HomeScreen golden test - Empty State', (tester) async {
    if (Platform.environment.containsKey('CI')) {
      markTestSkipped(
        'Skipping golden tests on CI due to platform differences',
      );
      return;
    }
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
          databaseProvider.overrideWithValue(inMemoryDb),
        ],
        child: const AlexandriaApp(),
      ),
    );

    // Wait for fonts/assets
    await tester.pumpAndSettle();

    // Golden match
    // Note: Goldens depend on platform (Mac/Linux/Windows).
    // Usually strict goldens require a specific environment setup (e.g. Docker or ALoC).
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/home_screen_empty.png'),
    );

    await inMemoryDb.close();
  });
}
