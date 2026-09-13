import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/ui/plugin_screen.dart';
import 'package:alexandria/ui/plugins/doi_harvester_dialog.dart';
import 'package:alexandria/ui/theme/app_theme.dart';

void main() {
  testWidgets('DoiHarvesterDialog renders and handles sample DOIs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: DoiHarvesterDialog(),
          ),
        ),
      ),
    );

    expect(find.text('DOI SCIENTIFIC HARVESTER'), findsOneWidget);
    expect(find.text('Enter DOI(s) or Paste Bibliography / Markdown:'), findsOneWidget);
    expect(find.text('Sample DOIs'), findsOneWidget);
    expect(find.text('Download Open-Access PDF'), findsOneWidget);

    // Tap Sample DOIs button
    await tester.tap(find.text('Sample DOIs'));
    await tester.pumpAndSettle();

    // Check that DOIs were detected and indicator displayed
    expect(find.text('3 DOI(s) ready for safe-harbor preservation'), findsOneWidget);
    expect(find.text('Harvest 3 Works'), findsOneWidget);
  });

  testWidgets('PluginScreen displays DOI Harvester card and launches dialog', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const PluginScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('THE GARDEN'), findsOneWidget);
    expect(find.text('DOI Scientific Harvester'), findsOneWidget);
    expect(find.text('Launch Harvester'), findsOneWidget);

    // Tap Launch Harvester
    await tester.tap(find.text('Launch Harvester'));
    await tester.pumpAndSettle();

    // Verify dialog opened
    expect(find.byType(DoiHarvesterDialog), findsOneWidget);
    expect(find.text('DOI SCIENTIFIC HARVESTER'), findsOneWidget);
  });
}
