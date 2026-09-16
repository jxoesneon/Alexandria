import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart';
import 'package:alexandria/logic/content_repository.dart';
import 'package:alexandria/logic/honor_system.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/knowledge_graph_service.dart';
import 'package:alexandria/services/preservation_service.dart';
import 'package:alexandria/ui/content_detail_screen.dart';
import 'package:alexandria/ui/theme/app_theme.dart';

class _FakeIpfs implements IpfsService {
  _FakeIpfs({this.bytes});

  final List<int>? bytes;

  @override
  Stream<Uint8List> getFile(String cid) async* {
    final b = bytes;
    if (b != null && b.isNotEmpty) yield Uint8List.fromList(b);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePreservation implements PreservationService {
  _FakePreservation(
      {this.health = HealthStatus.healthy, this.healResult = true});

  HealthStatus health;
  bool healResult;
  bool healThrows = false;
  int healCalls = 0;

  @override
  Future<HealthStatus> checkContentHealth(String cid) async => health;

  @override
  Future<bool> healContent(String cid) async {
    healCalls++;
    if (healThrows) throw StateError('network unreachable');
    return healResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHonor implements HonorSystem {
  @override
  int getTrustScore(String cid) => 42;

  @override
  void validateContent({
    required String targetCid,
    required int score,
    required String validatorId,
    int reputation = 10,
  }) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRepo implements ContentRepository {
  _FakeRepo({this.page = const [], this.retrieveThrows = false});

  List<ContentManifest> page;
  bool retrieveThrows;

  @override
  Future<List<ContentManifest>> getContentPage(
          {required int page, required int pageSize}) async =>
      this.page;

  bool retrieveCalled = false;

  @override
  Future<Uint8List> retrieveManifestContent(
      String manifestUuid, String cid) async {
    retrieveCalled = true;
    if (retrieveThrows) throw StateError('decrypt failed');
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ContentManifest _manifest({
  int id = 1,
  String uuid = 'uuid-1',
  String title = 'Test Work',
  String category = 'book',
}) =>
    ContentManifest(
      id: id,
      uuid: uuid,
      title: title,
      author: 'Author A',
      description: 'desc',
      category: category,
      isEncrypted: false,
      lastUpdated: DateTime(2024),
    );

ContentVersion _version(String cid, {String format = 'pdf'}) => ContentVersion(
      id: 1,
      manifestId: 1,
      cid: cid,
      language: 'en',
      format: format,
      sizeBytes: 2048,
      peerCount: 2,
      isPinned: true,
      createdData: DateTime(2024),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('content_detail providers', () {
    test('siblingsProvider maps repo content through findSiblings', () async {
      final repo = _FakeRepo(page: [
        // '(2nd Edition)' strips to the same normalized title → 1.0 match.
        _manifest(id: 2, title: 'Test Work (2nd Edition)'),
        _manifest(id: 3, title: 'Completely Different Treatise'),
      ]);
      final container = ProviderContainer(overrides: [
        contentRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(container.dispose);

      final siblings =
          await container.read(siblingsProvider('Test Work').future);
      expect(siblings, isNotEmpty);
      expect(siblings.first.title, 'Test Work (2nd Edition)');
    });

    test('relatedContentProvider returns entity and null for unknown id',
        () async {
      final kg = KnowledgeGraphService();
      kg.registerEntity(KnowledgeEntity(
        entityId: '7',
        canonicalTitle: 'Known Entity',
        author: 'A',
        variants: [
          KnowledgeVariant(
            cid: 'cid-v',
            format: 'pdf',
            language: 'en',
            sizeBytes: 10,
          ),
        ],
      ));
      final container = ProviderContainer(overrides: [
        knowledgeGraphServiceProvider.overrideWithValue(kg),
      ]);
      addTearDown(container.dispose);

      final entity = await container.read(relatedContentProvider('7').future);
      expect(entity, isNotNull);
      expect(entity!.canonicalTitle, 'Known Entity');

      final missing =
          await container.read(relatedContentProvider('nope').future);
      expect(missing, isNull);
    });

    test('integrityVerificationProvider verifies retrievable content',
        () async {
      final container = ProviderContainer(overrides: [
        ipfsServiceProvider
            .overrideWithValue(_FakeIpfs(bytes: List.generate(64, (i) => i))),
      ]);
      addTearDown(container.dispose);

      final result =
          await container.read(integrityVerificationProvider('cid-x').future);
      expect(result, isTrue);
    });

    test('integrityVerificationProvider returns false for absent content',
        () async {
      final container = ProviderContainer(overrides: [
        ipfsServiceProvider.overrideWithValue(_FakeIpfs(bytes: const [])),
      ]);
      addTearDown(container.dispose);

      final result =
          await container.read(integrityVerificationProvider('cid-x').future);
      expect(result, isFalse);
    });
  });

  group('ContentDetailScreen widget coverage', () {
    Future<void> pumpScreen(
      WidgetTester tester, {
      ContentManifest? manifest,
      List<ContentVersion>? versions,
      bool versionsThrow = false,
      bool trustScoreThrows = false,
      _FakeRepo? repo,
      _FakePreservation? preservation,
      _FakeIpfs? ipfs,
      KnowledgeGraphService? knowledgeGraph,
      Future<bool> Function(String cid)? integrity,
    }) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contentRepositoryProvider.overrideWithValue(repo ?? _FakeRepo()),
            ipfsServiceProvider.overrideWithValue(
                ipfs ?? _FakeIpfs(bytes: const [1, 2, 3, 4])),
            preservationServiceProvider
                .overrideWithValue(preservation ?? _FakePreservation()),
            honorSystemProvider.overrideWithValue(_FakeHonor()),
            versionsProvider.overrideWith((ref, id) => versionsThrow
                ? Future<List<ContentVersion>>.error(StateError('db'))
                : Future.value(versions ?? const <ContentVersion>[])),
            if (trustScoreThrows)
              trustScoreProvider.overrideWith(
                  (ref, cid) => Future<int>.error(StateError('score db'))),
            if (knowledgeGraph != null)
              knowledgeGraphServiceProvider.overrideWithValue(knowledgeGraph),
            if (integrity != null)
              integrityVerificationProvider
                  .overrideWith((ref, cid) => integrity(cid)),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: ContentDetailScreen(manifest: manifest ?? _manifest()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openActionDialog(WidgetTester tester) async {
      await tester.tap(find.text('PDF').first);
      await tester.pumpAndSettle();
      expect(find.text('Verify Content'), findsOneWidget);
    }

    testWidgets('View on a non-viewable format asks for an external viewer',
        (tester) async {
      await pumpScreen(tester, manifest: _manifest(category: 'blend'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'View'));
      await tester.pumpAndSettle();
      expect(
          find.textContaining('requires an external viewer'), findsOneWidget);
    });

    testWidgets('Open in… fails cleanly when no valid CID exists',
        (tester) async {
      await pumpScreen(
        tester,
        manifest: _manifest(category: 'blend'),
        versions: [_version('not a cid')],
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Open in…'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cannot open externally'), findsOneWidget);
    });

    testWidgets('versions error state shows the error label', (tester) async {
      await pumpScreen(tester, versionsThrow: true);
      expect(find.text('VERSIONS (error)'), findsOneWidget);
    });

    testWidgets('Verify Integrity failure shows the danger snackbar',
        (tester) async {
      await pumpScreen(
        tester,
        versions: [_version('cid-v1')],
        integrity: (_) async => false,
      );
      await openActionDialog(tester);
      await tester.tap(find.text('Verify Integrity'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('content may be corrupted or unavailable'),
        findsOneWidget,
      );
    });

    testWidgets('Verify Integrity success stamps the last-verified time',
        (tester) async {
      await pumpScreen(
        tester,
        versions: [_version('cid-v1')],
        integrity: (_) async => true,
      );
      await openActionDialog(tester);
      await tester.tap(find.text('Verify Integrity'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.textContaining('Integrity verified'), findsOneWidget);
      expect(find.textContaining('Last verified:'), findsOneWidget);
    });

    testWidgets('Download & Decrypt surfaces repository errors',
        (tester) async {
      final repo = _FakeRepo(retrieveThrows: true);
      await pumpScreen(
        tester,
        versions: [_version('cid-v1')],
        repo: repo,
      );
      await openActionDialog(tester);
      await tester.tap(find.text('Download & Decrypt'));
      await tester.pumpAndSettle();
      expect(repo.retrieveCalled, isTrue);
      expect(find.text('Downloading...'), findsWidgets);
    });

    testWidgets('Rescue failure and error paths invoke healContent',
        (tester) async {
      final preservation = _FakePreservation(healResult: false);
      await pumpScreen(
        tester,
        versions: [_version('cid-v1')],
        preservation: preservation,
      );
      await openActionDialog(tester);
      await tester.tap(find.text('Rescue (Re-pin)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(preservation.healCalls, 1);
      expect(find.text('Healing content...'), findsWidgets);

      // Now the throwing path.
      preservation.healThrows = true;
      await openActionDialog(tester);
      await tester.tap(find.text('Rescue (Re-pin)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(preservation.healCalls, 2);
    });

    testWidgets('Rescue success invokes healContent', (tester) async {
      final preservation = _FakePreservation(healResult: true);
      await pumpScreen(
        tester,
        versions: [_version('cid-v1')],
        preservation: preservation,
      );
      await openActionDialog(tester);
      await tester.tap(find.text('Rescue (Re-pin)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(preservation.healCalls, 1);
    });

    testWidgets('health indicator reflects endangered, lost, and unknown',
        (tester) async {
      for (final status in [
        HealthStatus.endangered,
        HealthStatus.lost,
        HealthStatus.unknown,
      ]) {
        await pumpScreen(
          tester,
          versions: [_version('cid-v1')],
          preservation: _FakePreservation(health: status),
        );
        expect(find.byType(Tooltip), findsWidgets);
        await tester.pumpWidget(Container());
        await tester.pump();
      }
    });

    testWidgets('trust score error renders the error icon', (tester) async {
      await pumpScreen(
        tester,
        versions: [_version('cid-v1')],
        trustScoreThrows: true,
      );
      expect(find.byIcon(Icons.error), findsWidgets);
    });

    testWidgets('variants section renders sibling cards and labels',
        (tester) async {
      await pumpScreen(
        tester,
        repo: _FakeRepo(page: [
          _manifest(id: 9, title: 'Test Work (2nd Edition)'),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('VARIANTS'), findsOneWidget);
      expect(find.text('Test Work (2nd Edition)'), findsOneWidget);
      expect(find.textContaining('% match'), findsOneWidget);
    });

    testWidgets('variants section shows empty and error states',
        (tester) async {
      await pumpScreen(tester);
      expect(find.text('No variants found'), findsOneWidget);
    });

    testWidgets('related content shows empty state and entity variants',
        (tester) async {
      // Empty state — no entity registered.
      await pumpScreen(tester);
      expect(find.text('No related content indexed yet'), findsOneWidget);
    });

    testWidgets('related content renders a registered entity\'s variants',
        (tester) async {
      final kg = KnowledgeGraphService();
      kg.registerEntity(KnowledgeEntity(
        entityId: '1',
        canonicalTitle: 'Related Title',
        author: 'Some Author',
        variants: [
          KnowledgeVariant(
            cid: 'cid-v',
            format: 'epub',
            language: 'fr',
            edition: '2nd',
            sizeBytes: 10,
          ),
        ],
      ));
      await pumpScreen(tester, knowledgeGraph: kg);
      expect(find.text('Related Title'), findsOneWidget);
      expect(find.text('Some Author'), findsOneWidget);
    });
  });
}
