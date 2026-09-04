import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alexandria/main.dart';

void main() {
  testWidgets('Alexandria App Root Smoke & MainScaffold Navigation Test',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: AlexandriaApp(),
      ),
    );

    // Use pump with duration instead of pumpAndSettle to avoid
    // Google Fonts network fetch timeout in tests
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Library tab is the default — verify it renders
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Statistics Summary'), findsOneWidget);

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
