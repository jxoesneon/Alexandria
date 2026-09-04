import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/models/security_models.dart';
import 'package:alexandria/providers/security_providers.dart';
import 'package:alexandria/ui/security/security_dashboard_screen.dart';

import 'fake_security_overview_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget createSubject(FakeSecurityOverviewService fake) {
    return ProviderScope(
      overrides: [
        securityOverviewServiceProvider.overrideWith((ref) => fake..ref = ref),
      ],
      child: const MaterialApp(
        home: SecurityDashboardScreen(),
      ),
    );
  }

  testWidgets('renders score, encryption status and alerts', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..overview = const SecurityOverview(score: 82, encryptionEnabled: true)
      ..alerts = [
        SecurityAlert(
          severity: 'medium',
          message: 'Key rotation due in 7 days',
          timestamp: DateTime.now(),
        ),
      ];

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Security Dashboard'), findsOneWidget);
    expect(find.text('Overall Score'), findsOneWidget);
    expect(find.text('82'), findsOneWidget);
    expect(find.text('Secure'), findsOneWidget);
    expect(find.text('Encryption active'), findsOneWidget);
    expect(find.text('Key rotation due in 7 days'), findsOneWidget);
  });

  testWidgets('shows empty alerts state', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..overview = const SecurityOverview(score: 50, encryptionEnabled: false)
      ..alerts = const [];

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('No recent alerts'), findsOneWidget);
  });

  testWidgets('handles overview error state', (tester) async {
    final fake = _ErrorThrowingService();

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.textContaining('Failed to load score'), findsOneWidget);
  });

  testWidgets('navigates to sub-screens', (tester) async {
    final fake = FakeSecurityOverviewService();

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Key Management'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Key Management'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Access Control'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Access Control'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Audit Logs'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Audit Logs'), findsOneWidget);
  });

  testWidgets('shows at risk score and disabled encryption', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..overview = const SecurityOverview(score: 45, encryptionEnabled: false)
      ..alerts = const [];

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('At risk'), findsOneWidget);
    expect(find.text('Encryption disabled'), findsOneWidget);
  });

  testWidgets('shows fair score', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..overview = const SecurityOverview(score: 50, encryptionEnabled: true)
      ..alerts = const [];

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Fair'), findsOneWidget);
  });

  testWidgets('handles alerts error', (tester) async {
    final fake = FakeSecurityOverviewService()
      ..overview = const SecurityOverview(score: 82, encryptionEnabled: true)
      ..alerts = const [];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          securityOverviewServiceProvider
              .overrideWith((ref) => fake..ref = ref),
          securityAlertsProvider.overrideWith(
            (ref) => Stream<List<SecurityAlert>>.error(
              Exception('alerts error'),
            ),
          ),
        ],
        child: const MaterialApp(
          home: SecurityDashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.textContaining('Failed to load alerts'), findsOneWidget);
  });

  testWidgets('renders multiple alerts with different severities',
      (tester) async {
    final fake = FakeSecurityOverviewService()
      ..overview = const SecurityOverview(score: 82, encryptionEnabled: true)
      ..alerts = [
        SecurityAlert(
          severity: 'high',
          message: 'Critical alert',
          timestamp: DateTime(2024, 5, 10, 12, 0),
        ),
        SecurityAlert(
          severity: 'low',
          message: 'Info alert',
          timestamp: DateTime(2024, 5, 10, 12, 0),
        ),
      ];

    await tester.pumpWidget(createSubject(fake));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Critical alert'), findsOneWidget);
    expect(find.text('Info alert'), findsOneWidget);
  });
}

class _ErrorThrowingService extends FakeSecurityOverviewService {
  @override
  Future<SecurityOverview> getOverview() async {
    throw Exception('overview error');
  }
}
