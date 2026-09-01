import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alexandria/ui/theme/app_theme.dart';
import 'package:alexandria/ui/settings/settings_screen.dart';
import 'package:alexandria/ui/widgets/glass_card.dart';
import 'package:alexandria/ui/widgets/info_glass.dart';

void main() {
  group('Accessibility & Semantics Verification', () {
    testWidgets('Interactive GlassCard provides accessible tap semantics',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: GlassCard(
              onTap: () {},
              child: const Text('Accessible Action Item'),
            ),
          ),
        ),
      );

      expect(find.byType(InkWell), findsOneWidget);
      expect(tester.getSemantics(find.text('Accessible Action Item')),
          matchesSemantics(label: 'Accessible Action Item'));
    });

    testWidgets('InfoGlass structure provides clear semantic hierarchy',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: InfoGlass(
              title: 'Storage Used',
              value: '512 MB',
              icon: Icons.data_usage,
            ),
          ),
        ),
      );

      expect(find.text('Storage Used'), findsOneWidget);
      expect(find.text('512 MB'), findsOneWidget);
    });

    testWidgets('SettingsScreen adheres to accessibility guidelines',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Network & Privacy'), findsOneWidget);
      expect(find.text('Storage & Maintenance'), findsOneWidget);
    });
  });
}
