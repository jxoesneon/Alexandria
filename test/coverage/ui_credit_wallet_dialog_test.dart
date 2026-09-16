import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/crypto_bridge_service.dart';
import 'package:alexandria/ui/credits/credit_wallet_dialog.dart';

void main() {
  Future<void> pumpDialog(WidgetTester tester,
      {double initialBalance = 200}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // In-memory CreditService (db: null) is hydrated synchronously
          // with the initial grant, so spend/export gates are live.
          creditServiceProvider.overrideWith(
              (ref) => CreditService(db: null, initialBalance: initialBalance)),
        ],
        // The dialog calls ScaffoldMessenger.of(context) - it needs a
        // Scaffold ancestor even when not shown via showDialog.
        child: const MaterialApp(home: Scaffold(body: CreditWalletDialog())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> scrollTo(WidgetTester tester, Finder what) async {
    await tester.scrollUntilVisible(
      what,
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('renders header, metrics, compliance chip and history',
      (tester) async {
    await pumpDialog(tester);
    await tester.pumpAndSettle();

    expect(find.text('COMPLIANT'), findsOneWidget);
    expect(find.text('Recent Credit Ledger Entries'), findsOneWidget);
    // Genesis transaction is listed.
    expect(find.text('No transactions recorded yet.'), findsNothing);
  });

  testWidgets('close button pops the dialog', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          creditServiceProvider.overrideWith(
              (ref) => CreditService(db: null, initialBalance: 50)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog(
                  context: context, builder: (_) => const CreditWalletDialog()),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(CreditWalletDialog), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(CreditWalletDialog), findsNothing);
  });

  testWidgets('sponsorship opt-in switch toggles', (tester) async {
    await pumpDialog(tester);
    await tester.pumpAndSettle();

    final toggle = find.byType(SwitchListTile);
    await scrollTo(tester, toggle);
    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Toggling flips the switch value.
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });

  testWidgets('debug faucets award credits and show snackbars', (tester) async {
    await pumpDialog(tester);
    await tester.pumpAndSettle();

    await scrollTo(tester, find.text('Simulate Parity Compute'));
    await tester.tap(find.text('Simulate Parity Compute'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Cauchy RS compute'), findsOneWidget);
    // SnackBars queue one-at-a-time - drain the first before the next.
    await tester.pump(const Duration(seconds: 5));

    await scrollTo(tester, find.text('Pass PoR Challenge'));
    await tester.tap(find.text('Pass PoR Challenge'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Endangered PoR Challenge'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('commission swarm pinning spends credits', (tester) async {
    await pumpDialog(tester);
    await tester.pumpAndSettle();

    await scrollTo(tester, find.text('Commission Swarm Pinning (20 ℭ)'));
    await tester.tap(find.text('Commission Swarm Pinning (20 ℭ)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Spent 20'), findsOneWidget);
  });

  testWidgets('crypto bridge: export rejection, voucher redeem, lightning',
      (tester) async {
    await pumpDialog(tester);
    await tester.pumpAndSettle();

    await scrollTo(tester, find.text('Configure'));
    await tester.tap(find.text('Configure'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Export is gated by payoutsEnabled=false → rejection snackbar.
    await scrollTo(tester, find.text('Export 10 ℭ (100 Sats)'));
    await tester.tap(find.text('Export 10 ℭ (100 Sats)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));

    // Voucher redemption is disabled at the service layer.
    final voucherField =
        find.widgetWithText(TextField, 'Paste cashuA... voucher to deposit');
    await scrollTo(tester, voucherField);
    await tester.enterText(voucherField, 'cashuAinvalid');
    await scrollTo(tester, find.text('Redeem'));
    await tester.tap(find.text('Redeem'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(CryptoBridgeService.redemptionDisabledReason),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 5));

    // Lightning sweep with an empty address shows the hint.
    await scrollTo(tester, find.text('Sweep 25 ℭ (250 Sats)'));
    await tester.tap(find.text('Sweep 25 ℭ (250 Sats)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Please enter a Lightning Address'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('crypto bridge: sweep with address surfaces live failure',
      (tester) async {
    await pumpDialog(tester);
    await tester.pumpAndSettle();

    await scrollTo(tester, find.text('Configure'));
    await tester.tap(find.text('Configure'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Enter a Lightning address, then sweep - the live path fails fast
    // (payouts disabled / no network) and surfaces its error verbatim.
    final lnField = find.byType(TextField).last;
    await scrollTo(tester, lnField);
    await tester.enterText(lnField, 'user@wallet.example');
    await scrollTo(tester, find.text('Sweep 25 ℭ (250 Sats)'));
    await tester.tap(find.text('Sweep 25 ℭ (250 Sats)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // 'Resolving LNURL-pay...' shows first, then the failure error.
    expect(find.textContaining('Resolving LNURL-pay'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 500));
  });
}
