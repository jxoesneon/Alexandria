import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/ui/widgets/contribution_graph.dart';

void main() {
  group('ContributionGraph Widget Tests', () {
    test('normalizeData aggregates dates by calendar day', () {
      final now = DateTime.now();
      final d1 = DateTime(now.year, now.month, now.day, 10, 30);
      final d2 = DateTime(now.year, now.month, now.day, 14, 45);
      final yesterday = now.subtract(const Duration(days: 1));

      final normalized = ContributionGraph.normalizeData([d1, d2, yesterday]);
      final todayKey = DateTime(now.year, now.month, now.day);
      final yestKey = DateTime(yesterday.year, yesterday.month, yesterday.day);

      expect(normalized[todayKey], equals(2));
      expect(normalized[yestKey], equals(1));
    });

    testWidgets('renders grid cells with various intensity levels',
        (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final d1 = today.subtract(const Duration(days: 2));
      final d2 = today.subtract(const Duration(days: 5));

      final data = {
        today: 10, // high intensity
        d1: 3, // medium intensity
        d2: 1, // low intensity
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContributionGraph(activityData: data),
          ),
        ),
      );

      expect(find.byType(ContributionGraph), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
