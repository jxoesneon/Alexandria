import 'package:alexandria/models/library_models.dart';
import 'package:alexandria/providers/library_providers.dart';
import 'package:alexandria/ui/library/collections_shelves_screen.dart';
import 'package:alexandria/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const collectionId = 'collection-1';

  Widget createSubject() {
    return ProviderScope(
      overrides: [
        selectedCollectionIdProvider.overrideWith((ref) => collectionId),
        collectionsTreeProvider.overrideWith(
          (ref) async => const [
            CollectionNode(
              id: 'collection-1',
              name: 'Research Papers',
              children: [
                CollectionNode(id: 'collection-1-1', name: 'Cryptography'),
              ],
            ),
            CollectionNode(id: 'collection-2', name: 'Fiction'),
          ],
        ),
        collectionItemsProvider.overrideWith(
          (ref, id) async => const [
            CollectionItem(
              id: 'item-1',
              title: 'The Architecture of Alexandria',
              author: 'Alexandria',
              format: 'PDF',
            ),
            CollectionItem(
              id: 'item-2',
              title: 'Decentralized Networks',
              author: 'Various',
              format: 'EPUB',
            ),
          ],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const CollectionsShelvesScreen(),
      ),
    );
  }

  testWidgets('renders collection tree and items', (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Collections & Shelves'), findsOneWidget);
    expect(find.text('Research Papers'), findsOneWidget);
    expect(find.text('Cryptography'), findsOneWidget);
    expect(find.text('Fiction'), findsOneWidget);
    expect(find.text('The Architecture of Alexandria'), findsOneWidget);
    expect(find.text('Decentralized Networks'), findsOneWidget);
  });
}
