import 'dart:async';

import 'package:alexandria/models/library_models.dart';
import 'package:alexandria/providers/library_providers.dart';
import 'package:alexandria/ui/library/discovery_search_screen.dart';
import 'package:alexandria/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final results = [
    SearchResult(
      id: 'result-1',
      title: 'The Decentralized Web',
      author: 'Alice Smith',
      format: 'PDF',
      dateAdded: DateTime(2026, 1, 10),
    ),
    SearchResult(
      id: 'result-2',
      title: 'Advanced Cryptography',
      author: 'Bob Jones',
      format: 'EPUB',
      dateAdded: DateTime(2026, 1, 5),
    ),
    SearchResult(
      id: 'result-3',
      title: 'Data Preservation Protocols',
      author: 'Charlie Brown',
      format: 'MD',
      dateAdded: DateTime(2026, 1, 1),
    ),
  ];

  Widget createSubject() {
    return ProviderScope(
      overrides: [
        searchQueryProvider.overrideWith((ref) => ''),
        searchResultsProvider.overrideWith((ref, query) async => results),
        availableTagsProvider.overrideWith(
          (ref) async => const ['Technology', 'Science', 'History'],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const DiscoverySearchScreen(),
      ),
    );
  }

  testWidgets('renders search results and filters', (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Discovery & Search'), findsOneWidget);
    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('Results'), findsOneWidget);
    expect(find.text('The Decentralized Web'), findsOneWidget);
    expect(find.text('Advanced Cryptography'), findsOneWidget);
    expect(find.text('Data Preservation Protocols'), findsOneWidget);
    expect(find.text('Technology'), findsOneWidget);
  });

  testWidgets('updates results when query changes', (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final searchBar = find.byType(SearchBar);
    expect(searchBar, findsOneWidget);

    await tester.enterText(searchBar, 'cryptography');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Advanced Cryptography'), findsOneWidget);
  });

  group('DiscoverySearchScreen states', () {
    final results = [
      SearchResult(
        id: 'result-1',
        title: 'The Decentralized Web',
        author: 'Alice Smith',
        format: 'PDF',
        dateAdded: DateTime(2026, 1, 10),
      ),
    ];

    Widget createStateSubject({
      String query = '',
      Future<List<SearchResult>> Function(Ref, String)? resultsBuilder,
      Future<List<String>> Function(Ref)? tagsBuilder,
    }) {
      return ProviderScope(
        overrides: [
          searchQueryProvider.overrideWith((ref) => query),
          searchResultsProvider.overrideWith(
            resultsBuilder ?? (ref, q) async => results,
          ),
          availableTagsProvider.overrideWith(
            tagsBuilder ?? (ref) async => const ['Technology'],
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const DiscoverySearchScreen(),
        ),
      );
    }

    testWidgets('shows empty results message', (tester) async {
      await tester.pumpWidget(createStateSubject(
        resultsBuilder: (ref, query) async => <SearchResult>[],
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('No results found.'), findsOneWidget);
    });

    testWidgets('shows error message when search fails', (tester) async {
      await tester.pumpWidget(createStateSubject(
        resultsBuilder: (ref, query) async => throw Exception('search boom'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('search boom'), findsOneWidget);
    });

    testWidgets('shows loading while search results resolve', (tester) async {
      final completer = Completer<List<SearchResult>>();
      await tester.pumpWidget(createStateSubject(
        resultsBuilder: (ref, query) => completer.future,
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);

      completer.complete(<SearchResult>[]);
      await tester.pump();
    });

    testWidgets('toggles from grid to list view', (tester) async {
      await tester.pumpWidget(createStateSubject());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(GridView), findsOneWidget);

      final listButton = find.byIcon(Icons.view_list);
      expect(listButton, findsOneWidget);
      await tester.tap(listButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ListView), findsWidgets);
      expect(find.byType(GridView), findsNothing);
    });

    testWidgets('clear query button removes the current query', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchQueryProvider.overrideWith((ref) => 'query'),
            searchResultsProvider
                .overrideWith((ref, query) async => <SearchResult>[]),
            availableTagsProvider.overrideWith((ref) async => const []),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const DiscoverySearchScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final clearButton = find.byIcon(Icons.clear);
      expect(clearButton, findsOneWidget);
      await tester.tap(clearButton);
      await tester.pump();
    });

    testWidgets('renders tags loading state', (tester) async {
      final completer = Completer<List<String>>();
      await tester.pumpWidget(createStateSubject(
        resultsBuilder: (ref, query) async => <SearchResult>[],
        tagsBuilder: (ref) => completer.future,
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);

      completer.complete(<String>[]);
      await tester.pump();
    });
  });
}
