import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart';
import 'package:alexandria/logic/content_repository.dart';
import 'package:alexandria/models/library_models.dart';
import 'package:alexandria/providers/library_providers.dart';
import 'package:alexandria/services/agent/agent_steward_service.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/poch_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/plugin_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:alexandria/services/sync_service.dart';
import 'package:alexandria/services/tor_service.dart';
import 'package:alexandria/ui/agent/agent_network_dialog.dart';
import 'package:alexandria/ui/agent/mcp_config_export_dialog.dart';
import 'package:alexandria/ui/credits/credit_wallet_dialog.dart';
import 'package:alexandria/ui/library/content_viewer_screen.dart';
import 'package:alexandria/ui/library/library_overview_screen.dart';
import 'package:alexandria/ui/plugin_screen.dart';
import 'package:alexandria/ui/plugins/doi_harvester_dialog.dart';
import 'package:alexandria/ui/scriptorium/creation_wizard.dart';
import 'package:alexandria/ui/settings/settings_screen.dart';
import 'package:alexandria/ui/theme/app_theme.dart';

import '../network_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> bigSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('PluginScreen', () {
    Widget subject({PluginService? service}) {
      return ProviderScope(
        overrides: service == null
            ? const []
            : [pluginServiceProvider.overrideWith((ref) => service)],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const PluginScreen(),
        ),
      );
    }

    testWidgets('plugins tab renders built-in card and launches harvester',
        (tester) async {
      await bigSurface(tester);
      await tester.pumpWidget(subject());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The built-in DOI harvester registers itself on service init.
      expect(find.text('THE GARDEN'), findsOneWidget);
      expect(find.text('Launch Harvester'), findsOneWidget);

      await tester.tap(find.text('Launch Harvester'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(DoiHarvesterDialog), findsOneWidget);
      // Dismiss the dialog.
      Navigator.of(tester.element(find.byType(DoiHarvesterDialog))).pop();
      await tester.pump();
    });

    testWidgets('toggle switch flips the plugin flag in the service',
        (tester) async {
      await bigSurface(tester);
      final service = PluginService();
      await tester.pumpWidget(subject(service: service));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The card reads plugin.enabled at build time - PluginService is
      // not a ChangeNotifier, so assert the flag flips on the service,
      // then force a fresh mount (an identical pumpWidget does not
      // rebuild the const widget subtree).
      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      final installed = service.plugins
          .firstWhere((p) => p.id == 'org.alexandria.plugin.doi-harvester');
      expect(installed.enabled, isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(subject(service: service));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Launch Harvester'), findsNothing);
    });

    testWidgets('plugin install dialog: examples, invalid, success, cancel',
        (tester) async {
      await bigSurface(tester);
      await tester.pumpWidget(subject());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Open install dialog on the plugins tab.
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Install Plugin'), findsOneWidget);

      // Example button fills the manifest field.
      await tester.tap(find.text('Zotero'));
      await tester.pump();
      await tester.tap(find.text('Install'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Installed:'), findsOneWidget);
      // Let the first snackbar expire - ScaffoldMessenger queues the
      // next one behind its 4-second display duration.
      await tester.pump(const Duration(seconds: 4));

      // Invalid manifest surfaces the danger snackbar.
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField).first, '{broken');
      await tester.tap(find.text('Install'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Invalid manifest'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));

      // Cancel dismisses.
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('themes tab: empty state, install, activate, invalid',
        (tester) async {
      await bigSurface(tester);
      final service = PluginService();
      await tester.pumpWidget(subject(service: service));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('THEMES'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('No custom themes'), findsOneWidget);

      // Install dialog shows the theme title variant.
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Install Theme'), findsOneWidget);

      // Invalid theme manifest.
      await tester.enterText(find.byType(TextField).first, '{broken');
      await tester.tap(find.text('Install'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Invalid theme manifest'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Valid theme - one bad hex color exercises the parse fallback.
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byType(TextField).first,
        jsonEncode({
          'id': 'theme.x',
          'name': 'Theme X',
          'version': '1.0.0',
          'author': 'tester',
          'colors': {'a': '#FF0000', 'b': 'not-a-color', 'c': '#00FF00'},
        }),
      );
      await tester.tap(find.text('Install'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Installed: Theme X'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));

      // The themes list only re-reads pluginService.themes on rebuild -
      // bounce through the plugins tab to force it.
      await tester.tap(find.text('PLUGINS'));
      await tester.pump();
      await tester.tap(find.text('THEMES'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Theme X'), findsOneWidget);

      // Tapping the card activates the theme - PluginService is not a
      // ChangeNotifier, so assert on the service, then force a fresh
      // mount for the ACTIVE badge render.
      await tester.tap(find.text('Theme X'));
      await tester.pump();
      expect(service.activeTheme?.id, 'theme.x');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(subject(service: service));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('THEMES'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('ACTIVE'), findsOneWidget);
    });

    testWidgets('empty plugin list renders the placeholder', (tester) async {
      await bigSurface(tester);
      final service = PluginService()
        ..uninstallPlugin('org.alexandria.plugin.doi-harvester');
      await tester.pumpWidget(subject(service: service));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('No plugins installed'), findsOneWidget);
    });
  });

  group('LibraryOverviewScreen item card', () {
    testWidgets('tapping a recent item opens the content viewer',
        (tester) async {
      await bigSurface(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          syncStatusProvider.overrideWith((ref) => SyncStatus.idle),
          libraryDashboardProvider.overrideWith((ref) async =>
              const LibraryStats(
                  totalItems: 1, totalSize: '1 KB', networkStatus: 'ok')),
          recentItemsProvider.overrideWith((ref) async =>
              const [LibraryItem(cid: 'c-tap', title: 'TapMe', author: 'a')]),
          newArrivalsProvider.overrideWith((ref) async => const []),
          sidebarVisibleProvider.overrideWith((ref) => false),
          currentDocumentProvider.overrideWith(
            (ref, cid) async => DocumentStream(
              title: 'Tapped Doc',
              content: 'body',
              format: 'md',
              cid: cid,
            ),
          ),
          documentVersionsProvider
              .overrideWith((ref, cid) async => const <ContentVersion>[]),
          annotationsProvider
              .overrideWith((ref, cid) => Future.value(const <Annotation>[])),
          contentIntegrityProvider.overrideWith(
            (ref, cid) => Future.value(const ContentIntegrityReport(
                cid: 'x', payloadHashOk: true, signatureValid: null)),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const LibraryOverviewScreen(),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('TapMe'), findsOneWidget);

      await tester.tap(find.text('TapMe'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ContentViewerScreen), findsOneWidget);
    });
  });

  group('CreationWizard extra branches', () {
    testWidgets('browse button and mid-step cancel', (tester) async {
      await bigSurface(tester);
      await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: CreationWizard())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Browse button's empty handler still counts as an interaction.
      await tester.tap(find.text('Browse Files'));
      await tester.pump();

      Stepper stepper() => tester.widget<Stepper>(find.byType(Stepper));
      stepper().onStepContinue!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Cancel at step 1 decrements back to step 0 (not a pop).
      stepper().onStepCancel!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(Stepper), findsOneWidget);
      expect(find.text('Add Document to Library'), findsOneWidget);
    });
  });

  group('SettingsScreen', () {
    Widget subject({TorStatus torStatus = TorStatus.disabled}) {
      return ProviderScope(
        overrides: [
          secureStorageServiceProvider
              .overrideWith((ref) => FakeSecureStorageService()),
          ipfsServiceProvider.overrideWith((ref) => FakeIpfsService(ref)),
          torServiceProvider.overrideWith(
              (ref) => FakeTorService(ref.read(secureStorageServiceProvider))),
          torStatusProvider.overrideWith((ref) => torStatus),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const SettingsScreen(),
        ),
      );
    }

    testWidgets('emergency wipe dialog: cancel and confirm', (tester) async {
      await bigSurface(tester);
      await tester.pumpWidget(subject());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('Emergency Data Wipe'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Confirm Emergency Data Wipe'), findsOneWidget);

      // Cancel branch.
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Confirm Emergency Data Wipe'), findsNothing);

      // Confirm branch → snackbar.
      await tester.tap(find.text('Emergency Data Wipe'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Confirm Wipe'));
      await tester.pump();
      expect(find.text('Data wipe completed.'), findsOneWidget);
    });

    testWidgets('theme dropdown, reduced-motion and tor switches, prune',
        (tester) async {
      await bigSurface(tester);
      await tester.pumpWidget(subject());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Theme mode dropdown.
      await tester.tap(find.text('System'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Dark Void').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Reduced motion switch (first SwitchListTile on screen).
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Tor switch → FakeTorService.enable() → status row updates.
      await tester.tap(find.byType(SwitchListTile).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Connected via Tor'), findsOneWidget);

      // Prune storage → snackbar.
      await tester.tap(find.text('Prune'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          find.text('Storage cleanup completed successfully.'), findsOneWidget);
    });

    testWidgets(
        'appbar actions open agent dialog, wallet and plugin '
        'screen', (tester) async {
      await bigSurface(tester);
      final creditService = CreditService(initialBalance: 50);
      final pochService = PoCHService();
      final moltbook = MoltbookService(creditService: creditService);
      final steward = AgentStewardService(
        creditService: creditService,
        pochService: pochService,
        moltbookService: moltbook,
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          secureStorageServiceProvider
              .overrideWith((ref) => FakeSecureStorageService()),
          ipfsServiceProvider.overrideWith((ref) => FakeIpfsService(ref)),
          torServiceProvider.overrideWith(
              (ref) => FakeTorService(ref.read(secureStorageServiceProvider))),
          creditServiceProvider.overrideWith((_) => creditService),
          pochServiceProvider.overrideWith((_) => pochService),
          moltbookServiceProvider.overrideWith((_) => moltbook),
          agentStewardServiceProvider.overrideWith((_) => steward),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const SettingsScreen(),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Agent network dialog.
      await tester.tap(find.byIcon(Icons.smart_toy_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AgentNetworkDialog), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Credit wallet dialog.
      await tester.tap(find.byIcon(Icons.account_balance_wallet_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CreditWalletDialog), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Plugin screen navigation.
      await tester.tap(find.byIcon(Icons.extension_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PluginScreen), findsOneWidget);
    });

    testWidgets('tor status row variants render', (tester) async {
      await bigSurface(tester);
      const expected = {
        TorStatus.disabled: 'Tor Disabled',
        TorStatus.connecting: 'Connecting to Tor Network...',
        TorStatus.connected: 'Connected via Tor (127.0.0.1:9050)',
        TorStatus.error: 'Tor Connection Failed — Check your Tor daemon',
      };
      for (final status in TorStatus.values) {
        await tester.pumpWidget(ProviderScope(
          key: ValueKey('settings-${status.name}'),
          overrides: [
            secureStorageServiceProvider
                .overrideWith((ref) => FakeSecureStorageService()),
            ipfsServiceProvider.overrideWith((ref) => FakeIpfsService(ref)),
            torServiceProvider.overrideWith((ref) =>
                FakeTorService(ref.read(secureStorageServiceProvider))),
            torStatusProvider.overrideWith((ref) => status),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const SettingsScreen(),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text(expected[status]!), findsOneWidget);
      }
    });
  });

  group('AgentNetworkDialog', () {
    (CreditService, PoCHService, MoltbookService, AgentStewardService)
        makeServices({double balance = 100.0}) {
      final creditService = CreditService(initialBalance: balance);
      final pochService = PoCHService();
      final moltbook = MoltbookService(creditService: creditService);
      moltbook.seedDemoPostsForTest();
      final steward = AgentStewardService(
        creditService: creditService,
        pochService: pochService,
        moltbookService: moltbook,
      );
      return (creditService, pochService, moltbook, steward);
    }

    Widget dialogHost(
      AgentStewardService steward,
      MoltbookService moltbook,
      CreditService credit,
      PoCHService poch,
    ) {
      return ProviderScope(
        overrides: [
          creditServiceProvider.overrideWith((_) => credit),
          pochServiceProvider.overrideWith((_) => poch),
          moltbookServiceProvider.overrideWith((_) => moltbook),
          agentStewardServiceProvider.overrideWith((_) => steward),
        ],
        child: const MaterialApp(
          home: Scaffold(body: AgentNetworkDialog()),
        ),
      );
    }

    testWidgets(
        'feed interactions: chips, upvote, unfunded claim, copy, '
        'export config, activity log', (tester) async {
      await bigSurface(tester);
      final (credit, poch, moltbook, steward) = makeServices();

      // Start then immediately stop: seeds the activity log section
      // without leaving a periodic timer that would stall pumpAndSettle.
      steward.startSteward();
      steward.stopSteward();

      await tester.pumpWidget(dialogHost(steward, moltbook, credit, poch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Recent Agent Activity:'), findsOneWidget);
      expect(
          find.text('[BOUNTY: CRITICAL] Endangered Quantum Physics '
              'Preprint (1998)'),
          findsOneWidget);

      // Seeded bounties are unfunded → disabled 'Unfunded' buttons.
      expect(find.text('Unfunded'), findsWidgets);

      // Upvote the first post.
      await tester.tap(find.byIcon(Icons.arrow_upward).first);
      await tester.pump();

      // Copy agent ID (unawaited Clipboard.setData → snackbar).
      await tester.tap(find.widgetWithText(OutlinedButton, 'Copy'));
      await tester.pump();
      expect(find.text('Agent ID copied to clipboard'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));

      // Submolt chip switching.
      await tester.tap(find.text('m/open-science'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('PLOS Computational Biology'), findsOneWidget);
      await tester.tap(find.text('m/preservation-alerts'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('m/alexandria-bounties'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Export Config opens the MCP config dialog - scroll it into
      // view first (it sits below the fold inside the scrollable).
      await tester.ensureVisible(find.text('Export Config'));
      await tester.pump();
      await tester.tap(find.text('Export Config'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(McpConfigExportDialog), findsOneWidget);
    });

    testWidgets('bounty dialog validation and insufficient-balance error',
        (tester) async {
      await bigSurface(tester);
      final (credit, poch, moltbook, steward) = makeServices(balance: 0.0);
      await tester.pumpWidget(dialogHost(steward, moltbook, credit, poch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Post Bounty'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Post Preservation Bounty (Moltbook)'), findsOneWidget);

      // Empty fields: publish is a silent no-op, dialog stays.
      await tester.tap(find.text('Publish Bounty'));
      await tester.pump();
      expect(find.text('Post Preservation Bounty (Moltbook)'), findsOneWidget);

      // Filled fields but zero balance → error snackbar.
      await tester.enterText(
          find.widgetWithText(TextField, 'Title / Paper Name'), 'Paper X');
      await tester.enterText(
          find.widgetWithText(TextField, 'Endangered CIDv1'), 'bafk_x');
      await tester.tap(find.text('Publish Bounty'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Error:'), findsOneWidget);
    });

    testWidgets('funded bounty posts, then self-claim is refused',
        (tester) async {
      await bigSurface(tester);
      final (credit, poch, moltbook, steward) = makeServices();
      await tester.pumpWidget(dialogHost(steward, moltbook, credit, poch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Post Bounty'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
          find.widgetWithText(TextField, 'Title / Paper Name'), 'Paper Y');
      await tester.enterText(
          find.widgetWithText(TextField, 'Endangered CIDv1'), 'bafk_y');
      await tester.tap(find.text('Publish Bounty'));
      await tester.pump();
      // Signing + escrow is async; give it real frames.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.textContaining('broadcast to Moltbook'), findsOneWidget);

      // The freshly posted, funded bounty resolves via the beacon
      // payload id and shows an enabled 'Claim Bounty' button - the
      // self-claim guard then refuses it.
      await tester.pump(const Duration(seconds: 4));
      final claim = find.text('Claim Bounty');
      expect(claim, findsOneWidget);
      await tester.tap(claim);
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.textContaining('Claim failed'), findsOneWidget);
    });
  });
}
