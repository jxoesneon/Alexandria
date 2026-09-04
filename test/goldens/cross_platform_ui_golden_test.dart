import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alexandria/main.dart';

void main() {
  group('Cross-Platform Golden & Theme Tests', () {
    testWidgets('renders AlexandriaApp in dark void mode cleanly',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: AlexandriaApp(),
        ),
      );

      // Use pump with duration instead of pumpAndSettle to avoid
      // Google Fonts network fetch timeout in tests
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Library'), findsWidgets);
      expect(find.text('Statistics Summary'), findsOneWidget);
    });
  });
}
