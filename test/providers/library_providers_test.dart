import 'dart:convert';
import 'dart:typed_data';

import 'package:alexandria/data/database.dart';
import 'package:alexandria/logic/content_repository.dart';
import 'package:alexandria/models/library_models.dart';
import 'package:alexandria/providers/library_providers.dart';
import 'package:alexandria/services/collection_service.dart'
    as collection_service;
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:alexandria/services/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDatabase extends AppDatabase {
  @override
  Future<List<ContentManifest>> getAllManifests() async {
    throw Exception('database down');
  }
}

class FakeContentRepository extends ContentRepository {
  FakeContentRepository(super.ref);

  @override
  Future<Uint8List> retrieveContent(String cid, {String? dekBase64}) async {
    return Uint8List.fromList(utf8.encode('Test content for $cid'));
  }
}

class FakeIdentityService extends IdentityService {
  final AlexandriaIdentity _identity;

  FakeIdentityService(this._identity) : super(SecureStorageService());

  @override
  Future<AlexandriaIdentity?> getIdentity() async => _identity;

  @override
  Future<Uint8List> sign(Uint8List data) async => Uint8List(64);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late collection_service.CollectionService collectionService;
  late collection_service.Collection sourceCollection;
  late collection_service.Collection forkedCollection;
  late ProviderContainer container;

  Future<void> seedDatabase() async {
    await db.insertManifest({
      'uuid': 'uuid-1',
      'title': 'The Great Gatsby',
      'author': 'F. Scott Fitzgerald',
      'lastUpdated': DateTime(2024, 1, 2),
      'tags': 'classic,literature',
    });
    await db.insertManifest({
      'uuid': 'uuid-2',
      'title': 'Decentralized Networks',
      'author': 'Various',
      'lastUpdated': DateTime(2024, 1, 3),
      'tags': 'tech',
    });
    await db.insertManifest({
      'uuid': 'uuid-3',
      'title': 'Document One',
      'author': 'Doc Author',
      'lastUpdated': DateTime(2024, 1, 1),
    });

    final manifests = await db.getAllManifests();
    final m1 = manifests.firstWhere((m) => m.uuid == 'uuid-1');
    final m2 = manifests.firstWhere((m) => m.uuid == 'uuid-2');
    final m3 = manifests.firstWhere((m) => m.uuid == 'uuid-3');

    await db.insertVersion({
      'manifestId': m1.id,
      'cid': 'cid-1',
      'sizeBytes': 1024,
      'createdData': DateTime(2024, 1, 2),
      'format': 'epub',
    });
    await db.insertVersion({
      'manifestId': m2.id,
      'cid': 'cid-2',
      'sizeBytes': 2048,
      'createdData': DateTime(2024, 1, 3),
      'format': 'pdf',
    });
    await db.insertVersion({
      'manifestId': m3.id,
      'cid': 'cid-doc',
      'sizeBytes': 512,
      'createdData': DateTime(2024, 1, 1),
      'format': 'md',
    });
  }

  setUp(() async {
    db = AppDatabase();
    await seedDatabase();

    final identity = AlexandriaIdentity(
      publicKey: Uint8List.fromList(List.filled(32, 1)),
      privateKey: Uint8List.fromList(List.filled(32, 2)),
      createdAt: DateTime(2024),
    );
    collectionService =
        collection_service.CollectionService(FakeIdentityService(identity));
    sourceCollection =
        await collectionService.createCollection(name: 'Research');
    forkedCollection =
        await collectionService.forkCollection(sourceCollection.id);

    await collectionService.addItem(
      collectionId: sourceCollection.id,
      contentCid: 'cid-1',
      note: 'First note',
    );
    await collectionService.addItem(
      collectionId: sourceCollection.id,
      contentCid: 'cid-doc',
    );
    await collectionService.addItem(
      collectionId: forkedCollection.id,
      contentCid: 'cid-1',
      note: 'Forked note',
    );

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        syncStatusProvider.overrideWith((ref) => SyncStatus.idle),
        contentRepositoryProvider.overrideWith(
          (ref) => FakeContentRepository(ref),
        ),
        collection_service.collectionServiceProvider
            .overrideWithValue(collectionService),
        readingProgressProvider.overrideWith((ref) async => {'cid-1': 0.4}),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('ProviderContainer tests', () {
    test('libraryDashboardProvider starts loading and resolves to data',
        () async {
      expect(container.read(libraryDashboardProvider),
          isA<AsyncLoading<LibraryStats>>());

      final stats = await container.read(libraryDashboardProvider.future);

      expect(stats.totalItems, 3);
      expect(stats.totalSize, '3.5 KB');
      expect(stats.networkStatus, 'Synchronized');
    });

    test('libraryDashboardProvider reflects sync status', () async {
      final offlineContainer = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncStatusProvider.overrideWith((ref) => SyncStatus.offline),
          contentRepositoryProvider.overrideWith(
            (ref) => FakeContentRepository(ref),
          ),
          collection_service.collectionServiceProvider
              .overrideWithValue(collectionService),
          readingProgressProvider.overrideWith((ref) async => {'cid-1': 0.4}),
        ],
      );
      addTearDown(offlineContainer.dispose);

      final stats =
          await offlineContainer.read(libraryDashboardProvider.future);
      expect(stats.networkStatus, 'Offline');
    });

    test('libraryDashboardProvider surfaces errors', () async {
      final errorDb = FakeDatabase();
      final errorContainer = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(errorDb),
          syncStatusProvider.overrideWith((ref) => SyncStatus.idle),
          contentRepositoryProvider.overrideWith(
            (ref) => FakeContentRepository(ref),
          ),
          collection_service.collectionServiceProvider
              .overrideWithValue(collectionService),
          readingProgressProvider.overrideWith((ref) async => {'cid-1': 0.4}),
        ],
      );
      addTearDown(errorContainer.dispose);
      addTearDown(errorDb.close);

      expect(errorContainer.read(libraryDashboardProvider),
          isA<AsyncLoading<LibraryStats>>());
      await expectLater(
        errorContainer.read(libraryDashboardProvider.future),
        throwsA(isA<Exception>()),
      );
      expect(errorContainer.read(libraryDashboardProvider).hasError, isTrue);
    });

