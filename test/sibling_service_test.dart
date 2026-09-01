import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/sibling_service.dart';

void main() {
  group('SiblingService Tests', () {
    late SiblingService siblingService;

    setUp(() {
      siblingService = SiblingService();
    });

    test(
        'normalizes titles by trimming, lowercasing, and stripping punctuation',
        () {
      expect(siblingService.normalizeTitle('  The Republic (Plato)!  '),
          equals('the republic plato'));
      expect(siblingService.normalizeTitle('Alexandria... - P2P?'),
          equals('alexandria p2p'));
    });

    test('calculates Levenshtein distance and similarity accurately', () {
      expect(
          siblingService.levenshteinDistance('kitten', 'sitting'), equals(3));
      expect(siblingService.calculateSimilarity('The Republic', 'The Republic'),
          equals(1.0));
      expect(siblingService.calculateSimilarity('', ''), equals(0.0));
      expect(
          siblingService.calculateSimilarity(
              'The Odyssey Book 1', 'The Odyssey Book 2'),
          greaterThan(0.85));
    });

    test('identifies sibling variants correctly', () {
      expect(
          siblingService.areSiblings('Principia Mathematica Vol 1',
              'Principia Mathematica Vol 1 (1910)'),
          isTrue);
      expect(siblingService.areSiblings('Moby Dick', 'War and Peace'), isFalse);
    });

    test('detects variant types across resolution, language, and format', () {
      expect(
          siblingService.detectVariantType(
              resolution1: '1080p', resolution2: '4K'),
          equals(VariantType.resolution));
      expect(siblingService.detectVariantType(language1: 'en', language2: 'es'),
          equals(VariantType.language));
      expect(siblingService.detectVariantType(format1: 'pdf', format2: 'epub'),
          equals(VariantType.format));
      expect(siblingService.detectVariantType(), isNull);
    });

    test('finds and sorts candidate siblings', () {
      final candidates = [
        {
          'cid': 'bafy1',
          'title': 'The Art of War (English)',
          'variantType': 'language',
          'variantValue': 'en'
        },
        {
          'cid': 'bafy2',
          'title': 'The Art of War (Spanish)',
          'variantType': 'language',
          'variantValue': 'es'
        },
        {
          'cid': 'bafy3',
          'title': 'Cooking Recipes 101',
          'variantType': 'format',
          'variantValue': 'pdf'
        },
      ];

      final results = siblingService.findSiblings(
        targetTitle: 'The Art of War',
        targetCid: 'bafy_target',
        candidates: candidates,
      );

      expect(results.length, equals(2));
      expect(results.first.title, contains('The Art of War'));
    });
  });
}
