import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/ui/agent/agent_network_dialog.dart';
import 'package:alexandria/ui/theme/app_theme.dart';

void main() {
  testWidgets('AgentNetworkDialog renders sections, submolts, and toggles steward',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: AgentNetworkDialog(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify Header & Sections
    expect(find.text('Autonomous Agent Network (ALX-006)'), findsOneWidget);
    expect(find.text('Autonomous Preservation Steward'), findsOneWidget);
    expect(find.text('Beacon v2 Agent Identity (Ed25519)'), findsOneWidget);
    expect(find.text('Moltbook Agent Social Transport'), findsOneWidget);
    expect(find.text('Alexandria MCP Tool Suite (8 Registered Tools)'), findsOneWidget);

    // 2. Verify Submolt filter chips
    expect(find.text('m/alexandria-bounties'), findsOneWidget);
    expect(find.text('m/open-science'), findsOneWidget);
    expect(find.text('m/preservation-alerts'), findsOneWidget);

    // 3. Switch Submolt to m/open-science
    await tester.tap(find.text('m/open-science'));
    await tester.pumpAndSettle();

    expect(find.textContaining('PLOS Computational Biology'), findsOneWidget);

    // 4. Toggle Autonomous Preservation Steward switch
    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    // Verify steward started and metric pills exist
    expect(find.text('Bounties Fulfilled'), findsOneWidget);
    expect(find.text('Compute Cycles'), findsOneWidget);
  });
}
