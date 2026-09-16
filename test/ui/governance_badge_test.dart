import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/ui/common/governance_badge.dart';
import 'package:alexandria/ui/theme/app_theme.dart';

void main() {
  testWidgets('GovernanceBanner renders 5 voices and opens voice detail dialog',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              children: [
                GovernanceBanner(),
                SizedBox(height: 20),
                GovernancePillRow(),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify Banner Title & 5 Voices
    expect(find.text('Alexandria Protocol Governance'), findsOneWidget);
    expect(find.text('Unanimously Ratified Protocol'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);

    expect(find.text('Coherence'), findsOneWidget);
    expect(find.text('Capability'), findsOneWidget);
    expect(find.text('Safety'), findsOneWidget);
    expect(find.text('Efficiency'), findsOneWidget);
    expect(find.text('Evolution'), findsOneWidget);

    // 2. Tap on "Coherence" to open modal details
    await tester.tap(find.text('Coherence'));
    await tester.pumpAndSettle();

    expect(find.text('Coherence Voice'), findsOneWidget);
    expect(find.text('CIDv1 Standard & Ontological Harmony'), findsOneWidget);
    expect(find.textContaining('Enforces universal content addressing'),
        findsOneWidget);

    // 3. Close dialog
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Coherence Voice'), findsNothing);
  });
}
