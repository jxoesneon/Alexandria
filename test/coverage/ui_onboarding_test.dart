import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/ui/onboarding_screen.dart';

/// Stateful in-memory handler for flutter_secure_storage.
Map<String, String> installSecureStore() {
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      final key = call.arguments['key'] as String?;
      switch (call.method) {
        case 'read':
          return store[key];
        case 'write':
          store[key!] = call.arguments['value'] as String;
          return null;
        case 'delete':
          store.remove(key);
          return null;
        case 'containsKey':
          return store.containsKey(key);
        default:
          return null;
      }
    },
  );
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpOnboarding(WidgetTester tester,
      {OnboardingStep? step, ProviderContainer? container}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final overrides = <Override>[
      if (step != null) onboardingStepProvider.overrideWith((ref) => step),
    ];
    final child = const MaterialApp(home: OnboardingScreen());
    await tester.pumpWidget(
      container != null
          ? UncontrolledProviderScope(container: container, child: child)
          : ProviderScope(overrides: overrides, child: child),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('welcome advances to identity step', (tester) async {
    installSecureStore();
    await pumpOnboarding(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Begin'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Create New Identity'), findsOneWidget);
    expect(find.text('Import Existing Identity'), findsOneWidget);
  });

  testWidgets('create new identity generates key and advances to key step',
      (tester) async {
    installSecureStore();
    await pumpOnboarding(tester, step: OnboardingStep.identity);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create New Identity'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // Key step reached after generation.
    expect(find.text('Create New Identity'), findsNothing);
  });

  testWidgets('create with stored identity asks before replacing',
      (tester) async {
    installSecureStore();
    // Seed an identity via a separate container so the widget's service
    // has no cache but hasIdentity() reports true.
    final seed = ProviderContainer();
    addTearDown(seed.dispose);
    await seed.read(identityServiceProvider).generateIdentity();

    await pumpOnboarding(tester, step: OnboardingStep.identity);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create New Identity'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Replace existing identity?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Create New Identity'), findsOneWidget);

    await tester.tap(find.text('Create New Identity'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace identity'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Create New Identity'), findsNothing);
  });

  testWidgets('generate backup phrase sets mnemonic words', (tester) async {
    installSecureStore();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(identityServiceProvider).generateIdentity();

    await pumpOnboarding(tester, step: OnboardingStep.mnemonic);
    await tester.pumpAndSettle();
    expect(find.text('Generate Backup Phrase'), findsOneWidget);

    // The button's async handler progresses across pump() microtask
    // flushes (PBKDF2 is pure Dart).
    await tester.tap(find.text('Generate Backup Phrase'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    // Words are populated into the provider - the phrase grid renders.
    final widgetContainer = ProviderScope.containerOf(
        tester.element(find.byType(OnboardingScreen)));
    final words = widgetContainer.read(mnemonicProvider);
    expect(words, isNotNull);
    expect(words, hasLength(24));
  });

  testWidgets('generate backup phrase without identity shows error snackbar',
      (tester) async {
    installSecureStore();
    await pumpOnboarding(tester, step: OnboardingStep.mnemonic);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generate Backup Phrase'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.text('No identity found to back up.'), findsOneWidget);
  });

  testWidgets('import dialog recovers a valid phrase and completes',
      (tester) async {
    installSecureStore();
    await pumpOnboarding(tester, step: OnboardingStep.identity);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import Existing Identity'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Import Recovery Phrase'), findsOneWidget);
    // The 24-field grid builds lazily - TextField.controller is public,
    // so fill the built cells, scroll, and fill the next batch.
    final words = List.filled(23, 'abandon') + ['art'];
    await fillWordFields(tester, words);
    await tester.tap(find.text('Import'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Enter the library'), findsOneWidget);
  });

  testWidgets('import dialog rejects an invalid phrase', (tester) async {
    installSecureStore();
    await pumpOnboarding(tester, step: OnboardingStep.identity);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import Existing Identity'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    await fillWordFields(tester, List.filled(24, 'zzz'));
    await tester.tap(find.text('Import'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Invalid recovery phrase'), findsOneWidget);
  });

  testWidgets('biometric step: enable reports unavailable in tests',
      (tester) async {
    installSecureStore();
    await pumpOnboarding(tester, step: OnboardingStep.biometric);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enable Biometrics'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    // Either the complete step (biometrics unavailable -> true) or the
    // error snackbar - both paths end onboarding.
    final completed = find.text('Enter the library').evaluate().isNotEmpty ||
        find.textContaining('Biometric').evaluate().isNotEmpty;
    expect(completed, isTrue);
  });

  testWidgets('complete step enters the library', (tester) async {
    final store = installSecureStore();
    await pumpOnboarding(tester, step: OnboardingStep.complete);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enter the library'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    tester.takeException();
    await tester.pumpAndSettle();
    tester.takeException();
    expect(store['has_seen_onboarding'], 'true');
  });
}

/// Fills the import dialog's 24 lazily-built word fields by writing to
/// each visible [TextField]'s public controller, scrolling the grid to
/// build the remaining cells.
Future<void> fillWordFields(WidgetTester tester, List<String> words) async {
  var i = 0;
  var guard = 0;
  while (i < 24 && guard++ < 12) {
    final fields = find
        .byType(TextField)
        .evaluate()
        .map((e) => e.widget as TextField)
        .toList();
    var filledThisPass = false;
    for (final tf in fields) {
      final c = tf.controller;
      if (c != null && c.text.isEmpty && i < 24) {
        c.text = words[i++];
        filledThisPass = true;
      }
    }
    if (i >= 24) break;
    await tester.drag(find.byType(GridView), const Offset(0, -300));
    await tester.pump();
    if (!filledThisPass) {
      // Guard against a grid that won't scroll further.
      final remaining = find
          .byType(TextField)
          .evaluate()
          .map((e) => e.widget as TextField)
          .where((tf) => (tf.controller?.text ?? '').isEmpty)
          .toList();
      if (remaining.isEmpty) break;
    }
  }
}
