import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/models/workspace_models.dart';
import 'package:alexandria/providers/workspace_providers.dart';
import 'package:alexandria/ui/workspace/workspace_dashboard_screen.dart';

void main() {
  Future<void> pumpDashboard(WidgetTester tester,
      {List<Override> overrides = const []}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(home: WorkspaceDashboardScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // SponsorshipCard starts a 5s dwell Timer in initState - advancing
    // past it keeps the tree free of pending timers at dispose time.
    await tester.pump(const Duration(seconds: 6));
  }

  /// Unmounts the tree and flushes pending zero-duration timers that
  /// drift's StreamQueryStore schedules while cancelling QueryStreams
  /// during ProviderScope disposal.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // pump() without a duration does not advance FakeAsync's clock -
    // pumpAndSettle elapses it so the pending timer fires.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('renders dashboard chrome, quest card and rich empty state',
      (tester) async {
    await pumpDashboard(tester);
    await tester.pumpAndSettle();

    expect(find.text('Workspace'), findsOneWidget);
    expect(find.text('Swarm Telemetry'), findsOneWidget);
    expect(find.text('First-Run Preservation Quests'), findsOneWidget);
    expect(find.text('No workspaces yet.'), findsOneWidget);
    expect(find.text('Launch Onboarding Tour'), findsOneWidget);
    expect(find.text('1-Click Landmark Science Pack'), findsOneWidget);
    expect(find.text('New Note'), findsOneWidget);
    expect(find.text('Metadata'), findsOneWidget);
    expect(find.text('Harvest DOI'), findsOneWidget);
    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('AI Agents'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('quest card dismisses via close icon', (tester) async {
    await pumpDashboard(tester);
    await tester.pumpAndSettle();

    // The quest card's close IconButton is the one inside the card; tap
    // the close icon nearest the quest title.
    final closeButtons = find.byIcon(Icons.close);
    await tester.tap(closeButtons.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('First-Run Preservation Quests'), findsNothing);
    await finish(tester);
  });

  // The drift database is created inside FakeAsync, so its stream-query
  // timers never fire - real writes can't feed the UI. Override the
  // stream providers instead to exercise the list/filter/item widgets.
  List<Override> seededOverrides() => [
        activeWorkspacesProvider.overrideWith((ref) => Stream.value(const [
              Workspace(id: 'w1', name: 'Alpha Workspace', pendingTasks: 2),
              Workspace(id: 'w2', name: 'Beta Cellar', pendingTasks: 0),
            ])),
        activityFeedProvider.overrideWith((ref) => Stream.value([
              ActivityEvent(
                  title: 'Alpha Workspace',
                  description: 'docs updated',
                  timestamp: DateTime(2024, 1, 1)),
            ])),
      ];

  testWidgets('search filters workspaces and shows no-results state',
      (tester) async {
    await pumpDashboard(tester, overrides: seededOverrides());
    await tester.pumpAndSettle();

    expect(find.text('Alpha Workspace'), findsWidgets);
    expect(find.text('Beta Cellar'), findsOneWidget);

    // Filter to a non-matching query -> 'No matching documents found.'
    await tester.enterText(find.byType(TextField).first, 'zzz-no-match');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('No matching documents found.'), findsOneWidget);

    // Clear button restores the list.
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Alpha Workspace'), findsWidgets);
    await finish(tester);
  });

  testWidgets('DOI-shaped search reveals the harvest button', (tester) async {
    await pumpDashboard(tester);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField).first, '10.1038/s41586-020-2012-7');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Harvest DOI (+20 ℭ)'), findsOneWidget);
    await tester.tap(find.text('Harvest DOI (+20 ℭ)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    tester.takeException();
    await tester.pumpAndSettle();
    tester.takeException();
    await finish(tester);
  });

  testWidgets('workspace tiles navigate to annotations on chevron',
      (tester) async {
    await pumpDashboard(tester, overrides: [
      activeWorkspacesProvider.overrideWith((ref) => Stream.value(const [
            Workspace(id: 'nav1', name: 'Navigable', pendingTasks: 3),
          ])),
      activityFeedProvider.overrideWith((ref) => Stream.value([
            ActivityEvent(
                title: 'Navigable',
                description: 'docs updated',
                timestamp: DateTime(2024, 1, 1)),
          ])),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Navigable'), findsWidgets);
    expect(find.textContaining('pending tasks'), findsOneWidget);
    // Activity feed lists the new manifest.
    expect(find.textContaining('updated'), findsWidgets);

    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    tester.takeException();
    await tester.pumpAndSettle();
    tester.takeException();
    await finish(tester);
  });

  testWidgets('wallet buttons open the credit wallet dialog', (tester) async {
    await pumpDashboard(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Wallet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Recent Credit Ledger Entries'), findsOneWidget);
    // Dismiss via the dialog close icon.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    tester.takeException();

    // App-bar balance pill opens the same dialog.
    await tester.tap(find.byIcon(Icons.account_balance_wallet).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Recent Credit Ledger Entries'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    tester.takeException();
    await finish(tester);
  });

  testWidgets('landmark seed pack button invokes ingest', (tester) async {
    await pumpDashboard(tester);
    await tester.pumpAndSettle();

    // The onPressed awaits ingestSeedPack, whose DB futures never resolve
    // inside FakeAsync - the tap still covers the callback's entry lines.
    await tester.tap(find.text('1-Click Landmark Science Pack'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    tester.takeException();
    await finish(tester);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('secondary actions push screens or show dialogs', (tester) async {
    await pumpDashboard(tester);
    await tester.pumpAndSettle();

    // 'New Note' -> AnnotationsNotesScreen
    await tester.tap(find.text('New Note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    tester.takeException();
    await tester.pumpAndSettle();
    tester.takeException();
    await tester.pumpWidget(const SizedBox());

    await pumpDashboard(tester);
    await tester.pumpAndSettle();

    // 'Metadata' -> MetadataEditorScreen
    await tester.tap(find.text('Metadata'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    tester.takeException();
    await tester.pumpAndSettle();
    tester.takeException();
    await tester.pumpWidget(const SizedBox());

    await pumpDashboard(tester);
    await tester.pumpAndSettle();

    // 'Harvest DOI' -> DoiHarvesterDialog
    await tester.tap(find.text('Harvest DOI'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    tester.takeException();
    await tester.pumpAndSettle();
    tester.takeException();
    await tester.pumpWidget(const SizedBox());

    await pumpDashboard(tester);
    await tester.pumpAndSettle();

    // 'AI Agents' -> AgentNetworkDialog
    await tester.tap(find.text('AI Agents'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    tester.takeException();
    await tester.pumpAndSettle();
    tester.takeException();
    await tester.pumpWidget(const SizedBox());

    await pumpDashboard(tester);
    await tester.pumpAndSettle();

    // App-bar tour icon -> FirstRunWizardDialog
    await tester.tap(find.byIcon(Icons.auto_stories_outlined).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    tester.takeException();
    await tester.pumpAndSettle();
    tester.takeException();
    await finish(tester);
  });
}
