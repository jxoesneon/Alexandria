import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/ui/common/governance_badge.dart';
import 'package:alexandria/ui/common/identity_avatar_action.dart';
import 'package:alexandria/ui/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'IdentityAvatarAction shows create-identity nudge without an identity '
      'and navigates to the profile screen', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            appBar: null,
            body: IdentityAvatarAction(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Mocked secure storage holds no identity -> the nudge chip renders.
    expect(find.text('Create Identity'), findsOneWidget);

    await tester.tap(find.text('Create Identity'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    tester.takeException();
    await tester.pumpAndSettle();
    tester.takeException();

    expect(find.text('Identity'), findsOneWidget);
  });

  testWidgets('GovernancePillRow tap opens the Parliament', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: Center(child: GovernancePillRow()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(GovernancePillRow));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    tester.takeException();
    await tester.pumpAndSettle();
    tester.takeException();

    expect(find.text('Parliament'), findsOneWidget);
  });
}
