import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/agent/agent_steward_service.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/poch_service.dart';
import 'package:alexandria/ui/agent/agent_network_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AgentNetworkDialog Tests', () {
    testWidgets('renders dialog header, steward status, and controls',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final creditService = CreditService();
      final pochService = PoCHService();
      final moltbook = MoltbookService(creditService: creditService);
      final steward = AgentStewardService(
        creditService: creditService,
        pochService: pochService,
        moltbookService: moltbook,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            creditServiceProvider.overrideWith((_) => creditService),
            pochServiceProvider.overrideWith((_) => pochService),
            moltbookServiceProvider.overrideWith((_) => moltbook),
            agentStewardServiceProvider.overrideWith((_) => steward),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: AgentNetworkDialog(),
            ),
          ),
        ),
      );

      expect(find.text('Autonomous Agent Network (ALX-006)'), findsOneWidget);
      expect(find.text('Autonomous Preservation Steward'), findsOneWidget);
      expect(find.text('Bounties Fulfilled'), findsOneWidget);
      expect(find.text('Compute Cycles'), findsOneWidget);
      expect(find.text('Credits Earned'), findsOneWidget);

      // Claimed build provenance renders as advisory display only —
      // including the claimed client version (ALX-012 B3-lite). In tests
      // no dart-defines are injected, so the dev sentinels are shown.
      expect(find.textContaining('Claimed build:'), findsOneWidget);
      expect(find.textContaining('client vdev'), findsOneWidget);

      // Toggle steward switch
      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);
      await tester.tap(switchFinder);
      await tester.pump();
      expect(steward.isRunning, isTrue);

      await tester.tap(switchFinder);
      await tester.pump();
      expect(steward.isRunning, isFalse);
    });

    testWidgets('supports static AgentNetworkDialog.show and close button',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final creditService = CreditService();
      final pochService = PoCHService();
      final moltbook = MoltbookService(creditService: creditService);
      final steward = AgentStewardService(
        creditService: creditService,
        pochService: pochService,
        moltbookService: moltbook,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            creditServiceProvider.overrideWith((_) => creditService),
            pochServiceProvider.overrideWith((_) => pochService),
            moltbookServiceProvider.overrideWith((_) => moltbook),
            agentStewardServiceProvider.overrideWith((_) => steward),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => AgentNetworkDialog.show(context),
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Autonomous Agent Network (ALX-006)'), findsOneWidget);

      // Copy Agent ID
      final copyBtn = find.widgetWithText(OutlinedButton, 'Copy');
      if (copyBtn.evaluate().isNotEmpty) {
        await tester.tap(copyBtn);
        await tester.pump();
        expect(find.text('Agent ID copied to clipboard'), findsOneWidget);
      }

      // Open Post Bounty dialog and cancel
      final postBountyBtn = find.text('Post Bounty');
      expect(postBountyBtn, findsOneWidget);
      await tester.tap(postBountyBtn);
      await tester.pumpAndSettle();

      expect(find.text('Post Preservation Bounty (Moltbook)'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Open Post Bounty dialog and publish
      await tester.tap(postBountyBtn);
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Title / Paper Name'), 'Test Paper');
      await tester.enterText(find.widgetWithText(TextField, 'Endangered CIDv1'),
          'bafytestcid123456');
      await tester.tap(find.text('Publish Bounty'));
      await tester.pumpAndSettle();

      expect(find.text('Post Preservation Bounty (Moltbook)'), findsNothing);

      // Tap close button on main dialog
      final closeBtn = find.byIcon(Icons.close);
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      expect(find.text('Autonomous Agent Network (ALX-006)'), findsNothing);
    });
  });
}
