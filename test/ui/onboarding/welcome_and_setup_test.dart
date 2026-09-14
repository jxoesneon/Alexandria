import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/biometric_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/mnemonic_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:alexandria/ui/onboarding/setup_wizard_screen.dart';
import 'package:alexandria/ui/onboarding/welcome_screen.dart';
import 'package:alexandria/ui/onboarding_screen.dart';

class _FakeIdentityService implements IdentityService {
  @override
  Future<AlexandriaIdentity> generateIdentity() async => AlexandriaIdentity(
        publicKey: Uint8List(32),
        privateKey: Uint8List(32),
        createdAt: DateTime(2026, 1, 1),
      );

  @override
  Future<AlexandriaIdentity?> getIdentity() async => AlexandriaIdentity(
        publicKey: Uint8List(32),
        privateKey: Uint8List(32),
        createdAt: DateTime(2026, 1, 1),
      );

  Future<AlexandriaIdentity> createIdentity({String? name}) async => AlexandriaIdentity(
        publicKey: Uint8List(32),
        privateKey: Uint8List(32),
        createdAt: DateTime(2026, 1, 1),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMnemonicService implements MnemonicService {
  @override
  Future<MnemonicResult> generateMnemonic() async => MnemonicResult(
        words: List.filled(24, 'abandon'),
        entropy: Uint8List(32),
        seed: Uint8List(64),
      );

  @override
  bool validateMnemonic(List<String> words) => words.length == 24;

  @override
  Future<AlexandriaIdentity?> recoverFromMnemonic(List<String> words) async =>
      AlexandriaIdentity(
        publicKey: Uint8List(32),
        privateKey: Uint8List(32),
        createdAt: DateTime(2026, 1, 1),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBiometricService implements BiometricService {
  Future<bool> isBiometricAvailable() async => true;

  @override
  Future<bool> authenticate(
      {String reason = 'Please authenticate to access Alexandria'}) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSecureStorageService implements SecureStorageService {
  final Map<String, String> storage = {};

  @override
  Future<void> write(String key, String value) async {
    storage[key] = value;
  }

  @override
  Future<String?> read(String key) async => storage[key];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Onboarding Screens Tests', () {
    testWidgets('WelcomeScreen renders title, subtitle, and enter button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            identityServiceProvider.overrideWithValue(_FakeIdentityService()),
            mnemonicServiceProvider.overrideWithValue(_FakeMnemonicService()),
            biometricServiceProvider.overrideWithValue(_FakeBiometricService()),
            secureStorageServiceProvider.overrideWithValue(_FakeSecureStorageService()),
          ],
          child: const MaterialApp(
            home: WelcomeScreen(),
          ),
        ),
      );

      expect(find.text('ALEXANDRIA'), findsOneWidget);
      expect(find.text('Preserve Human Knowledge'), findsOneWidget);
      expect(find.text('Enter the archive'), findsOneWidget);

      await tester.tap(find.text('Enter the archive'));
      await tester.pumpAndSettle();
    });

    testWidgets('SetupWizardScreen completes timer sequence and progresses', (tester) async {
      final fakeStorage = _FakeSecureStorageService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageServiceProvider.overrideWithValue(fakeStorage),
          ],
          child: const MaterialApp(
            home: SetupWizardScreen(),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.fingerprint), findsOneWidget);

      // Fast forward all fake timers in _startGenerationSequence
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(fakeStorage.storage['has_seen_onboarding'], equals('true'));
    });

    testWidgets('OnboardingScreen renders all steps via step provider', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeIdentity = _FakeIdentityService();
      final fakeMnemonic = _FakeMnemonicService();
      final fakeBiometrics = _FakeBiometricService();
      final fakeStorage = _FakeSecureStorageService();

      final container = ProviderContainer(
        overrides: [
          identityServiceProvider.overrideWithValue(fakeIdentity),
          mnemonicServiceProvider.overrideWithValue(fakeMnemonic),
          biometricServiceProvider.overrideWithValue(fakeBiometrics),
          secureStorageServiceProvider.overrideWithValue(fakeStorage),
        ],
      );
      addTearDown(container.dispose);

      // Start at welcome step and tap Begin
      container.read(onboardingStepProvider.notifier).state = OnboardingStep.welcome;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OnboardingScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Begin'), findsOneWidget);
      await tester.tap(find.text('Begin'));
      await tester.pumpAndSettle();

      // Identity step: tap Create New Identity
      expect(find.text('Create New Identity'), findsOneWidget);
      await tester.tap(find.text('Create New Identity'));
      await tester.pumpAndSettle();

      // Key step
      expect(find.text('Ed25519 Keypair Generated'), findsOneWidget);
      expect(find.text('Backup your key'), findsOneWidget);
      await tester.tap(find.text('Backup your key'));
      await tester.pumpAndSettle();

      // Mnemonic step: generate and copy
      if (find.text('Generate Backup Phrase').evaluate().isNotEmpty) {
        await tester.tap(find.text('Generate Backup Phrase'));
        await tester.pumpAndSettle();
      }

      final copyButton = find.text('Copy');
      if (copyButton.evaluate().isNotEmpty) {
        await tester.tap(copyButton);
        await tester.pump();
      }

      final savedButton = find.text("I've Saved It");
      if (savedButton.evaluate().isNotEmpty) {
        await tester.tap(savedButton);
        await tester.pumpAndSettle();
      }

      // Biometric step: Enable biometrics
      final enableBiometricsBtn = find.text('Enable Biometrics');
      if (enableBiometricsBtn.evaluate().isNotEmpty) {
        await tester.tap(enableBiometricsBtn);
        await tester.pumpAndSettle();
      }

      // Complete step
      expect(find.text('Welcome, Archivist'), findsOneWidget);
      expect(find.text('Enter the library'), findsOneWidget);

      // Import Dialog Flow
      container.read(onboardingStepProvider.notifier).state = OnboardingStep.identity;
      await tester.pumpAndSettle();

      final importBtn = find.text('Import Existing Identity');
      if (importBtn.evaluate().isNotEmpty) {
        await tester.tap(importBtn);
        await tester.pumpAndSettle();

        expect(find.text('Import Recovery Phrase'), findsOneWidget);
        await tester.tap(find.text('Import'));
        await tester.pumpAndSettle();
      }

      // Test cancel button on import dialog
      container.read(onboardingStepProvider.notifier).state = OnboardingStep.identity;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import Existing Identity'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Import Recovery Phrase'), findsNothing);

      // Test "Skip for now" on key step
      container.read(onboardingStepProvider.notifier).state = OnboardingStep.key;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();
      expect(container.read(onboardingStepProvider), equals(OnboardingStep.biometric));

      // Test "Skip" on biometric step
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(container.read(onboardingStepProvider), equals(OnboardingStep.complete));

      // Test "Enter the library" button on complete step (navigates away)
      await tester.tap(find.text('Enter the library'));
      await tester.pumpAndSettle();
      expect(fakeStorage.storage['has_seen_onboarding'], equals('true'));
    });
  });
}
