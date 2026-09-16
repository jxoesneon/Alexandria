import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/plugin_service.dart';

void main() {
  group('DoiHarvesterPlugin Tests', () {
    test('DoiRecord formatting, bibtex and markdown dossier generation', () {
      final record = DoiRecord(
        doi: '10.1038/s41586-020-2649-2',
        title: 'Array programming with NumPy',
        authors: [
          'Charles R. Harris',
          'K. Jarrod Millman',
          'Stéfan J. van der Walt'
        ],
        journal: 'Nature',
        year: 2020,
        volume: '585',
        issue: '7825',
        pages: '357-362',
        publisher: 'Springer Science and Business Media LLC',
        abstractText:
            'Array programming provides a powerful, compact syntax...',
        subjects: ['Computer science', 'Scientific data'],
        citationCount: 4500,
        isOpenAccess: true,
        pdfUrl: 'https://nature.com/articles/s41586-020-2649-2.pdf',
      );

      expect(record.formattedAuthors, 'Charles R. Harris et al.');
      expect(record.toBibtex().contains('@article{'), isTrue);
      expect(record.toBibtex().contains('10.1038/s41586-020-2649-2'), isTrue);

      final markdown = record.toMarkdownDossier();
      expect(markdown.contains('# Array programming with NumPy'), isTrue);
      expect(markdown.contains('**DOI:**'), isTrue);
      expect(markdown.contains('## BibTeX Citation'), isTrue);

      final map = record.toMap();
      expect(map['doi'], '10.1038/s41586-020-2649-2');
      expect(map['isOpenAccess'], isTrue);
    });

    test('DoiRecord single and dual author formatting', () {
      final single = DoiRecord(
        doi: '10.1234/single',
        title: 'Single Author Study',
        authors: ['Ada Lovelace'],
        journal: 'Scientific Memoirs',
      );
      expect(single.formattedAuthors, 'Ada Lovelace');

      final dual = DoiRecord(
        doi: '10.1234/dual',
        title: 'Dual Author Study',
        authors: ['Ada Lovelace', 'Charles Babbage'],
        journal: 'Scientific Memoirs',
      );
      expect(dual.formattedAuthors, 'Ada Lovelace & Charles Babbage');

      final empty = DoiRecord(
        doi: '10.1234/empty',
        title: 'Empty Author Study',
        authors: [],
        journal: 'Anonymous',
      );
      expect(empty.formattedAuthors, 'Unknown Author');
    });

    test('DoiResolver normalization and extraction from text', () {
      expect(
        DoiResolver.normalizeDoi('https://doi.org/10.1038/s41586-020-2649-2'),
        '10.1038/s41586-020-2649-2',
      );
      expect(
        DoiResolver.normalizeDoi('http://dx.doi.org/10.1145/3377811.3380327'),
        '10.1145/3377811.3380327',
      );
      expect(
        DoiResolver.normalizeDoi('doi: 10.1126/science.1058040.'),
        '10.1126/science.1058040',
      );

      const sampleText = '''
Here are some papers:
1. https://doi.org/10.1038/s41586-020-2649-2 in Nature.
2. Check doi: 10.1145/3377811.3380327 for systems research.
3. Classic: 10.1126/science.1058040
      ''';

      final extracted = DoiResolver.extractDoisInText(sampleText);
      expect(extracted.length, 3);
      expect(extracted.contains('10.1038/s41586-020-2649-2'), isTrue);
      expect(extracted.contains('10.1145/3377811.3380327'), isTrue);
      expect(extracted.contains('10.1126/science.1058040'), isTrue);
    });

    test('DoiHarvesterPlugin manifest and action execution', () async {
      final plugin = DoiHarvesterPlugin();
      expect(plugin.manifest.id, 'org.alexandria.plugin.doi-harvester');
      expect(plugin.actions.length, 4);

      // Extract DOIs action
      final extractResult = await plugin.executeAction('extract_dois', {
        'text': 'Read 10.1038/s41586-020-2649-2 and 10.1145/3377811.3380327',
      });
      expect(extractResult.success, isTrue);
      expect((extractResult.data['dois'] as List).length, 2);

      // Batch harvest empty input
      final emptyBatch = await plugin.executeAction('harvest_batch', {
        'input': '',
      });
      expect(emptyBatch.success, isFalse);

      // Unknown action
      final unknownAction = await plugin.executeAction('unknown_action', {});
      expect(unknownAction.success, isFalse);

      // Hook execution
      await plugin.onHook(PluginHook.onStartup, null);
      plugin.isEnabled = false;
      expect(plugin.isEnabled, isFalse);
    });

    test('DoiRecord.fromCrossref parses complex responses', () {
      final crossrefJson = {
        'DOI': '10.1038/s41586-020-2649-2',
        'title': ['Array programming with NumPy'],
        'author': [
          {'given': 'Charles R.', 'family': 'Harris'},
          {'name': 'NumPy Developers'},
        ],
        'container-title': ['Nature'],
        'published-print': {
          'date-parts': [
            [2020, 9, 15]
          ]
        },
        'abstract': '<jats:p>Array programming syntax...</jats:p>',
        'subject': ['Computer Science'],
        'is-referenced-by-count': 4200,
        'link': [
          {
            'content-type': 'application/pdf',
            'URL': 'https://nature.com/paper.pdf'
          }
        ],
        'license': [
          {'URL': 'https://creativecommons.org/licenses/by/4.0/'}
        ],
      };

      final record = DoiRecord.fromCrossref(crossrefJson);
      expect(record.doi, '10.1038/s41586-020-2649-2');
      expect(record.authors.length, 2);
      expect(record.authors[0], 'Charles R. Harris');
      expect(record.authors[1], 'NumPy Developers');
      expect(record.year, 2020);
      expect(record.month, 9);
      expect(record.abstractText, 'Array programming syntax...');
      expect(record.isOpenAccess, isTrue);
      expect(record.pdfUrl, 'https://nature.com/paper.pdf');
    });

    test('DoiRecord.fromOpenAlex parses work metadata', () {
      final openAlexJson = {
        'doi': 'https://doi.org/10.1038/s41586-020-2649-2',
        'title': 'Array programming with NumPy',
        'authorships': [
          {
            'author': {'display_name': 'Charles R. Harris'}
          }
        ],
        'primary_location': {
          'source': {'display_name': 'Nature'},
          'pdf_url': 'https://nature.com/paper.pdf',
          'license': 'cc-by',
        },
        'publication_year': 2020,
        'cited_by_count': 5000,
        'open_access': {'is_oa': true},
        'abstract_inverted_index': {
          'Array': [0],
          'programming': [1],
          'with': [2],
          'NumPy': [3]
        },
        'concepts': [
          {'display_name': 'Computer science'}
        ],
      };

      final record = DoiRecord.fromOpenAlex(openAlexJson);
      expect(record.doi, '10.1038/s41586-020-2649-2');
      expect(record.journal, 'Nature');
      expect(record.year, 2020);
      expect(record.citationCount, 5000);
      expect(record.abstractText, 'Array programming with NumPy');
      expect(record.isOpenAccess, isTrue);
      expect(record.sourceApi, 'openalex');
    });

    test(
        'DoiHarvesterPlugin ingestRecord returns error when context is uninitialized',
        () async {
      final plugin = DoiHarvesterPlugin();
      final record = DoiRecord(
        doi: '10.1234/test',
        title: 'Test Paper',
        authors: ['Author A'],
        journal: 'Journal of Tests',
      );

      final result = await plugin.ingestRecord(record);
      expect(result['success'], isFalse);
      expect(result['error'], contains('Plugin context not initialized'));
    });
  });
}
