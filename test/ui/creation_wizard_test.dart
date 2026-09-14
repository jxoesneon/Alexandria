import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/ui/scriptorium/creation_wizard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CreationWizard Tests', () {
    testWidgets('renders stepper steps and navigates forward', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: CreationWizard(),
          ),
        ),
      );

      expect(find.text('Add Document to Library'), findsOneWidget);
      expect(find.byType(Stepper), findsOneWidget);
      expect(find.text('Select File'), findsOneWidget);

      final continueButton = find.widgetWithText(TextButton, 'Continue');
      if (continueButton.evaluate().isNotEmpty) {
        await tester.tap(continueButton.first);
        await tester.pumpAndSettle();
      }

      expect(find.byType(TextField), findsWidgets);
    });
  });
}
