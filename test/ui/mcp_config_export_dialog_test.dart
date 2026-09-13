import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/ui/agent/mcp_config_export_dialog.dart';
import 'package:alexandria/ui/theme/app_theme.dart';

void main() {
  testWidgets('McpConfigExportDialog renders tabs, Governance review, and config content',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final tools = [
      {
        'name': 'alexandria_search_archive',
        'description': 'Search the library',
      },
      {
        'name': 'alexandria_ingest_doi',
        'description': 'Ingest a scientific DOI',
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: McpConfigExportDialog(tools: tools),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Header and Review verification
    expect(find.text('Connect External AI Agents (ALX-006)'), findsOneWidget);
    expect(find.text('Governance — Lord of Wisdom Orchestration'), findsOneWidget);
    expect(find.text('Claude Desktop'), findsOneWidget);
    expect(find.text('Gemini CLI'), findsOneWidget);
    expect(find.text('Cursor / Windsurf'), findsOneWidget);
    expect(find.textContaining('Tool Schemas'), findsOneWidget);

    // 2. Active Tab contains claude config
    expect(find.text('claude_desktop_config.json'), findsOneWidget);
    expect(find.textContaining('alexandria_mcp_server.js'), findsOneWidget);

    // 3. Switch to Gemini CLI tab
    await tester.tap(find.text('Gemini CLI'));
    await tester.pumpAndSettle();

    expect(find.text('gemini_config.json'), findsOneWidget);
    expect(find.textContaining('protocol-governance'), findsOneWidget);

    // 4. Verify Copy Button exists
    expect(find.text('Copy Active Config'), findsOneWidget);
  });
}
