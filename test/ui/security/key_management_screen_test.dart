import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/models/security_models.dart';
import 'package:alexandria/providers/security_providers.dart';
import 'package:alexandria/ui/security/key_management_screen.dart';

import 'fake_security_overview_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget createSubject(FakeSecurityOverviewService fake) {
    return ProviderScope(
      overrides: [
        securityOverviewServiceProvider.overrideWith((ref) => fake..ref = ref),
      ],
      child: const MaterialApp(
        home: KeyManagementScreen(),
      ),
    );
  }

  testWidgets('renders active identities', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..identities = [
        Keypair(
          id: 'key-001',
          type: KeyType.ed25519,
          createdAt: DateTime(2024, 5, 12),
          did: 'did:alex:key-001',
        ),
      ];

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Key Management'), findsOneWidget);
    expect(find.text('Active identities'), findsOneWidget);
    expect(find.text('Ed25519'), findsOneWidget);
    expect(find.text('did:alex:key-001'), findsOneWidget);
  });

  testWidgets('generates a new keypair', (tester) async {
    final fake = FakeSecurityOverviewService();

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('No identities found'), findsOneWidget);

    await tester.tap(find.text('Generate new key'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Ed25519'), findsOneWidget);
    expect(fake.identities, isNotEmpty);
  });

  testWidgets('warns before replacing an existing keypair', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..identities = [
        Keypair(
          id: 'key-001',
          type: KeyType.ed25519,
          createdAt: DateTime(2024, 5, 12),
          did: 'did:alex:key-001',
        ),
      ];

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // The existing key may be funded — rotation must be confirmed.
    await tester.tap(find.text('Generate new key'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Replace existing keypair?'), findsOneWidget);
    expect(fake.generatedIdentity, isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(fake.generatedIdentity, isNull);

    // Confirming performs the rotation.
    await tester.tap(find.text('Generate new key'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Replace key'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(fake.generatedIdentity, isNotNull);
  });

  testWidgets(
      'rotation failure shows a SnackBar instead of an '
      'unhandled error', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..generateError = StateError('identity write failed verification');

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.text('Generate new key'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // An uncaught async error would fail this test on its own.
    expect(
      find.textContaining('Failed to generate new key'),
      findsOneWidget,
    );
    expect(fake.generatedIdentity, isNull);
  });

  testWidgets('exports private key', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..identities = [
        Keypair(
          id: 'key-001',
          type: KeyType.ed25519,
          createdAt: DateTime(2024, 5, 12),
          did: 'did:alex:key-001',
        ),
      ];

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Export private key'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'password123');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Exported key'), findsOneWidget);
    expect(find.textContaining('encrypted-private-key'), findsOneWidget);
  });

  testWidgets('resolves a DID', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..resolvedDid = const DidDocument(
        did: 'did:alex:key-001',
        publicKeys: ['pubkey-001'],
      );

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.text('Resolve DID'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Resolve DID'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'did:alex:key-001');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Resolve'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Resolved DID'), findsOneWidget);
    expect(find.textContaining('pubkey-001'), findsOneWidget);
  });

  testWidgets('resolves a DID from the identity icon', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..identities = [
        Keypair(
          id: 'key-001',
          type: KeyType.ed25519,
          createdAt: DateTime(2024, 5, 12),
          did: 'did:alex:key-001',
        ),
      ]
      ..resolvedDid = const DidDocument(
        did: 'did:alex:key-001',
        publicKeys: ['pubkey-001'],
      );

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.verified_user_outlined));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Resolved DID'), findsOneWidget);
    expect(find.textContaining('pubkey-001'), findsOneWidget);
  });

  testWidgets('renders multiple identities', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..identities = [
        Keypair(
          id: 'key-001',
          type: KeyType.ed25519,
          createdAt: DateTime(2024, 5, 12),
          did: 'did:alex:key-001',
        ),
        Keypair(
          id: 'key-002',
          type: KeyType.ed25519,
          createdAt: DateTime(2024, 5, 13),
          did: 'did:alex:key-002',
        ),
      ];

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('did:alex:key-001'), findsOneWidget);
    expect(find.text('did:alex:key-002'), findsOneWidget);
  });

  testWidgets('cancels export dialog', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..identities = [
        Keypair(
          id: 'key-001',
          type: KeyType.ed25519,
          createdAt: DateTime(2024, 5, 12),
          did: 'did:alex:key-001',
        ),
      ];

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('cancels resolve input dialog', (tester) async {
    final fake = FakeSecurityOverviewService();

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.text('Resolve DID'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('resolve input dialog does nothing when empty', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..resolvedDid = const DidDocument(
        did: 'did:alex:key-001',
        publicKeys: ['pubkey-001'],
      );

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.text('Resolve DID'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.text('Resolve'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Resolved DID'), findsNothing);
  });

  testWidgets('closes result dialog', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..identities = [
        Keypair(
          id: 'key-001',
          type: KeyType.ed25519,
          createdAt: DateTime(2024, 5, 12),
          did: 'did:alex:key-001',
        ),
      ];

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextField).first, 'password123');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Exported key'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('shows identity error state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeIdentitiesProvider.overrideWith(
            (ref) => Future<List<Keypair>>.error(
              Exception('identities error'),
            ),
          ),
        ],
        child: const MaterialApp(
          home: KeyManagementScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Error loading identities:'), findsOneWidget);
  });
}
