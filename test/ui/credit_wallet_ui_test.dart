import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/credits/crypto_bridge_service.dart';
import 'package:alexandria/services/credits/sponsorship_service.dart';
import 'package:alexandria/ui/credits/credit_wallet_dialog.dart';
import 'package:alexandria/ui/credits/sponsorship_card.dart';
import 'package:alexandria/ui/theme/app_theme.dart';

void main() {
  testWidgets('CreditWalletDialog renders balance, PoCH status, and handles simulation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: CreditWalletDialog(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('COMMON HERITAGE WALLET'), findsOneWidget);
    expect(find.text('ARCHIVAL CREDITS'), findsOneWidget);
    expect(find.text('PROOF OF COMMON HERITAGE'), findsOneWidget);
    expect(find.text('Resource Contribution Breakdown'), findsOneWidget);
    expect(find.text('Enable Community Sponsorships'), findsOneWidget);

    // Tap Simulate Parity Compute button
    final computeButton = find.text('Simulate Parity Compute');
    expect(computeButton, findsOneWidget);
    await tester.tap(computeButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify snackbar confirmed compute
    expect(find.textContaining('Contributed Cauchy RS compute: +42.5 ℭ earned!'), findsOneWidget);

    expect(find.textContaining('Simulated Cauchy RS Parity Encoding'), findsWidgets);
  });

  testWidgets(
      'CreditWalletDialog shows attested split and surfaces payout-disabled reason',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: CreditWalletDialog(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Attested/unattested split rendered under the balance.
    expect(find.textContaining('Attested:'), findsOneWidget);
    expect(find.textContaining('Unattested:'), findsOneWidget);

    // Expand the crypto bridge section.
    await tester.ensureVisible(find.text('Configure'));
    await tester.tap(find.text('Configure'));
    await tester.pumpAndSettle();

    // Export is blocked at the service layer (ALX-010): the snackbar must
    // surface the rejection reason verbatim, not crash or fake a success.
    await tester.ensureVisible(find.text('Export 10 ℭ (100 Sats)'));
    await tester.tap(find.text('Export 10 ℭ (100 Sats)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.text(CryptoBridgeService.payoutsDisabledReason),
      findsOneWidget,
    );
    expect(find.textContaining('Exported 100 Sats'), findsNothing);
  });

  testWidgets('SponsorshipCard honors opt-in privacy gate', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: SponsorshipCard(
              category: 'technology',
              tags: ['privacy'],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // When opted out (default), zero visual elements rendered
    expect(find.text('ETHICAL SPONSOR'), findsNothing);
    expect(find.text('Electronic Frontier Foundation'), findsNothing);

    // Enable opt-in via container
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(sponsorshipServiceProvider).toggleOptIn(true);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: SponsorshipCard(
              category: 'technology',
              tags: ['privacy'],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Now renders ethical sponsor badge
    expect(find.text('ETHICAL SPONSOR'), findsOneWidget);
    expect(find.text('Electronic Frontier Foundation'), findsOneWidget);
    expect(find.text('+8.5 ℭ Kickback'), findsOneWidget);
  });
}
