import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/knowledge_graph_service.dart';

void main() {
  group('KnowledgeGraphService (test/services)', () {
    late KnowledgeGraphService graph;

    setUp(() {
      graph = KnowledgeGraphService();
    });

    test('provider exposes a service instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(knowledgeGraphServiceProvider),
        isA<KnowledgeGraphService>(),
      );
    });

    test('registerEntity and getEntity', () {
      final entity = KnowledgeEntity(
        entityId: 'e1',
        canonicalTitle: 'Title',
        author: 'Author',
        tags: ['tag'],
      );
      graph.registerEntity(entity);

      expect(graph.getEntity('e1'), equals(entity));
      expect(graph.getEntity('missing'), isNull);
    });

    test('addVariant appends a new variant to an entity', () {
      final entity = KnowledgeEntity(entityId: 'e2', canonicalTitle: 'Book');
      graph.registerEntity(entity);

      final variant = KnowledgeVariant(
        cid: 'cid-v1',
        format: 'pdf',
        language: 'en',
        sizeBytes: 1000,
      );
      graph.addVariant('e2', variant);

      expect(graph.getEntity('e2')!.variants.length, equals(1));
      expect(graph.getEntity('e2')!.variants.first.cid, equals('cid-v1'));
    });

    test('addVariant throws for missing entity', () {
      expect(
        () => graph.addVariant(
            'missing',
            KnowledgeVariant(
              cid: 'cid',
              format: 'pdf',
              language: 'en',
              sizeBytes: 1,
            )),
        throwsArgumentError,
      );
    });

    test('addRelation does not throw', () {
      graph.registerEntity(KnowledgeEntity(entityId: 'a', canonicalTitle: 'A'));
      graph.registerEntity(KnowledgeEntity(entityId: 'b', canonicalTitle: 'B'));

      expect(
        () => graph.addRelation('a', 'b', KnowledgeRelationType.translationOf),
        returnsNormally,
      );
    });

    test('selectOptimalVariant returns null for missing or variant-less entity',
        () {
      graph.registerEntity(
          KnowledgeEntity(entityId: 'empty', canonicalTitle: 'Empty'));
      expect(graph.selectOptimalVariant('missing'), isNull);
      expect(graph.selectOptimalVariant('empty'), isNull);
    });

    test('selectOptimalVariant filters by language and format', () {
      final entity = KnowledgeEntity(
        entityId: 'e3',
        canonicalTitle: 'Iliad',
        variants: [
          KnowledgeVariant(
            cid: 'en-pdf',
            format: 'pdf',
            language: 'en',
            sizeBytes: 1000,
          ),
          KnowledgeVariant(
            cid: 'gr-epub',
            format: 'epub',
            language: 'gr',
            sizeBytes: 1000,
          ),
        ],
      );
      graph.registerEntity(entity);

      final greekEpub = graph.selectOptimalVariant(
        'e3',
        preferredLanguage: 'gr',
        preferredFormat: 'epub',
      );
      expect(greekEpub?.cid, equals('gr-epub'));
    });

    test('selectOptimalVariant falls back when filters exclude all', () {
      final entity = KnowledgeEntity(
        entityId: 'e4',
        canonicalTitle: 'Odyssey',
        variants: [
          KnowledgeVariant(
            cid: 'high-quality',
            format: 'pdf',
            language: 'en',
            sizeBytes: 2000,
            peerCount: 10,
            isPinned: true,
            honorTrustScore: 100,
          ),
          KnowledgeVariant(
            cid: 'low-quality',
            format: 'pdf',
            language: 'en',
            sizeBytes: 2000,
            peerCount: 1,
            isPinned: false,
            honorTrustScore: 10,
          ),
        ],
      );
      graph.registerEntity(entity);

      final optimal = graph.selectOptimalVariant(
        'e4',
        preferredLanguage: 'fr',
        preferredFormat: 'epub',
      );
      expect(optimal?.cid, equals('high-quality'));
    });

    test('searchEntities matches title, author, and tags', () {
      graph.registerEntity(KnowledgeEntity(
        entityId: 'e5',
        canonicalTitle: 'Meditations',
        author: 'Marcus Aurelius',
        tags: ['stoicism', 'philosophy'],
      ));

      expect(graph.searchEntities('Meditations'), hasLength(1));
      expect(graph.searchEntities('Marcus'), hasLength(1));
      expect(graph.searchEntities('stoicism'), hasLength(1));
      expect(graph.searchEntities('physics'), isEmpty);
    });

    test('KnowledgeVariant toJson includes all fields', () {
      final variant = KnowledgeVariant(
        cid: 'cid',
        format: 'pdf',
        language: 'en',
        edition: 'second',
        resolution: VariantResolution.hd1080p,
        sizeBytes: 1000,
        peerCount: 5,
        isPinned: true,
        honorTrustScore: 20,
      );

      final json = variant.toJson();
      expect(json['cid'], equals('cid'));
      expect(json['format'], equals('pdf'));
      expect(json['language'], equals('en'));
      expect(json['edition'], equals('second'));
      expect(json['resolution'], equals('hd1080p'));
      expect(json['sizeBytes'], equals(1000));
      expect(json['peerCount'], equals(5));
      expect(json['isPinned'], isTrue);
      expect(json['honorTrustScore'], equals(20));
    });

    test('KnowledgeEntity toJson includes nested variants', () {
      final entity = KnowledgeEntity(
        entityId: 'e6',
        canonicalTitle: 'Physics',
        author: 'Aristotle',
        tags: ['science'],
        variants: [
          KnowledgeVariant(
            cid: 'cid-physics',
            format: 'epub',
            language: 'gr',
            sizeBytes: 500,
          ),
        ],
      );

      final json = entity.toJson();
      expect(json['entityId'], equals('e6'));
      expect(json['canonicalTitle'], equals('Physics'));
      expect(json['author'], equals('Aristotle'));
      expect(json['tags'], equals(['science']));
      expect(json['variants'], hasLength(1));
    });
  });
}
