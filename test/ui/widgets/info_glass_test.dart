import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/ui/theme/app_theme.dart';
import 'package:alexandria/ui/widgets/info_glass.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('InfoGlass renders value, icon and color', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          body: InfoGlass(
            title: 'Total Pinned',
            value: '1.2 GB',
            icon: Icons.storage,
            color: Colors.red,
          ),
        ),
      ),
    );

    expect(find.text('Total Pinned'), findsOneWidget);
    expect(find.text('1.2 GB'), findsOneWidget);
    expect(find.byIcon(Icons.storage), findsOneWidget);

    final icon = tester.widget<Icon>(find.byIcon(Icons.storage));
    expect(icon.color, Colors.red);
  });

  testWidgets('InfoGlass renders description and small', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          body: InfoGlass(
            title: 'Status',
            description: 'System is healthy.',
            small: true,
          ),
        ),
      ),
    );

    expect(find.text('Status'), findsOneWidget);
    expect(find.text('System is healthy.'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });
}
