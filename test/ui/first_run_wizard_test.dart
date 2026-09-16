import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/ui/onboarding/first_run_wizard_dialog.dart';
import 'package:alexandria/ui/theme/app_theme.dart';

void main() {
  testWidgets('FirstRunWizardDialog renders Alexandria Core Team banner and navigates all steps',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    bool completed = false;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: FirstRunWizardDialog(
              onComplete: () => completed = true,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Step 0: Welcome & Protocol Governance
    expect(find.text('Alexandria Onboarding'), findsOneWidget);
    expect(find.text('Decentralized Archival Infrastructure & Common Heritage'), findsOneWidget);
    expect(find.text('Alexandria Protocol Governance'), findsOneWidget);
    expect(find.text('Unanimously Ratified Protocol'), findsOneWidget);
    expect(find.text('Coherence'), findsOneWidget);
    expect(find.text('Capability'), findsOneWidget);
    expect(find.text('Safety'), findsOneWidget);
    expect(find.text('Efficiency'), findsOneWidget);
    expect(find.text('Evolution'), findsOneWidget);

    // Navigate to Step 1: Genesis Grant
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Your Common Heritage Grant'), findsOneWidget);
    expect(find.textContaining('100.0 ℭ'), findsOneWidget);
    expect(find.textContaining('Storage Pillar'), findsOneWidget);
    expect(find.textContaining('Compute Pillar'), findsOneWidget);

    // Navigate to Step 2: Storage Baseline Allocation
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Proof of Common Heritage (PoCH)'), findsOneWidget);
    expect(find.text('1.0 GB'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);

    // Navigate to Step 3: Starter Seed Packs
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('1-Click Starter Archive Packs'), findsOneWidget);
    expect(find.textContaining('Landmark Open Science'), findsOneWidget);
    expect(find.textContaining('Clean Slate (Start Empty)'), findsOneWidget);

    // Select Clean Slate and Complete Onboarding
    await tester.tap(find.textContaining('Clean Slate (Start Empty)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Launch Archive'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
  });
}
