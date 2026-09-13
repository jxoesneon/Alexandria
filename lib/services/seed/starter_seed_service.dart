import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/content_repository.dart';
import '../credits/credit_service.dart';
import '../credits/poch_service.dart';
import 'seed_data_texts.dart';

/// Represents a curated starter archive collection for immediate 1-click seeding
class StarterSeedDocument {
  final String id;
  final String title;
  final String author;
  final int year;
  final String category;
  final String? doi;
  final String description;
  final List<String> tags;
  final String contentMarkdown;
  final String? briefMarkdown;

  const StarterSeedDocument({
    required this.id,
    required this.title,
    required this.author,
    required this.year,
    required this.category,
    this.doi,
    required this.description,
    required this.tags,
    required this.contentMarkdown,
    this.briefMarkdown,
  });
}

class StarterSeedPack {
  final String id;
  final String name;
  final String description;
  final String iconName;
  final double estimatedSizeMb;
  final List<StarterSeedDocument> documents;

  const StarterSeedPack({
    required this.id,
    required this.name,
    required this.description,
    required this.iconName,
    required this.estimatedSizeMb,
    required this.documents,
  });
}

final starterSeedServiceProvider = Provider<StarterSeedService>((ref) {
  return StarterSeedService(ref);
});

class StarterSeedService {
  final Ref _ref;

  StarterSeedService(this._ref);

  /// Returns all available starter seed packs
  List<StarterSeedPack> getAvailableSeedPacks() {
    return [
      const StarterSeedPack(
        id: 'open-science-landmarks',
        name: 'Landmark Open Science (ALX-Science-01)',
        description:
            'Seminal scientific discoveries that transformed human understanding, curated for immutable peer-to-peer preservation.',
        iconName: 'science',
        estimatedSizeMb: 1.8,
        documents: [
          StarterSeedDocument(
            id: 'doi_einstein_1905',
            title: 'Über einen die Erzeugung und Verwandlung des Lichtes betreffenden heuristischen Gesichtspunkt (Photoelectric Effect)',
            author: 'Albert Einstein',
            year: 1905,
            category: 'Physics',
            doi: '10.1002/andp.19053220607',
            description:
                'Einstein proposes the light quantum hypothesis to explain the photoelectric effect, leading directly to quantum mechanics and his 1921 Nobel Prize in Physics.',
            tags: ['physics', 'quantum', 'photoelectric', 'nobel'],
            contentMarkdown: SeedDataTexts.einstein1905PhotoelectricFullText,
            briefMarkdown: SeedDataTexts.einstein1905PhotoelectricBrief,
          ),
          StarterSeedDocument(
            id: 'doi_watson_crick_1953',
            title: 'Molecular Structure of Nucleic Acids: A Structure for Deoxyribose Nucleic Acid',
            author: 'J. D. Watson, F. H. C. Crick',
            year: 1953,
            category: 'Biology',
            doi: '10.1038/171737a0',
            description:
                'The groundbreaking double-helix model of DNA that unlocked the physical mechanism for genetic replication and modern molecular genetics.',
            tags: ['genetics', 'dna', 'molecular-biology', 'nature'],
            contentMarkdown: SeedDataTexts.watsonCrick1953DnaFullText,
            briefMarkdown: SeedDataTexts.watsonCrick1953DnaBrief,
          ),
          StarterSeedDocument(
            id: 'doi_turing_1936',
            title: 'On Computable Numbers, with an Application to the Entscheidungsproblem',
            author: 'Alan M. Turing',
            year: 1936,
            category: 'Computer Science',
            doi: '10.1112/plms/s2-42.1.230',
            description:
                'Introduces the Universal Turing Machine, computability theory, and proves the undecidability of the halting problem, forming the foundation of computer science.',
            tags: ['computing', 'turing-machine', 'algorithms', 'mathematics'],
            contentMarkdown: SeedDataTexts.turing1936ComputableNumbersFullText,
            briefMarkdown: SeedDataTexts.turing1936ComputableNumbersBrief,
          ),
        ],
      ),
      const StarterSeedPack(
        id: 'classical-commons',
        name: 'Human Commons & Philosophy (ALX-Heritage-01)',
        description:
            'Timeless foundational philosophical treatises and open digital texts preserved for universal common heritage.',
        iconName: 'menu_book',
        estimatedSizeMb: 2.4,
        documents: [
          StarterSeedDocument(
            id: 'heritage_plato_republic',
            title: 'The Republic (Allegory of the Cave)',
            author: 'Plato',
            year: -375,
            category: 'Philosophy',
            description:
                'The seminal Socratic dialogue examining justice, the order and character of the just city-state, and the nature of knowledge.',
            tags: ['philosophy', 'ethics', 'classics', 'epistemology'],
            contentMarkdown: SeedDataTexts.platoRepublicCaveFullText,
            briefMarkdown: SeedDataTexts.platoRepublicCaveBrief,
          ),
          StarterSeedDocument(
            id: 'heritage_newton_principia',
            title: 'Philosophiae Naturalis Principia Mathematica',
            author: 'Isaac Newton',
            year: 1687,
            category: 'Physics & Mathematics',
            description:
                'Sets forth the three laws of motion and the law of universal gravitation, synthesizing classical mechanics and calculus.',
            tags: ['physics', 'mechanics', 'gravitation', 'calculus'],
            contentMarkdown: SeedDataTexts.newtonPrincipiaFullText,
            briefMarkdown: SeedDataTexts.newtonPrincipiaBrief,
          ),
        ],
      ),
    ];
  }

  /// Ingests all documents from a chosen seed pack into Alexandria's local library and IPFS node
  Future<int> ingestSeedPack(String packId) async {
    final pack = getAvailableSeedPacks().firstWhere(
      (p) => p.id == packId,
      orElse: () => throw ArgumentError('Pack not found: $packId'),
    );

    final contentRepo = _ref.read(contentRepositoryProvider);
    final creditService = _ref.read(creditServiceProvider);
    final pochService = _ref.read(pochServiceProvider);

    int count = 0;
    for (final doc in pack.documents) {
      final bytes = Uint8List.fromList(utf8.encode(doc.contentMarkdown));
      final uuid = await contentRepo.createContent(
        title: doc.title,
        author: doc.author,
        description: doc.description,
        fileData: bytes,
        category: doc.category,
        format: 'md-unabridged',
        tags: doc.tags,
        extraMetadata: {
          'year': doc.year,
          if (doc.doi != null) 'doi': doc.doi,
          'seedPack': packId,
          'license': 'Public Domain / Open Access',
        },
      );

      // Ingest the companion executive brief as a secondary version under the SAME manifest
      if (doc.briefMarkdown != null) {
        final briefBytes = Uint8List.fromList(utf8.encode(doc.briefMarkdown!));
        await contentRepo.addContentVersion(
          manifestUuid: uuid,
          fileData: briefBytes,
          language: 'en',
          format: 'md-brief',
        );
      }

      // Reward storage & verification credits for seeding
      creditService.awardStorageCredits(
        sizeBytes: bytes.length,
        peerCount: 3,
        porPassed: true,
        cid: doc.id,
      );

      // Update PoCH seeder allocation metrics
      pochService.recordSeedingActivity(bytes.length);
      count++;
    }

    return count;
  }
}