    test('recentItemsProvider filters items with progress', () async {
      final items = await container.read(recentItemsProvider.future);

      expect(items.length, 1);
      expect(items.first.cid, 'cid-1');
      expect(items.first.progress, 0.4);
    });

    test('newArrivalsProvider returns the latest additions', () async {
      final items = await container.read(newArrivalsProvider.future);

      expect(items.length, 3);
      expect(items.first.title, 'Decentralized Networks');
    });

    test('searchResultsProvider returns matches for a query', () async {
      final results =
          await container.read(searchResultsProvider('gatsby').future);

      expect(results.length, 1);
      expect(results.first.title, 'The Great Gatsby');
      expect(results.first.format, 'EPUB');
    });

    test('searchResultsProvider returns all results for empty query', () async {
      final results = await container.read(searchResultsProvider('').future);

      expect(results.length, 3);
    });

    test('searchResultsProvider returns empty list for no matches', () async {
      final results =
          await container.read(searchResultsProvider('nonexistent').future);

      expect(results, isEmpty);
    });

    test('availableTagsProvider extracts and sorts unique tags', () async {
      final tags = await container.read(availableTagsProvider.future);

      expect(tags, ['classic', 'literature', 'tech']);
    });

    test('currentDocumentProvider loads a document by CID', () async {
      final document =
          await container.read(currentDocumentProvider('cid-doc').future);

      expect(document.title, 'Document One');
      expect(document.content, 'Test content for cid-doc');
    });

    test('currentDocumentProvider throws for an unknown document', () async {
      await expectLater(
        container.read(currentDocumentProvider('unknown').future),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('annotationsProvider aggregates notes across collections', () async {
      final notes = await container.read(annotationsProvider('cid-1').future);

      expect(notes.length, 2);
      final texts = notes.map((n) => n.text).toList();
      expect(texts, contains('First note'));
      expect(texts, contains('Forked note'));
    });

    test('collectionsTreeProvider builds the collection hierarchy', () async {
      final tree = await container.read(collectionsTreeProvider.future);

      expect(tree.length, 1);
      expect(tree.first.id, sourceCollection.id);
      expect(tree.first.children.length, 1);
      expect(tree.first.children.first.id, forkedCollection.id);
    });

    test('collectionItemsProvider returns items for a collection', () async {
      final items = await container
          .read(collectionItemsProvider(sourceCollection.id).future);

      expect(items.length, 2);
      final titles = items.map((i) => i.title).toList();
      expect(titles, contains('The Great Gatsby'));
      expect(titles, contains('Document One'));
    });

    test('collectionItemsProvider returns empty list for null id', () async {
      final items = await container.read(collectionItemsProvider(null).future);

      expect(items, isEmpty);
    });

    test('collectionItemsProvider returns empty list for missing collection',
        () async {
      final items =
          await container.read(collectionItemsProvider('missing-id').future);

      expect(items, isEmpty);
    });
  });

  group('ProviderScope tests', () {
    testWidgets('renders library dashboard through ProviderScope',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            syncStatusProvider.overrideWith((ref) => SyncStatus.idle),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) {
                final value = ref.watch(libraryDashboardProvider);
                return Scaffold(
                  body: value.when(
                    data: (stats) =>
                        Text('${stats.totalItems} ${stats.networkStatus}'),
                    loading: () => const Text('loading'),
                    error: (error, stack) => const Text('error'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('loading'), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.text('3 Synchronized'), findsOneWidget);
    });

    testWidgets('renders an error state through ProviderScope', (tester) async {
      final errorDb = FakeDatabase();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(errorDb),
            syncStatusProvider.overrideWith((ref) => SyncStatus.idle),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) {
                final value = ref.watch(libraryDashboardProvider);
                return Scaffold(
                  body: value.when(
                    data: (stats) => Text(stats.networkStatus),
                    loading: () => const Text('loading'),
                    error: (error, stack) => const Text('error'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('error'), findsOneWidget);
      addTearDown(errorDb.close);
    });
  });
}
