import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart';
import 'package:alexandria/logic/content_repository.dart';
import 'package:alexandria/services/plugin_service.dart';

void main() {
  group('DOI Normalization & Extraction Tests', () {
    test('normalizes DOIs across diverse URI and prefix formats', () {
      expect(
        DoiResolver.normalizeDoi('https://doi.org/10.1038/s41586-020-2649-2'),
        '10.1038/s41586-020-2649-2',
      );
      expect(
        DoiResolver.normalizeDoi('http://dx.doi.org/10.1145/3377811.3380327.'),
        '10.1145/3377811.3380327',
      );
      expect(
        DoiResolver.normalizeDoi('doi: 10.1073/pnas.123456789;'),
        '10.1073/pnas.123456789',
      );
      expect(
        DoiResolver.normalizeDoi('  10.1126/science.1058040> '),
        '10.1126/science.1058040',
      );
    });

    test('extracts multiple unique DOIs from arbitrary literature text and bibliography', () {
      const sampleText = '''
      # Archival Bibliography
      1. Quantum supremacy using a programmable superconducting processor.
         Available at https://doi.org/10.1038/s41586-019-1666-5.
      2. Attention is all you need. Vaswani et al. (doi:10.48550/arXiv.1706.03762).
      3. Repetition of previous: [10.1038/s41586-019-1666-5].
      4. Another work: https://dx.doi.org/10.1103/PhysRevLett.116.061102.
      ''';

      final dois = DoiResolver.extractDoisInText(sampleText);
      expect(dois.length, 3);
      expect(dois, contains('10.1038/s41586-019-1666-5'));
      expect(dois, contains('10.48550/arXiv.1706.03762'));
      expect(dois, contains('10.1103/PhysRevLett.116.061102'));
    });
  });

  group('Scholarly Metadata Parsing & BibTeX Synthesis', () {
    test('parses Crossref JSON metadata and cleans JATS XML abstracts', () {
      final crossrefJson = {
        'DOI': '10.1038/s41586-020-2649-2',
        'title': ['Array programming with NumPy'],
        'author': [
          {'given': 'Charles R.', 'family': 'Harris'},
          {'given': 'K. Jarrod', 'family': 'Millman'},
          {'given': 'Stéfan J.', 'family': 'van der Walt'},
        ],
        'container-title': ['Nature'],
        'published-print': {
          'date-parts': [
            [2020, 9, 17]
          ]
        },
        'volume': '585',
        'issue': '7825',
        'page': '357-362',
        'publisher': 'Springer Science and Business Media LLC',
        'abstract': '<jats:p>Array programming provides a powerful, compact and expressive syntax for accessing, manipulating and computing on data in vectors, matrices and higher-dimensional arrays.</jats:p>',
        'subject': ['Computer Science', 'Data Analysis'],
        'is-referenced-by-count': 5420,
        'link': [
          {
            'URL': 'https://www.nature.com/articles/s41586-020-2649-2.pdf',
            'content-type': 'application/pdf',
          }
        ],
      };

      final record = DoiRecord.fromCrossref(crossrefJson);

      expect(record.doi, '10.1038/s41586-020-2649-2');
      expect(record.title, 'Array programming with NumPy');
      expect(record.authors.length, 3);
      expect(record.formattedAuthors, 'Charles R. Harris et al.');
      expect(record.journal, 'Nature');
      expect(record.year, 2020);
      expect(record.month, 9);
      expect(record.volume, '585');
      expect(record.issue, '7825');
      expect(record.pages, '357-362');
      expect(record.citationCount, 5420);
      expect(record.abstractText, startsWith('Array programming provides'));
      expect(record.abstractText, isNot(contains('<jats:p>')));
      expect(record.isOpenAccess, isTrue);
      expect(record.pdfUrl, 'https://www.nature.com/articles/s41586-020-2649-2.pdf');

      // Check BibTeX format
      final bibtex = record.toBibtex();
      expect(bibtex, contains('@article{Harris2020,'));
      expect(bibtex, contains('doi = {10.1038/s41586-020-2649-2}'));
      expect(bibtex, contains('journal = {{Nature}}'));
      expect(bibtex, contains('year = {2020}'));

      // Check Markdown Dossier
      final md = record.toMarkdownDossier();
      expect(md, contains('# Array programming with NumPy'));
      expect(md, contains('**Journal:** Nature'));
      expect(md, contains('```bibtex'));
    });

    test('parses OpenAlex JSON and reconstructs inverted index abstract', () {
      final openAlexJson = {
        'doi': 'https://doi.org/10.1007/s11276-008-0131-4',
        'title': 'Decentralized Peer-to-Peer Content Routing',
        'authorships': [
          {
            'author': {'display_name': 'Dr. Ada Lovelace'}
          },
          {
            'author': {'display_name': 'Alan Turing'}
          }
        ],
        'publication_year': 2024,
        'primary_location': {
          'source': {'display_name': 'Wireless Networks'},
          'pdf_url': 'https://example.org/p2p-routing.pdf',
        },
        'open_access': {'is_oa': true, 'oa_url': 'https://example.org/p2p-routing.pdf'},
        'cited_by_count': 142,
        'abstract_inverted_index': {
          'Decentralized': [0],
          'networks': [1],
          'provide': [2],
          'resilience.': [3],
        },
      };

      final record = DoiRecord.fromOpenAlex(openAlexJson);

      expect(record.doi, '10.1007/s11276-008-0131-4');
      expect(record.title, 'Decentralized Peer-to-Peer Content Routing');
      expect(record.formattedAuthors, 'Dr. Ada Lovelace & Alan Turing');
      expect(record.journal, 'Wireless Networks');
      expect(record.year, 2024);
      expect(record.isOpenAccess, isTrue);
      expect(record.pdfUrl, 'https://example.org/p2p-routing.pdf');
      expect(record.abstractText, 'Decentralized networks provide resilience.');
    });
  });

  group('DOI Harvester Safe Harbor Ingestion Integration Tests', () {
    late ProviderContainer container;
    late ContentRepository repository;
    late DoiHarvesterPlugin plugin;

    setUp(() async {
      container = ProviderContainer();
      repository = container.read(contentRepositoryProvider);
      plugin = DoiHarvesterPlugin();
      await plugin.initialize(PluginContext(
        container: container,
        pluginId: plugin.manifest.id,
      ));
    });

    tearDown(() {
      container.dispose();
    });

    test('ingests scholarly DOI record into ContentRepository and Drift database', () async {
      final record = DoiRecord(
        doi: '10.1038/nature12345',
        title: 'Quantum Entanglement in Macroscopic Crystals',
        authors: ['Alice Smith', 'Bob Jones'],
        journal: 'Nature Physics',
        year: 2025,
        publisher: 'Nature Publishing Group',
        abstractText: 'We report experimental observation of entanglement across spatial domains.',
        subjects: ['Quantum Physics', 'Optics'],
        citationCount: 42,
      );

      final result = await plugin.ingestRecord(record, downloadPdf: false);
      expect(result['success'], isTrue);
      expect(result['uuid'], isNotNull);
      expect(result['title'], 'Quantum Entanglement in Macroscopic Crystals');
      expect(result['format'], 'md');

      final uuid = result['uuid'] as String;
      final manifest = await repository.getManifestByUuid(uuid);
      expect(manifest, isNotNull);
      expect(manifest!.title, 'Quantum Entanglement in Macroscopic Crystals');
      expect(manifest.author, 'Alice Smith & Bob Jones');
      expect(manifest.category, 'academicAndScience');
      expect(manifest.tags, contains('doi'));
      expect(manifest.tags, contains('academic'));

      // Verify metadata payload
      final extraMeta = jsonDecode(manifest.metadata!) as Map<String, dynamic>;
      expect(extraMeta['doi'], '10.1038/nature12345');
      expect(extraMeta['journal'], 'Nature Physics');
      expect(extraMeta['year'], 2025);
      expect(extraMeta['harvesterPlugin'], 'org.alexandria.plugin.doi-harvester');

      // Verify content file retrieval from IPFS blockstore
      final db = container.read(databaseProvider);
      final versions = await db.getVersionsForManifest(manifest.id);
      expect(versions.isNotEmpty, isTrue);

      final version = versions.first;
      expect(version.cid.startsWith('b'), isTrue); // Multihash base32

      final bytes = await repository.retrieveContent(version.cid);
      final content = utf8.decode(bytes);
      expect(content, contains('# Quantum Entanglement in Macroscopic Crystals'));
      expect(content, contains('**DOI:** [https://doi.org/10.1038/nature12345]'));
      expect(content, contains('```bibtex'));
    });

    test('executes action extract_dois via plugin interface', () async {
      final res = await plugin.executeAction('extract_dois', {
        'text': 'References: 10.1016/j.cell.2021.01.001 and https://doi.org/10.1126/science.abc1234',
      });

      expect(res.success, isTrue);
      expect(res.data['count'], 2);
      expect(res.data['dois'], contains('10.1016/j.cell.2021.01.001'));
      expect(res.data['dois'], contains('10.1126/science.abc1234'));
    });
  });
}
