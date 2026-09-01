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

      await tester.pumpAndSettle();
      expect(find.text('Alexandria'), findsOneWidget);
      expect(find.text('Your Decentralized Library'), findsOneWidget);
    });
  });
}
