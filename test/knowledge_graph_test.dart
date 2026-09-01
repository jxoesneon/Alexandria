import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/knowledge_graph_service.dart';

void main() {
  group('KnowledgeGraphService Tests', () {
    late KnowledgeGraphService graphService;

    setUp(() {
      graphService = KnowledgeGraphService();
    });

    test('registers entities and selects optimal variant based on health', () {
      final entity = KnowledgeEntity(
        entityId: 'ent_plat_rep',
        canonicalTitle: 'The Republic',
        author: 'Plato',
        tags: ['philosophy', 'politics', 'classics'],
        variants: [
          KnowledgeVariant(
            cid: 'bafy_pdf_low',
            format: 'pdf',
            language: 'en',
            sizeBytes: 1000000,
            peerCount: 1,
            isPinned: false,
          ),
          KnowledgeVariant(
            cid: 'bafy_pdf_healthy',
            format: 'pdf',
            language: 'en',
            sizeBytes: 1200000,
            peerCount: 8,
            isPinned: true,
          ),
        ],
      );

      graphService.registerEntity(entity);
      final optimal = graphService.selectOptimalVariant('ent_plat_rep',
          preferredFormat: 'pdf', preferredLanguage: 'en');

      expect(optimal, isNotNull);
      expect(optimal!.cid, equals('bafy_pdf_healthy'));
    });

    test('searches entities by keyword across title, author, and tags', () {
      graphService.registerEntity(KnowledgeEntity(
        entityId: 'e1',
        canonicalTitle: 'Principia Mathematica',
        author: 'Isaac Newton',
        tags: ['physics', 'calculus'],
      ));

      final results = graphService.searchEntities('calculus');
      expect(results.length, equals(1));
      expect(results.first.canonicalTitle, equals('Principia Mathematica'));
    });
  });
}
