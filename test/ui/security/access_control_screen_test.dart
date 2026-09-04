import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/models/security_models.dart';
import 'package:alexandria/providers/security_providers.dart';
import 'package:alexandria/services/encryption_service.dart';
import 'package:alexandria/ui/security/access_control_screen.dart';

import 'fake_security_overview_service.dart';

class _FakeEncryptionService extends EncryptionService {
  @override
  Future<Uint8List> encryptForPeer(Uint8List data, String peerPublicKey) async {
    return Uint8List.fromList(data.map((b) => b ^ 0x42).toList());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget createSubject(FakeSecurityOverviewService fake) {
    return ProviderScope(
      overrides: [
        securityOverviewServiceProvider.overrideWith((ref) => fake..ref = ref),
        encryptionServiceProvider
            .overrideWith((ref) => _FakeEncryptionService()),
      ],
      child: const MaterialApp(
        home: AccessControlScreen(),
      ),
    );
  }

  testWidgets('renders documents and access list', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..documents = [
        const DocumentOption(cid: 'doc-cid-1', title: 'Quarterly report'),
        const DocumentOption(cid: 'doc-cid-2', title: 'Project roadmap'),
      ]
      ..accessPolicies = {
        'doc-cid-1': [
          AccessPolicy(
            cid: 'doc-cid-1',
            peerDid: 'did:peer:alice',
            grantedAt: DateTime(2024, 5, 10),
          ),
        ],
      };

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Access Control'), findsOneWidget);
    expect(find.text('Quarterly report (doc-cid-1)'), findsOneWidget);
    expect(find.text('did:peer:alice'), findsOneWidget);
  });

  testWidgets('grants access to a peer', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..documents = [
        const DocumentOption(cid: 'doc-cid-1', title: 'Quarterly report'),
      ];

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextField).first, 'did:peer:bob');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Grant'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Access granted'), findsOneWidget);
    expect(find.text('did:peer:bob'), findsWidgets);
  });

  testWidgets('revokes access', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..documents = [
        const DocumentOption(cid: 'doc-cid-1', title: 'Quarterly report'),
      ]
      ..accessPolicies = {
        'doc-cid-1': [
          AccessPolicy(
            cid: 'doc-cid-1',
            peerDid: 'did:peer:alice',
            grantedAt: DateTime(2024, 5, 10),
          ),
        ],
      };

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.ensureVisible(find.byIcon(Icons.delete_outline).first);
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Access revoked'), findsOneWidget);
    expect(
        find.text('No permissions granted for this document'), findsOneWidget);
  });

  testWidgets('encrypts data for peer', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..documents = [
        const DocumentOption(cid: 'doc-cid-1', title: 'Quarterly report'),
      ];

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextField).first, 'did:peer:bob');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Encrypt for peer'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.textContaining('Encrypted 32 bytes for peer'), findsOneWidget);
  });

  testWidgets('shows no documents message', (tester) async {
    final fake = FakeSecurityOverviewService()..documents = const [];

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('No documents available'), findsOneWidget);
    expect(
      find.text('No permissions granted for this document'),
      findsOneWidget,
    );
  });

  testWidgets('shows loading documents', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentsProvider.overrideWith(
            (ref) => Completer<List<DocumentOption>>().future,
          ),
        ],
        child: const MaterialApp(
          home: AccessControlScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('selects a different document from dropdown', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..documents = const [
        DocumentOption(cid: 'doc-cid-1', title: 'Quarterly report'),
        DocumentOption(cid: 'doc-cid-2', title: 'Project roadmap'),
      ]
      ..accessPolicies = {
        'doc-cid-2': [
          AccessPolicy(
            cid: 'doc-cid-2',
            peerDid: 'did:peer:bob',
            grantedAt: DateTime(2024, 5, 10),
          ),
        ],
      };

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.text('Project roadmap (doc-cid-2)').last);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('did:peer:bob'), findsOneWidget);
  });

  testWidgets('renders multiple policies', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..documents = const [
        DocumentOption(cid: 'doc-cid-1', title: 'Quarterly report'),
      ]
      ..accessPolicies = {
        'doc-cid-1': [
          AccessPolicy(
            cid: 'doc-cid-1',
            peerDid: 'did:peer:alice',
            grantedAt: DateTime(2024, 5, 10),
          ),
          AccessPolicy(
            cid: 'doc-cid-1',
            peerDid: 'did:peer:bob',
            grantedAt: DateTime(2024, 5, 11),
          ),
        ],
      };

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('did:peer:alice'), findsOneWidget);
    expect(find.text('did:peer:bob'), findsOneWidget);
  });

  testWidgets('shows access list error', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..documents = const [
        DocumentOption(cid: 'doc-cid-1', title: 'Quarterly report'),
      ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          securityOverviewServiceProvider.overrideWith(
            (ref) => fake..ref = ref,
          ),
          encryptionServiceProvider
              .overrideWith((ref) => _FakeEncryptionService()),
          selectedCidProvider.overrideWith((ref) => 'doc-cid-1'),
          documentAclProvider.overrideWith(
            (ref, cid) => Future<List<AccessPolicy>>.error(
              Exception('acl error'),
            ),
          ),
        ],
        child: const MaterialApp(
          home: AccessControlScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.textContaining('Failed to load access list'), findsOneWidget);
  });

  testWidgets('shows documents error', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentsProvider.overrideWith(
            (ref) => Future<List<DocumentOption>>.error(
              Exception('documents error'),
            ),
          ),
        ],
        child: const MaterialApp(
          home: AccessControlScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.textContaining('Failed to load documents'), findsOneWidget);
  });
}
