import 'package:alexandria/models/library_models.dart';
import 'package:alexandria/providers/library_providers.dart';
import 'package:alexandria/services/sync_service.dart';
import 'package:alexandria/ui/library/library_overview_screen.dart';
import 'package:alexandria/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget createSubject() {
    return ProviderScope(
      overrides: [
        syncStatusProvider.overrideWith((ref) => SyncStatus.idle),
        libraryDashboardProvider.overrideWith(
          (ref) async => const LibraryStats(
            totalItems: 3,
            totalSize: '1.2 MB',
            networkStatus: 'Synchronized',
          ),
        ),
        recentItemsProvider.overrideWith(
          (ref) async => const [
            LibraryItem(
              cid: 'cid-recent-1',
              title: 'Continue Reading Book',
              author: 'Recent Author',
              progress: 0.35,
            ),
          ],
        ),
        newArrivalsProvider.overrideWith(
          (ref) async => const [
            LibraryItem(
              cid: 'cid-new-1',
              title: 'New Arrival One',
              author: 'New Author One',
            ),
            LibraryItem(
              cid: 'cid-new-2',
              title: 'New Arrival Two',
              author: 'New Author Two',
            ),
          ],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const LibraryOverviewScreen(),
      ),
    );
  }

  testWidgets('renders dashboard stats', (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Statistics Summary'), findsOneWidget);
    expect(find.text('Total Items'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Total Size'), findsOneWidget);
    expect(find.text('1.2 MB'), findsOneWidget);
    expect(find.text('Network Status'), findsOneWidget);
    expect(find.text('Synchronized'), findsOneWidget);
  });

  testWidgets('renders continue reading section', (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Continue Reading'), findsOneWidget);
    expect(find.text('Continue Reading Book'), findsOneWidget);
    expect(find.text('Recent Author'), findsOneWidget);
    expect(find.text('35% completed'), findsOneWidget);
  });

  testWidgets('renders new arrivals section', (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('New Arrivals'), findsOneWidget);
    expect(find.text('New Arrival One'), findsOneWidget);
    expect(find.text('New Author One'), findsOneWidget);
    expect(find.text('New Arrival Two'), findsOneWidget);
    expect(find.text('New Author Two'), findsOneWidget);
  });
}
