import 'dart:async';
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
  /// Simulate an identity already stored on the device - the "Create
  /// New Identity" path must warn before replacing it.
  bool identityExists = false;
  int generateCalls = 0;

  final StreamController<int> _revisionController =
      StreamController<int>.broadcast(sync: true);
  int _revision = 0;

  @override
  Stream<int> get revisionStream => _revisionController.stream;

  @override
  int get revision => _revision;

  @override
  Future<bool> hasIdentity() async => identityExists;

  @override
  Future<AlexandriaIdentity> generateIdentity() async {
    generateCalls++;
    _revision++;
    _revisionController.add(_revision);
    return AlexandriaIdentity(
      publicKey: Uint8List(32),
      privateKey: Uint8List(32),
      createdAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<AlexandriaIdentity?> getIdentity() async => AlexandriaIdentity(
        publicKey: Uint8List(32),
        privateKey: Uint8List(32),
        createdAt: DateTime(2026, 1, 1),
      );

  Future<AlexandriaIdentity> createIdentity({String? name}) async =>
      AlexandriaIdentity(
        publicKey: Uint8List(32),
        privateKey: Uint8List(32),
        createdAt: DateTime(2026, 1, 1),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMnemonicService implements MnemonicService {
  bool backupRequested = false;
  bool randomGenerateRequested = false;
  bool backupConfirmed = false;
  String? confirmedPhrase;
  int recoverCalls = 0;

  /// What [backupCurrentIdentity] should return; null simulates "no
  /// identity exists to back up".
  MnemonicResult? backupResult = MnemonicResult(
    words: List.filled(24, 'abandon'),
    entropy: Uint8List(32),
    seed: Uint8List(64),
  );

  @override
  Future<MnemonicResult> generateMnemonic() async {
    randomGenerateRequested = true;
    return MnemonicResult(
      words: List.filled(24, 'abandon'),
      entropy: Uint8List(32),
      seed: Uint8List(64),
    );
  }

  @override
  Future<MnemonicResult?> backupCurrentIdentity() async {
    backupRequested = true;
    return backupResult;
  }

  @override
  Future<void> markBackupConfirmed(String phrase) async {
    backupConfirmed = true;
    confirmedPhrase = phrase;
  }

  @override
  bool validateMnemonic(List<String> words) => words.length == 24;

  @override
  Future<AlexandriaIdentity?> recoverFromMnemonic(List<String> words) async {
    recoverCalls++;
    return AlexandriaIdentity(
      publicKey: Uint8List(32),
      privateKey: Uint8List(32),
      createdAt: DateTime(2026, 1, 1),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBiometricService implements BiometricService {
  Future<bool> isBiometricAvailable() async => true;

  @override
  Future<bool> authenticate(
          {String reason = 'Please authenticate to access Alexandria'}) async =>
      true;

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
    testWidgets('WelcomeScreen renders title, subtitle, and enter button',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            identityServiceProvider.overrideWithValue(_FakeIdentityService()),
            mnemonicServiceProvider.overrideWithValue(_FakeMnemonicService()),
            biometricServiceProvider.overrideWithValue(_FakeBiometricService()),
            secureStorageServiceProvider
                .overrideWithValue(_FakeSecureStorageService()),
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

    testWidgets('SetupWizardScreen completes timer sequence and progresses',
        (tester) async {
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

    testWidgets('OnboardingScreen renders all steps via step provider',
        (tester) async {
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
      container.read(onboardingStepProvider.notifier).state =
          OnboardingStep.welcome;
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
      container.read(onboardingStepProvider.notifier).state =
          OnboardingStep.identity;
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
      container.read(onboardingStepProvider.notifier).state =
          OnboardingStep.identity;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import Existing Identity'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Import Recovery Phrase'), findsNothing);

      // Test "Skip for now" on key step
      container.read(onboardingStepProvider.notifier).state =
          OnboardingStep.key;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();
      expect(container.read(onboardingStepProvider),
          equals(OnboardingStep.biometric));

      // Test "Skip" on biometric step
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(container.read(onboardingStepProvider),
          equals(OnboardingStep.complete));

      // Test "Enter the library" button on complete step (navigates away)
      await tester.tap(find.text('Enter the library'));
      await tester.pumpAndSettle();
      expect(fakeStorage.storage['has_seen_onboarding'], equals('true'));
    });

    testWidgets(
        'backup phrase is derived from the stored identity, not random entropy',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeMnemonic = _FakeMnemonicService();
      final container = ProviderContainer(
        overrides: [
          identityServiceProvider.overrideWithValue(_FakeIdentityService()),
          mnemonicServiceProvider.overrideWithValue(fakeMnemonic),
          biometricServiceProvider.overrideWithValue(_FakeBiometricService()),
          secureStorageServiceProvider
              .overrideWithValue(_FakeSecureStorageService()),
        ],
      );
      addTearDown(container.dispose);

      container.read(onboardingStepProvider.notifier).state =
          OnboardingStep.mnemonic;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OnboardingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Regression: the displayed "backup" must be derived from the
      // stored private key via backupCurrentIdentity() - never from
      // fresh random entropy (generateMnemonic), which would recover a
      // DIFFERENT keypair.
      await tester.tap(find.text('Generate Backup Phrase'));
      await tester.pumpAndSettle();

      expect(fakeMnemonic.backupRequested, isTrue);
      expect(fakeMnemonic.randomGenerateRequested, isFalse);
      expect(container.read(mnemonicProvider), isNotNull);
      expect(find.text("I've Saved It"), findsOneWidget);
    });

    testWidgets('shows an error when there is no identity to back up',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeMnemonic = _FakeMnemonicService()..backupResult = null;
      final container = ProviderContainer(
        overrides: [
          identityServiceProvider.overrideWithValue(_FakeIdentityService()),
          mnemonicServiceProvider.overrideWithValue(fakeMnemonic),
          biometricServiceProvider.overrideWithValue(_FakeBiometricService()),
          secureStorageServiceProvider
              .overrideWithValue(_FakeSecureStorageService()),
        ],
      );
      addTearDown(container.dispose);

      container.read(onboardingStepProvider.notifier).state =
          OnboardingStep.mnemonic;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OnboardingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate Backup Phrase'));
      await tester.pumpAndSettle();

      expect(find.text('No identity found to back up.'), findsOneWidget);
      expect(container.read(mnemonicProvider), isNull);
    });

    testWidgets('creating an identity warns before replacing a stored one',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeIdentity = _FakeIdentityService()..identityExists = true;
      final container = ProviderContainer(
        overrides: [
          identityServiceProvider.overrideWithValue(fakeIdentity),
          mnemonicServiceProvider.overrideWithValue(_FakeMnemonicService()),
          biometricServiceProvider.overrideWithValue(_FakeBiometricService()),
          secureStorageServiceProvider
              .overrideWithValue(_FakeSecureStorageService()),
        ],
      );
      addTearDown(container.dispose);

      container.read(onboardingStepProvider.notifier).state =
          OnboardingStep.identity;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OnboardingScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // The stored identity may be funded - creating a new key must
      // require explicit confirmation first.
      await tester.tap(find.text('Create New Identity'));
      await tester.pumpAndSettle();

      expect(find.text('Replace existing identity?'), findsOneWidget);
      expect(fakeIdentity.generateCalls, 0);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fakeIdentity.generateCalls, 0);
      expect(
        container.read(onboardingStepProvider),
        OnboardingStep.identity,
      );

      // Confirming performs the replacement.
      await tester.tap(find.text('Create New Identity'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace identity'));
      await tester.pumpAndSettle();

      expect(fakeIdentity.generateCalls, 1);
      expect(container.read(onboardingStepProvider), OnboardingStep.key);
    });

    testWidgets('backup confirmation writes the backup marker on explicit save',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeMnemonic = _FakeMnemonicService();
      final container = ProviderContainer(
        overrides: [
          identityServiceProvider.overrideWithValue(_FakeIdentityService()),
          mnemonicServiceProvider.overrideWithValue(fakeMnemonic),
          biometricServiceProvider.overrideWithValue(_FakeBiometricService()),
          secureStorageServiceProvider
              .overrideWithValue(_FakeSecureStorageService()),
        ],
      );
      addTearDown(container.dispose);

      container.read(onboardingStepProvider.notifier).state =
          OnboardingStep.mnemonic;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OnboardingScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate Backup Phrase'));
      await tester.pumpAndSettle();
      expect(fakeMnemonic.backupConfirmed, isFalse);

      await tester.tap(find.text("I've Saved It"));
      await tester.pumpAndSettle();

      expect(fakeMnemonic.backupConfirmed, isTrue);
      expect(
        fakeMnemonic.confirmedPhrase,
        List.filled(24, 'abandon').join(' '),
      );
      expect(
        container.read(onboardingStepProvider),
        OnboardingStep.biometric,
      );
    });

    testWidgets('importing a phrase warns before replacing a stored identity',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeIdentity = _FakeIdentityService()..identityExists = true;
      final fakeMnemonic = _FakeMnemonicService();
      final container = ProviderContainer(
        overrides: [
          identityServiceProvider.overrideWithValue(fakeIdentity),
          mnemonicServiceProvider.overrideWithValue(fakeMnemonic),
          biometricServiceProvider.overrideWithValue(_FakeBiometricService()),
          secureStorageServiceProvider
              .overrideWithValue(_FakeSecureStorageService()),
        ],
      );
      addTearDown(container.dispose);

      container.read(onboardingStepProvider.notifier).state =
          OnboardingStep.identity;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OnboardingScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Import Existing Identity'));
      await tester.pumpAndSettle();
      expect(find.text('Import Recovery Phrase'), findsOneWidget);

      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      // The recovery would REPLACE the stored identity - confirm first.
      // The confirm dialog stacks on top of the import dialog, so
      // scope the lookup to the dialog containing 'Replace identity'.
      expect(find.text('Replace existing identity?'), findsOneWidget);
      expect(fakeMnemonic.recoverCalls, 0);

      final confirmDialog = find.ancestor(
        of: find.text('Replace identity'),
        matching: find.byType(AlertDialog),
      );
      await tester.tap(
        find.descendant(of: confirmDialog, matching: find.text('Cancel')),
      );
      await tester.pumpAndSettle();
      expect(fakeMnemonic.recoverCalls, 0);

      // Confirming performs the import.
      await tester.tap(find.text('Import Existing Identity'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace identity'));
      await tester.pumpAndSettle();

      expect(fakeMnemonic.recoverCalls, 1);
      expect(
        container.read(onboardingStepProvider),
        OnboardingStep.complete,
      );
    });
  });
}
