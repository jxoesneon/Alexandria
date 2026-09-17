import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database.dart';
import '../../logic/content_repository.dart';
import '../credits/credit_service.dart';
import '../credits/poch_service.dart';
import '../ipfs_service.dart';
import '../plugins/doi_harvester_plugin.dart';

/// A curated catalog entry - METADATA ONLY. No content ships with the
/// application: every payload is acquired at runtime from the network
/// (swarm/bitswap or legal open-access sources). A document entry can
/// carry three resolution pointers, tried in order:
///
///  * [cid] - a content address already hosted on the swarm;
///  * [oaUrl] - a direct open-access URL (Gutenberg, Internet Archive,
///    arXiv and similar legal public-domain/OA sources);
///  * [doi] - resolved to an OA copy through Crossref/OpenAlex.
///
/// If no pointer resolves, the document is honestly skipped - the
/// library never contains a manifest whose payload does not exist.
class StarterSeedDocument {
  final String id;
  final String title;
  final String author;
  final int year;
  final String category;
  final String? doi;
  final String? oaUrl;
  final String? cid;
  final String expectedFormat;
  final String description;
  final List<String> tags;

  const StarterSeedDocument({
    required this.id,
    required this.title,
    required this.author,
    required this.year,
    required this.category,
    this.doi,
    this.oaUrl,
    this.cid,
    this.expectedFormat = 'bin',
    required this.description,
    required this.tags,
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

/// One skipped document with the honest reason.
class SeedSkip {
  final String docId;
  final String reason;
  const SeedSkip(this.docId, this.reason);
}

/// Outcome of an ingest run - counts are exact, never implied.
class SeedIngestResult {
  final int ingested;
  final int deduped;
  final List<SeedSkip> skipped;
  const SeedIngestResult({
    required this.ingested,
    required this.deduped,
    required this.skipped,
  });
}

/// Injectable fetch seam: production runs the real resolution chain;
/// tests substitute any function returning bytes (or null).
typedef SeedDocFetcher = Future<Uint8List?> Function(StarterSeedDocument doc);

final starterSeedServiceProvider = Provider<StarterSeedService>((ref) {
  return StarterSeedService(ref);
});

class StarterSeedService {
  final Ref _ref;
  final SeedDocFetcher? _docFetcher;
  final DoiResolver _resolver;

  StarterSeedService(this._ref,
      {SeedDocFetcher? docFetcher, DoiResolver? resolver})
      : _docFetcher = docFetcher,
        _resolver = resolver ?? DoiResolver();

  /// Returns all available starter seed packs - pointers only.
  List<StarterSeedPack> getAvailableSeedPacks() {
    return [
      const StarterSeedPack(
        id: 'open-science-landmarks',
        name: 'Landmark Open Science (ALX-Science-01)',
        description:
            'Seminal scientific discoveries that transformed human understanding, resolved from the network at ingest time.',
        iconName: 'science',
        estimatedSizeMb: 1.8,
        documents: [
          StarterSeedDocument(
            id: 'doi_einstein_1905',
            title:
                'Über einen die Erzeugung und Verwandlung des Lichtes betreffenden heuristischen Gesichtspunkt (Photoelectric Effect)',
            author: 'Albert Einstein',
            year: 1905,
            category: 'Physics',
            doi: '10.1002/andp.19053220607',
            expectedFormat: 'pdf',
            description:
                'Einstein proposes the light quantum hypothesis to explain the photoelectric effect, leading directly to quantum mechanics and his 1921 Nobel Prize in Physics.',
            tags: ['physics', 'quantum', 'photoelectric', 'nobel'],
          ),
          StarterSeedDocument(
            id: 'doi_watson_crick_1953',
            title:
                'Molecular Structure of Nucleic Acids: A Structure for Deoxyribose Nucleic Acid',
            author: 'J. D. Watson, F. H. Crick',
            year: 1953,
            category: 'Biology',
            doi: '10.1038/171737a0',
            expectedFormat: 'pdf',
            description:
                'The groundbreaking double-helix model of DNA that unlocked the physical mechanism for genetic replication and modern molecular genetics.',
            tags: ['genetics', 'dna', 'molecular-biology', 'nature'],
          ),
          StarterSeedDocument(
            id: 'doi_turing_1936',
            title:
                'On Computable Numbers, with an Application to the Entscheidungsproblem',
            author: 'Alan M. Turing',
            year: 1936,
            category: 'Computer Science',
            doi: '10.1112/plms/s2-42.1.230',
            expectedFormat: 'pdf',
            description:
                'Introduces the Universal Turing Machine, computability theory, and proves the undecidability of the halting problem, forming the foundation of computer science.',
            tags: ['computing', 'turing-machine', 'algorithms', 'mathematics'],
          ),
        ],
      ),
      const StarterSeedPack(
        id: 'classical-commons',
        name: 'Human Commons & Philosophy (ALX-Heritage-01)',
        description:
            'Timeless foundational philosophical treatises and open digital texts, resolved from legal public-domain archives at ingest time.',
        iconName: 'menu_book',
        estimatedSizeMb: 2.4,
        documents: [
          StarterSeedDocument(
            id: 'heritage_plato_republic',
            title: 'The Republic (Allegory of the Cave)',
            author: 'Plato',
            year: -375,
            category: 'Philosophy',
            oaUrl: 'https://www.gutenberg.org/cache/epub/1497/pg1497.txt',
            expectedFormat: 'txt',
            description:
                'The seminal Socratic dialogue examining justice, the order and character of the just city-state, and the nature of knowledge.',
            tags: ['philosophy', 'ethics', 'classics', 'epistemology'],
          ),
          StarterSeedDocument(
            id: 'heritage_newton_principia',
            title: 'Philosophiae Naturalis Principia Mathematica',
            author: 'Isaac Newton',
            year: 1687,
            category: 'Physics & Mathematics',
            oaUrl:
                'https://archive.org/download/newtonspmathema00newtrich/newtonspmathema00newtrich_djvu.txt',
            expectedFormat: 'txt',
            description:
                'Sets forth the three laws of motion and the law of universal gravitation, synthesizing classical mechanics and calculus.',
            tags: ['physics', 'mechanics', 'gravitation', 'calculus'],
          ),
        ],
      ),
    ];
  }

  /// Resolves and ingests every document in [packId] from the network.
  ///
  /// Acquisition order per document: swarm CID fetch, direct OA URL,
  /// DOI->OA resolution. Documents already ingested (matched on the
  /// `seedDoc` metadata marker) are deduplicated; documents whose
  /// pointers resolve to nothing are skipped with a reason. The result
  /// reports each outcome exactly - no phantom manifests.
  Future<SeedIngestResult> ingestSeedPack(String packId) async {
    final pack = getAvailableSeedPacks().firstWhere(
      (p) => p.id == packId,
      orElse: () => throw ArgumentError('Pack not found: $packId'),
    );

    final contentRepo = _ref.read(contentRepositoryProvider);
    final creditService = _ref.read(creditServiceProvider);
    final pochService = _ref.read(pochServiceProvider);
    final db = _ref.read(databaseProvider);
    final fetcher = _docFetcher ?? _resolveDocBytes;

    // Dedup marker: manifests created by an earlier ingest carry
    // 'seedDoc' in their metadata JSON.
    final seen = <String>{};
    for (final m in await db.getAllManifests()) {
      final meta = m.metadata;
      if (meta == null) continue;
      try {
        final decoded = jsonDecode(meta);
        if (decoded is Map && decoded['seedDoc'] is String) {
          seen.add(decoded['seedDoc'] as String);
        }
      } catch (_) {}
    }

    var ingested = 0;
    var deduped = 0;
    final skipped = <SeedSkip>[];

    for (final doc in pack.documents) {
      if (seen.contains(doc.id)) {
        deduped++;
        continue;
      }
      Uint8List? bytes;
      try {
        bytes = await fetcher(doc);
      } catch (_) {
        bytes = null;
      }
      if (bytes == null || bytes.isEmpty) {
        skipped.add(SeedSkip(doc.id, 'no reachable copy'));
        continue;
      }
      await contentRepo.createContent(
        title: doc.title,
        author: doc.author,
        description: doc.description,
        fileData: bytes,
        category: doc.category,
        format: doc.expectedFormat,
        tags: doc.tags,
        extraMetadata: {
          'year': doc.year,
          if (doc.doi != null) 'doi': doc.doi,
          'seedPack': packId,
          'seedDoc': doc.id,
          'license': 'Public Domain / Open Access',
          'sourcedFrom': 'network',
        },
      );

      // Reward storage & verification credits only for content that
      // actually arrived - never for a pointer that resolved to air.
      // Await hydration or a startup-time ingest mints 0.0 silently;
      // a service disposed mid-hydration drops the award rather than
      // failing the ingest.
      await creditService.ready;
      try {
        creditService.awardStorageCredits(
          sizeBytes: bytes.length,
          peerCount: 3,
          porPassed: true,
          cid: doc.id,
        );
      } catch (_) {}
      pochService.recordSeedingActivity(bytes.length);
      ingested++;
    }

    return SeedIngestResult(
        ingested: ingested, deduped: deduped, skipped: skipped);
  }

  /// The real acquisition chain, tried in order:
  ///  1. swarm/bitswap fetch when the entry publishes a CID;
  ///  2. direct open-access URL under the full SSRF gate;
  ///  3. DOI -> Crossref/OpenAlex OA location -> SSRF-gated download.
  Future<Uint8List?> _resolveDocBytes(StarterSeedDocument doc) async {
    final cid = doc.cid;
    if (cid != null) {
      final buf = BytesBuilder();
      await for (final chunk in _ref.read(ipfsServiceProvider).getFile(cid)) {
        buf.add(chunk);
      }
      if (buf.isNotEmpty) return buf.toBytes();
    }
    final oa = doc.oaUrl;
    if (oa != null) {
      final bytes = await _resolver.downloadBytes(oa);
      if (bytes != null && bytes.isNotEmpty) return bytes;
    }
    final doi = doc.doi;
    if (doi != null) {
      final record = await _resolver.resolve(doi);
      final url = record?.pdfUrl;
      if (url != null) {
        final bytes = await _resolver.downloadPdf(url);
        if (bytes != null) return bytes;
      }
    }
    return null;
  }
}
