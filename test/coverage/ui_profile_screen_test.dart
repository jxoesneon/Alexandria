import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/ui/profile_screen.dart';

/// Installs a stateful in-memory handler for flutter_secure_storage so
/// the real IdentityService/MnemonicService paths are exercisable.
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

  group('providers', () {
    test(
        'reputationProvider, pinnedCountProvider, myProfileProvider, '
        'userActivityProvider resolve', () async {
      installSecureStore();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(reputationProvider), isA<double>());
      expect(container.read(pinnedCountProvider), isA<int>());
      expect(await container.read(myProfileProvider.future), isNull);
      final activity =
          await container.read(userActivityProvider('pubkey-x').future);
      expect(activity, isA<Map<DateTime, int>>());
    });
  });

  group('ProfileScreen', () {
    Future<void> pumpScreen(WidgetTester tester,
        {List<Override> overrides = const []}) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('shows unverified state and generates identity',
        (tester) async {
      installSecureStore();
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      expect(find.text('UNVERIFIED'), findsOneWidget);
      expect(find.text('Generate Identity'), findsOneWidget);

      await tester.tap(find.text('Generate Identity'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Identity created successfully!'), findsOneWidget);
      expect(find.text('VERIFIED'), findsOneWidget);
    });

    testWidgets('generate with stale-null state asks before replacing',
        (tester) async {
      installSecureStore();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Create an identity in a SEPARATE container — the widget's own
      // IdentityService never caches it and its revision stream doesn't
      // invalidate the widget's provider, so the screen keeps rendering
      // the stale no-identity state while hasIdentity() reports true.
      await pumpScreen(tester);
      await tester.pumpAndSettle();
      expect(find.text('Generate Identity'), findsOneWidget);

      final otherContainer = ProviderContainer();
      addTearDown(otherContainer.dispose);
      await otherContainer.read(identityServiceProvider).generateIdentity();

      await tester.tap(find.text('Generate Identity'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Replace existing identity?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      // Cancelled: still unverified in the stale view.
      expect(find.text('UNVERIFIED'), findsOneWidget);

      await tester.tap(find.text('Generate Identity'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace identity'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Identity created successfully!'), findsOneWidget);
    });

    testWidgets('identity provider error branch renders', (tester) async {
      installSecureStore();
      await pumpScreen(tester, overrides: [
        identityStateProvider.overrideWith((ref) async {
          throw StateError('identity boom');
        }),
      ]);
      await tester.pumpAndSettle();
      expect(find.textContaining('Error:'), findsOneWidget);
    });

    testWidgets('backup dialog shows empty-state error without identity',
        (tester) async {
      installSecureStore();
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.backup));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Backup Identity'), findsOneWidget);
      expect(find.text('No identity found to backup.'), findsOneWidget);
    });

    testWidgets('backup dialog shows phrase and copy/confirm actions',
        (tester) async {
      final store = installSecureStore();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final identityService = container.read(identityServiceProvider);
      await identityService.generateIdentity();
      expect(store.isNotEmpty, isTrue);

      // The mnemonic word grid overflows ~7px at the default text scale
      // in the test font environment; shrink text so the dialog fits.
      tester.platformDispatcher.textScaleFactorTestValue = 0.7;
      addTearDown(
          () => tester.platformDispatcher.clearTextScaleFactorTestValue());

      // Clipboard.setData is a no-op under the test messenger — no mock
      // needed (overriding 'flutter/platform' would break SystemChrome
      // and SystemSound messages that share that channel).
      await pumpScreen(tester);
      await tester.pumpAndSettle();
      expect(find.text('VERIFIED'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.backup));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Copy'), findsOneWidget);
      // Executes the Clipboard.setData + SnackBar path; the transient
      // snackbar isn't a stable finder, so assert the dialog stays put.
      await tester.tap(find.text('Copy'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Backup Identity'), findsOneWidget);

      await tester.tap(find.text("I've saved it"));
      await tester.pumpAndSettle();
      expect(find.text('Backup Identity'), findsNothing);
    });

    testWidgets('recover dialog rejects short phrase', (tester) async {
      installSecureStore();
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recover from Mnemonic'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Recover Identity'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'only two words');
      await tester.tap(find.text('Recover'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Invalid mnemonic phrase'), findsOneWidget);
    });

    testWidgets('recover dialog accepts a valid 24-word phrase',
        (tester) async {
      installSecureStore();
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recover from Mnemonic'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // Standard BIP-39 vector for 256-bit all-zero entropy — passes
      // checksum validation without calling backupCurrentIdentity (its
      // PBKDF2 seed derivation stalls under the fake-async zone).
      final phrase = '${List.filled(23, 'abandon').join(' ')} art';
      await tester.enterText(find.byType(TextField), phrase);
      await tester.tap(find.text('Recover'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Identity recovered successfully!'), findsOneWidget);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
