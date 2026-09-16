import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/collection_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:alexandria/ui/collection_screen.dart';

class _FakeIdentityService extends IdentityService {
  _FakeIdentityService() : super(SecureStorageService());

  @override
  Future<AlexandriaIdentity?> getIdentity() async => AlexandriaIdentity(
        publicKey: Uint8List.fromList(List.filled(32, 1)),
        privateKey: Uint8List.fromList(List.filled(32, 2)),
        createdAt: DateTime(2025, 1, 1),
      );

  @override
  Future<Uint8List> sign(Uint8List data) async => Uint8List(64);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CollectionScreen Tests', () {
    testWidgets(
        'renders collections list, creates collection and opens create dialog',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final identity = _FakeIdentityService();
      final service = CollectionService(identity);
      await service.createCollection(name: 'Ancient Philosophers');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectionServiceProvider.overrideWithValue(service),
          ],
          child: const MaterialApp(
            home: CollectionScreen(),
          ),
        ),
      );

      expect(find.text('THE SCRIPTORIUM'), findsOneWidget);
      expect(find.text('Ancient Philosophers'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();

      expect(find.text('Create Collection'), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);

      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(2));
      await tester.enterText(textFields.at(0), 'Modern Thinkers');
      await tester.enterText(
          textFields.at(1), 'Contemporary philosophical essays');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(service.collections.any((c) => c.name.value == 'Modern Thinkers'),
          isTrue);
    });

    testWidgets(
        'renders detail view, adds item, and tests menu actions (fork and history)',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final identity = _FakeIdentityService();
      final service = CollectionService(identity);
      final col = await service.createCollection(
        name: 'Ancient Philosophers',
        description: 'Classical Greek canon',
      );

      // Pre-add an item to verify item card display
      await service.addItem(
        collectionId: col.id,
        contentCid: 'bafy_plato_dialogue',
        note: 'Primary source',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectionServiceProvider.overrideWithValue(service),
            selectedCollectionProvider.overrideWith((ref) => col.id),
          ],
          child: const MaterialApp(
            home: CollectionScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Ancient Philosophers'), findsWidgets);
      expect(find.text('CRDT Synced'), findsOneWidget);
      expect(find.text('bafy_plato_dialogue'), findsOneWidget);
      expect(find.text('Primary source'), findsOneWidget);

      // Open Add Item dialog
      await tester.tap(find.text('Add Item'));
      await tester.pumpAndSettle();

      expect(find.text('Content CID'), findsOneWidget);
      final addFields = find.byType(TextField);
      await tester.enterText(addFields.at(0), 'bafy_aristotle_ethics');
      await tester.enterText(addFields.at(1), 'Nicomachean Ethics');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(
          col.items.elements
              .any((i) => i.contentCid == 'bafy_aristotle_ethics'),
          isTrue);

      // Test PopupMenu actions (History)
      final moreBtn = find.byIcon(Icons.more_vert);
      expect(moreBtn, findsOneWidget);
      await tester.tap(moreBtn);
      await tester.pumpAndSettle();

      await tester.tap(find.text('View History'));
      await tester.pumpAndSettle();
      expect(find.text('Collection History'), findsOneWidget);
      expect(find.text('Created'), findsOneWidget);
      expect(find.text('Last modified'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10)); // tap outside to dismiss dialog
      await tester.pumpAndSettle();

      // Test PopupMenu actions (Fork)
      await tester.tap(moreBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fork Collection'));
      await tester.pumpAndSettle();
      expect(find.text('Collection forked!'), findsOneWidget);
    });
  });
}
