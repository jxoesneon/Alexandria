import 'dart:typed_data';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart';
import 'package:alexandria/logic/content_repository.dart';
import 'package:alexandria/logic/honor_system.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/knowledge_graph_service.dart';
import 'package:alexandria/services/preservation_service.dart';
import 'package:alexandria/services/sibling_service.dart';
import 'package:alexandria/ui/content_detail_screen.dart';
import 'package:alexandria/ui/library/content_viewer_screen.dart';

class _FakeIpfsService implements IpfsService {
  @override
  int get storedBytes => 0;

  bool isPinned(String cid) => true;

  @override
  Stream<Uint8List> getFile(String cid) async* {
    yield Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePreservationService implements PreservationService {
  @override
  Future<HealthStatus> checkContentHealth(String cid) async =>
      HealthStatus.healthy;

  @override
  Future<bool> healContent(String cid) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHonorSystem implements HonorSystem {
  int validatedScore = 0;
  String? lastTargetCid;

  @override
  int getTrustScore(String cid) => 95;

  @override
  void validateContent({
    required String targetCid,
    required int score,
    required String validatorId,
    int reputation = 10,
  }) {
    validatedScore = score;
    lastTargetCid = targetCid;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeContentRepository implements ContentRepository {
  bool downloadCalled = false;
  bool addVersionCalled = false;

  @override
  Future<Uint8List> downloadContent(String cid, {String? keyBase64}) async {
    downloadCalled = true;
    return Uint8List.fromList([65, 66, 67, 68]);
  }

  // The screen now unwraps DEKs through the repository layer
  // (round-2 fix - manifest rows no longer carry key material), so the
  // download path calls retrieveManifestContent rather than
  // downloadContent.
  @override
  Future<Uint8List> retrieveManifestContent(
      String manifestUuid, String cid) async {
    downloadCalled = true;
    return Uint8List.fromList([65, 66, 67, 68]);
  }

  @override
  Future<String> addContentVersion({
    required String manifestUuid,
    required Uint8List fileData,
    String language = 'en',
    String format = 'bin',
  }) async {
    addVersionCalled = true;
    return 'bafy_new_version_cid';
  }

  @override
  Future<List<ContentManifest>> getContentPage(
      {required int page, required int pageSize}) async {
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ContentDetailScreen Tests', () {
    testWidgets(
        'renders manifest details, metadata, and handles View / Open in buttons',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final manifest = ContentManifest(
        id: 1,
        uuid: 'uuid-123',
        title: 'Elements of Geometry',
        author: 'Euclid of Alexandria',
        description: 'Classical mathematical treatise',
        category: 'book',
        tags: '["math","geometry"]',
        metadata: '{"year": -300, "pages": 500}',
        isEncrypted: false,
        lastUpdated: DateTime(2026, 1, 1),
      );

      final db = AppDatabase();
      addTearDown(db.close);

      final fakeHonor = _FakeHonorSystem();
      final fakeRepo = _FakeContentRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            contentRepositoryProvider.overrideWithValue(fakeRepo),
            ipfsServiceProvider.overrideWithValue(_FakeIpfsService()),
            preservationServiceProvider
                .overrideWithValue(_FakePreservationService()),
            honorSystemProvider.overrideWithValue(fakeHonor),
            versionFilePickerProvider.overrideWithValue(
              () async => (
                bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
                format: 'pdf',
              ),
            ),
          ],
          child: MaterialApp(
            home: ContentDetailScreen(manifest: manifest),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Elements of Geometry'), findsWidgets);
      expect(find.textContaining('Euclid of Alexandria'), findsOneWidget);
      expect(find.text('BOOK'), findsWidgets);
      expect(find.text('math'), findsOneWidget);
      expect(find.text('Year: -300'), findsOneWidget);

      // Tap Open in… button
      final openButton = find.widgetWithText(OutlinedButton, 'Open in…');
      expect(openButton, findsOneWidget);
      await tester.tap(openButton);
      await tester.pumpAndSettle();

      // Tap Read button → opens the in-app reader.
      final readButton = find.widgetWithText(ElevatedButton, 'Read');
      expect(readButton, findsOneWidget);
      await tester.tap(readButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ContentViewerScreen), findsOneWidget);
    });

    testWidgets(
        'shows version items and handles action dialog (verify, report, download, rescue)',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final manifest = ContentManifest(
        id: 42,
        uuid: 'manifest-42',
        title: 'Principia Mathematica',
        author: 'Isaac Newton',
        description: 'Philosophiae Naturalis Principia Mathematica',
        category: 'book',
        tags: '["physics"]',
        metadata: '{"edition": "1st"}',
        isEncrypted: false,
        lastUpdated: DateTime(2026, 1, 1),
      );

      final db = AppDatabase();
      addTearDown(db.close);

      // Insert manifest and version into drift database
      await db.into(db.contentManifests).insert(
            ContentManifestsCompanion(
              id: const drift.Value(42),
              uuid: const drift.Value('manifest-42'),
              title: const drift.Value('Principia Mathematica'),
              author: const drift.Value('Isaac Newton'),
              category: const drift.Value('book'),
              lastUpdated: drift.Value(DateTime.now()),
            ),
          );

      await db.into(db.contentVersions).insert(
            ContentVersionsCompanion(
              manifestId: const drift.Value(42),
              cid: const drift.Value('bafy_version_cid_1'),
              format: const drift.Value('pdf'),
              language: const drift.Value('Latin'),
              sizeBytes: const drift.Value(2048),
              isPinned: const drift.Value(true),
              createdData: drift.Value(DateTime.now()),
            ),
          );

      final fakeHonor = _FakeHonorSystem();
      final fakeRepo = _FakeContentRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            contentRepositoryProvider.overrideWithValue(fakeRepo),
            ipfsServiceProvider.overrideWithValue(_FakeIpfsService()),
            preservationServiceProvider
                .overrideWithValue(_FakePreservationService()),
            honorSystemProvider.overrideWithValue(fakeHonor),
            versionFilePickerProvider.overrideWithValue(
              () async => (
                bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
                format: 'pdf',
              ),
            ),
          ],
          child: MaterialApp(
            home: ContentDetailScreen(manifest: manifest),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('VERSIONS (1)'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('Latin'), findsOneWidget);

      // Tap on the version glass card to open action dialog
      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();

      expect(find.text('Content Actions'), findsOneWidget);
      expect(find.text('Verify (+1)'), findsOneWidget);

      // Tap Verify (+1)
      await tester.tap(find.text('Verify (+1)'));
      await tester.pumpAndSettle();
      expect(fakeHonor.validatedScore, 1);
      expect(fakeHonor.lastTargetCid, 'bafy_version_cid_1');

      // Re-open dialog and test Report (-1)
      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report (-1)'));
      await tester.pumpAndSettle();
      expect(fakeHonor.validatedScore, -1);

      // Re-open dialog and test Download & Decrypt
      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download & Decrypt'));
      await tester.pumpAndSettle();
      expect(fakeRepo.downloadCalled, isTrue);

      // Re-open dialog and test Rescue (Re-pin)
      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rescue (Re-pin)'));
      await tester.pumpAndSettle();

      // Add Version via icon button
      final addVersionBtn = find.byIcon(Icons.add_circle);
      expect(addVersionBtn, findsOneWidget);
      await tester.tap(addVersionBtn);
      await tester.pumpAndSettle();
      expect(fakeRepo.addVersionCalled, isTrue);
    });

    testWidgets('renders variants and related content sections',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final manifest = ContentManifest(
        id: 99,
        uuid: 'manifest-99',
        title: 'The Republic',
        author: 'Plato',
        description: 'Socratic dialogue on justice and order',
        category: 'book',
        isEncrypted: false,
        lastUpdated: DateTime(2026, 1, 1),
      );

      final db = AppDatabase();
      addTearDown(db.close);

      final sibling = ContentSibling(
        cid: 'cid-greek',
        title: 'The Republic (Greek original)',
        similarity: 0.95,
        variantType: VariantType.language,
        variantValue: 'Greek',
      );

      final kgEntity = KnowledgeEntity(
        entityId: '99',
        canonicalTitle: 'The Republic Commentary',
        author: 'Proclus',
        variants: [
          KnowledgeVariant(
            cid: 'cid-var-1',
            format: 'epub',
            language: 'en',
            edition: 'Critical',
            sizeBytes: 1024,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            contentRepositoryProvider
                .overrideWithValue(_FakeContentRepository()),
            ipfsServiceProvider.overrideWithValue(_FakeIpfsService()),
            preservationServiceProvider
                .overrideWithValue(_FakePreservationService()),
            honorSystemProvider.overrideWithValue(_FakeHonorSystem()),
            siblingsProvider(manifest.title).overrideWith((ref) => [sibling]),
            relatedContentProvider('99').overrideWith((ref) => kgEntity),
          ],
          child: MaterialApp(
            home: ContentDetailScreen(manifest: manifest),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('VARIANTS'), findsOneWidget);
      expect(find.text('The Republic (Greek original)'), findsOneWidget);
      expect(find.text('Greek translation'), findsOneWidget);
      expect(find.text('95% match'), findsOneWidget);

      expect(find.text('RELATED CONTENT'), findsOneWidget);
      expect(find.text('The Republic Commentary'), findsOneWidget);
      expect(find.text('Proclus'), findsOneWidget);
    });
  });
}
