import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alexandria/main.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import '../network_test_fakes.dart';

void main() {
  group('Cross-Platform Golden & Theme Tests', () {
    testWidgets('renders AlexandriaApp in dark void mode cleanly',
        (tester) async {
      // The entry gate routes on 'has_seen_onboarding': seed it so the
      // app lands on MainScaffold rather than the first-run chain.
      final storage = FakeSecureStorageService();
      await storage.write('has_seen_onboarding', 'true');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageServiceProvider.overrideWithValue(storage),
          ],
          child: const AlexandriaApp(),
        ),
      );

      // Use pump with duration instead of pumpAndSettle to avoid
      // Google Fonts network fetch timeout in tests
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Library'), findsWidgets);
      expect(find.text('Storage Used'), findsOneWidget);
    });
  });
}
