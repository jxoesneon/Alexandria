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

    await tester.pumpAndSettle();

    expect(find.text('Alexandria'), findsOneWidget);
    expect(find.text('Your Decentralized Library'), findsOneWidget);

    // Switch to Settings tab
    final settingsNav = find.text('Settings');
    expect(settingsNav, findsOneWidget);
    await tester.tap(settingsNav);
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Network & Privacy'), findsOneWidget);
    expect(find.text('Storage & Maintenance'), findsOneWidget);
  });
}
