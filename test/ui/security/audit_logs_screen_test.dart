import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/models/security_models.dart';
import 'package:alexandria/providers/security_providers.dart';
import 'package:alexandria/ui/security/audit_logs_screen.dart';

import 'fake_security_overview_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget createSubject(FakeSecurityOverviewService fake) {
    return ProviderScope(
      overrides: [
        securityOverviewServiceProvider.overrideWith((ref) => fake..ref = ref),
      ],
      child: const MaterialApp(
        home: AuditLogsScreen(),
      ),
    );
  }

  testWidgets('renders audit logs', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..auditLogs = [
        AuditLog(
          event: 'Document access',
          actor: 'did:peer:user1',
          timestamp: DateTime(2024, 5, 10, 12, 30),
          status: 'Success',
        ),
        AuditLog(
          event: 'Key export',
          actor: 'did:peer:user2',
          timestamp: DateTime(2024, 5, 10, 11, 0),
          status: 'Denied',
        ),
      ];

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Audit Logs'), findsOneWidget);
    expect(find.text('Document access'), findsOneWidget);
    expect(find.text('Key export'), findsOneWidget);
    expect(find.text('did:peer:user1'), findsOneWidget);
    expect(find.text('Denied'), findsOneWidget);
  });

  testWidgets('issues and verifies a PoR challenge', (tester) async {
    final fake = FakeSecurityOverviewService()..verifyResult = true;

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), 'cid-001');
    await tester.enterText(textFields.at(1), 'peer-001');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.text('Issue challenge'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Challenge issued'), findsOneWidget);
    expect(find.text('cid-001'), findsWidgets);

    await tester.ensureVisible(find.text('Verify').first);
    await tester.tap(find.text('Verify').first);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.textContaining('Verified: proof is valid'), findsOneWidget);
  });

  testWidgets('shows empty audit logs state', (tester) async {
    final fake = FakeSecurityOverviewService();

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('No audit logs available'), findsOneWidget);
  });

  testWidgets('shows audit logs error', (tester) async {
    final fake = FakeSecurityOverviewService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          securityOverviewServiceProvider
              .overrideWith((ref) => fake..ref = ref),
          auditLogsProvider.overrideWith(
            (ref) => Future<List<AuditLog>>.error(
              Exception('logs error'),
            ),
          ),
        ],
        child: const MaterialApp(
          home: AuditLogsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.textContaining('Failed to load audit logs'), findsOneWidget);
  });

  testWidgets('shows verification failed', (tester) async {
    final fake = FakeSecurityOverviewService()..verifyResult = false;

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), 'cid-001');
    await tester.enterText(textFields.at(1), 'peer-001');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.text('Issue challenge'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.ensureVisible(find.text('Verify').first);
    await tester.tap(find.text('Verify').first);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(
        find.textContaining('Verification failed for cid-001'), findsOneWidget);
  });

  testWidgets('renders multiple PoR challenges', (tester) async {
    final fake = FakeSecurityOverviewService();

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final textFields = find.byType(TextField);

    await tester.enterText(textFields.at(0), 'cid-001');
    await tester.enterText(textFields.at(1), 'peer-001');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Issue challenge'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.enterText(textFields.at(0), 'cid-002');
    await tester.enterText(textFields.at(1), 'peer-002');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Issue challenge'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.textContaining('cid-001'), findsWidgets);
    expect(find.textContaining('cid-002'), findsWidgets);
  });
}
