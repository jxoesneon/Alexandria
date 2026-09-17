import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alexandria/main.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'network_test_fakes.dart' as network;

void main() {
  testWidgets('Alexandria App Root Smoke & MainScaffold Navigation Test',
      (WidgetTester tester) async {
    // Past the first-run gate so the app lands on the MainScaffold.
    final storage = network.FakeSecureStorageService();
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

    // Home tab is the default landing surface - verify it renders
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Your Decentralized Library'), findsOneWidget);

    // Switch to Settings tab
    final settingsNav = find.text('Settings');
    expect(settingsNav, findsOneWidget);
    await tester.tap(settingsNav);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Network & Privacy'), findsOneWidget);
    expect(find.text('Storage & Maintenance'), findsOneWidget);
  });
}
