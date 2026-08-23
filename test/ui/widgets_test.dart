import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/ui/theme/app_theme.dart';
import 'package:alexandria/ui/widgets/glass_card.dart';
import 'package:alexandria/ui/widgets/info_glass.dart';

void main() {
  group('UI Glass Widgets Tests', () {
    testWidgets('GlassCard renders child and triggers onTap callback', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: GlassCard(
              onTap: () => tapped = true,
              child: const Text('Glass Test Content'),
            ),
          ),
        ),
      );

      expect(find.text('Glass Test Content'), findsOneWidget);
      await tester.tap(find.text('Glass Test Content'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('InfoGlass renders title, value and icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: InfoGlass(
              title: 'Total Pinned',
              value: '1.2 GB',
              icon: Icons.storage,
            ),
          ),
        ),
      );

      expect(find.text('Total Pinned'), findsOneWidget);
      expect(find.text('1.2 GB'), findsOneWidget);
      expect(find.byIcon(Icons.storage), findsOneWidget);
    });
  });
}
