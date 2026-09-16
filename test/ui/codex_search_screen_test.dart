import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/ui/codex/search_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SearchScreen (Codex) Tests', () {
    testWidgets('renders search field, filter categories, and updates state',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SearchScreen(),
        ),
      );

      expect(find.text('Search Library'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Books'), findsOneWidget);
      expect(find.text('Science'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Quantum mechanics');
      await tester.pump();

      await tester.tap(find.text('Science'));
      await tester.pump();
    });
  });
}
