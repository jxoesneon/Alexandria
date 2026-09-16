import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import '../../logic/content_repository.dart';
import '../plugin_service.dart';
import '../url_safety.dart';

/// Structured metadata model for a scholarly work resolved via DOI.
class DoiRecord {
  final String doi;
  final String title;
  final List<String> authors;
  final String journal;
  final int? year;
  final int? month;
  final String? volume;
  final String? issue;
  final String? pages;
  final String? publisher;
  final String? abstractText;
  final List<String> subjects;
  final int? citationCount;
  final String? licenseUrl;
  final bool isOpenAccess;
  final String? pdfUrl;
  final String? bibtex;
  final String sourceApi;

  DoiRecord({
    required this.doi,
    required this.title,
    required this.authors,
    required this.journal,
    this.year,
    this.month,
    this.volume,
    this.issue,
    this.pages,
    this.publisher,
    this.abstractText,
    this.subjects = const [],
    this.citationCount,
    this.licenseUrl,
    this.isOpenAccess = false,
    this.pdfUrl,
    this.bibtex,
    this.sourceApi = 'crossref',
  });

  String get formattedAuthors {
    if (authors.isEmpty) return 'Unknown Author';
    if (authors.length == 1) return authors.first;
    if (authors.length == 2) return '${authors[0]} & ${authors[1]}';
    return '${authors[0]} et al.';
  }

  String toBibtex() {
    if (bibtex != null && bibtex!.isNotEmpty) return bibtex!;
    final citeKey = _generateCiteKey();
    final buffer = StringBuffer();
    buffer.writeln('@article{$citeKey,');
    buffer.writeln('  doi = {$doi},');
    buffer.writeln('  title = {{$title}},');
    if (authors.isNotEmpty) {
      buffer.writeln('  author = {${authors.join(' and ')}},');
    }
    if (journal.isNotEmpty) {
      buffer.writeln('  journal = {{$journal}},');
    }
    if (year != null) {
      buffer.writeln('  year = {$year},');
    }
    if (volume != null && volume!.isNotEmpty) {
      buffer.writeln('  volume = {$volume},');
    }
    if (issue != null && issue!.isNotEmpty) {
      buffer.writeln('  number = {$issue},');
    }
    if (pages != null && pages!.isNotEmpty) {
      buffer.writeln('  pages = {$pages},');
    }
    if (publisher != null && publisher!.isNotEmpty) {
      buffer.writeln('  publisher = {{$publisher}},');
    }
    buffer.writeln('}');
    return buffer.toString();
  }

  String _generateCiteKey() {
    final firstAuthor = authors.isNotEmpty
        ? authors.first.split(' ').last.replaceAll(RegExp(r'\W'), '')
        : 'Alexandria';
    final yr = year ?? DateTime.now().year;
    return '$firstAuthor$yr';
  }

  String toMarkdownDossier() {
    final buffer = StringBuffer();
    buffer.writeln('# $title\n');
    buffer.writeln('**Authors:** ${authors.join(', ')}  ');
    buffer.writeln('**Journal:** $journal  ');
    if (year != null) buffer.writeln('**Year:** $year  ');
    if (volume != null || issue != null) {
      buffer.writeln('**Volume/Issue:** ${volume ?? ''} (${issue ?? ''})  ');
    }
    buffer.writeln('**DOI:** [https://doi.org/$doi](https://doi.org/$doi)  ');
    if (publisher != null) buffer.writeln('**Publisher:** $publisher  ');
    if (citationCount != null) {
      buffer.writeln('**Citations:** $citationCount  ');
    }
    buffer.writeln('**Open Access:** ${isOpenAccess ? "Yes" : "Subscription/Paywalled"}  \n');

    if (abstractText != null && abstractText!.trim().isNotEmpty) {
      buffer.writeln('## Abstract\n');
      buffer.writeln('${abstractText!.trim()}\n');
    }

    buffer.writeln('## BibTeX Citation\n');
    buffer.writeln('```bibtex');
    buffer.writeln(toBibtex());
    buffer.writeln('```\n');

    buffer.writeln('---');
    buffer.writeln('*Archived by Alexandria Decentralized Library & Preservation Engine.*');
    return buffer.toString();
  }

  Map<String, dynamic> toMap() => {
        'doi': doi,
        'title': title,
        'authors': authors,
        'journal': journal,
        'year': year,
        'month': month,
        'volume': volume,
        'issue': issue,
        'pages': pages,
        'publisher': publisher,
        'abstract': abstractText,
        'subjects': subjects,
        'citationCount': citationCount,
        'licenseUrl': licenseUrl,
        'isOpenAccess': isOpenAccess,
        'pdfUrl': pdfUrl,
        'bibtex': toBibtex(),
        'sourceApi': sourceApi,
      };

  factory DoiRecord.fromCrossref(Map<String, dynamic> message) {
    final doi = message['DOI'] as String? ?? '';
    final titles = message['title'] as List<dynamic>?;
    final title = (titles != null && titles.isNotEmpty)
        ? titles.first.toString().trim()
        : 'Untitled Scientific Work';

    final authorList = <String>[];
    if (message['author'] is List) {
      for (final a in message['author'] as List) {
        if (a is Map) {
          final given = a['given']?.toString() ?? '';
          final family = a['family']?.toString() ?? '';
          if (family.isNotEmpty) {
            authorList.add(given.isNotEmpty ? '$given $family' : family);
          } else if (a['name'] != null) {
            authorList.add(a['name'].toString());
          }
        }
      }
    }

    final journals = message['container-title'] as List<dynamic>?;
    final journal = (journals != null && journals.isNotEmpty)
        ? journals.first.toString().trim()
        : (message['publisher']?.toString() ?? 'Scholarly Publication');

    int? year;
    int? month;
    final published = message['published-print'] ??
        message['published-online'] ??
        message['issued'];
    if (published is Map && published['date-parts'] is List) {
      final parts = published['date-parts'] as List;
      if (parts.isNotEmpty && parts.first is List) {
        final dateList = parts.first as List;
        if (dateList.isNotEmpty && dateList[0] is int) {
          year = dateList[0] as int;
        }
        if (dateList.length > 1 && dateList[1] is int) {
          month = dateList[1] as int;
        }
      }
    }

    // Clean JATS XML abstract
    String? abstractText = message['abstract']?.toString();
    if (abstractText != null) {
      abstractText = abstractText
          .replaceAll(RegExp(r'<jats:[^>]+>'), '')
          .replaceAll(RegExp(r'</jats:[^>]+>'), '')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .trim();
    }

    final subjects = <String>[];
    if (message['subject'] is List) {
      for (final s in message['subject'] as List) {
        subjects.add(s.toString());
      }
    }

    // PDF link detection
    String? pdfUrl;
    if (message['link'] is List) {
      for (final link in message['link'] as List) {
        if (link is Map) {
          final ct = link['content-type']?.toString().toLowerCase() ?? '';
          if (ct.contains('pdf') && link['URL'] != null) {
            pdfUrl = link['URL'].toString();
            break;
          }
        }
      }
    }

    return DoiRecord(
      doi: doi,
      title: title,
      authors: authorList,
      journal: journal,
      year: year,
      month: month,
      volume: message['volume']?.toString(),
      issue: message['issue']?.toString(),
      pages: message['page']?.toString(),
      publisher: message['publisher']?.toString(),
      abstractText: abstractText,
      subjects: subjects,
      citationCount: message['is-referenced-by-count'] as int?,
      licenseUrl: (message['license'] is List && (message['license'] as List).isNotEmpty)
          ? message['license'][0]['URL']?.toString()
          : null,
      isOpenAccess: pdfUrl != null,
      pdfUrl: pdfUrl,
      sourceApi: 'crossref',
    );
  }

  factory DoiRecord.fromOpenAlex(Map<String, dynamic> data) {
    final doiRaw = data['doi']?.toString() ?? '';
    final doi = doiRaw.replaceFirst('https://doi.org/', '');
    final title = data['title']?.toString() ?? 'Untitled Scientific Work';

    final authorList = <String>[];
    if (data['authorships'] is List) {
      for (final a in data['authorships'] as List) {
        if (a is Map && a['author'] is Map) {
          final name = a['author']['display_name']?.toString();
          if (name != null && name.isNotEmpty) {
            authorList.add(name);
          }
        }
      }
    }

    final primaryLoc = data['primary_location'] as Map<String, dynamic>?;
    final source = primaryLoc?['source'] as Map<String, dynamic>?;
    final journal = source?['display_name']?.toString() ??
        (data['host_venue']?['display_name']?.toString() ?? 'Scholarly Journal');

    final year = data['publication_year'] as int?;
    final biblio = data['biblio'] as Map<String, dynamic>?;

    // Abstract reconstruction from inverted index if present
    String? abstractText;
    if (data['abstract_inverted_index'] is Map) {
      final index = data['abstract_inverted_index'] as Map<String, dynamic>;
      final wordMap = <int, String>{};
      for (final entry in index.entries) {
        if (entry.value is List) {
          for (final pos in entry.value as List) {
            if (pos is int) wordMap[pos] = entry.key;
          }
        }
      }
      final sortedPositions = wordMap.keys.toList()..sort();
      abstractText = sortedPositions.map((pos) => wordMap[pos]!).join(' ');
    }

    final openAccess = data['open_access'] as Map<String, dynamic>?;
    final isOa = openAccess?['is_oa'] as bool? ?? false;
    final oaUrl = openAccess?['oa_url']?.toString();
    final pdfUrl = primaryLoc?['pdf_url']?.toString() ?? oaUrl;

    return DoiRecord(
      doi: doi,
      title: title,
      authors: authorList,
      journal: journal,
      year: year,
      volume: biblio?['volume']?.toString(),
      issue: biblio?['issue']?.toString(),
      pages: biblio?['first_page'] != null
          ? '${biblio!['first_page']}-${biblio['last_page'] ?? ''}'
          : null,
      publisher: source?['publisher']?.toString(),
      abstractText: abstractText,
      isOpenAccess: isOa,
      pdfUrl: pdfUrl,
      citationCount: data['cited_by_count'] as int?,
      sourceApi: 'openalex',
    );
  }
}

/// Core DOI Resolver capable of querying Crossref, OpenAlex, and DOI Content Negotiation.
class DoiResolver {
  final HttpClient? _customHttpClient;

  DoiResolver([this._customHttpClient]);

  static final RegExp _doiPattern = RegExp(
    r'10\.\d{4,9}/[-._;()/:A-Za-z0-9]+',
    caseSensitive: false,
  );

  /// Normalizes a DOI string by removing URL prefixes and trailing punctuation.
  static String normalizeDoi(String raw) {
    var cleaned = raw.trim();
    cleaned = cleaned.replaceFirst(RegExp(r'^https?://(dx\.)?doi\.org/', caseSensitive: false), '');
    cleaned = cleaned.replaceFirst(RegExp(r'^doi:\s*', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r'[\s>\)\]\.;]+$'), '');
    return cleaned;
  }

  /// Extracts all valid unique DOIs from arbitrary text, bibliography, or markdown.
  static List<String> extractDoisInText(String text) {
    final matches = _doiPattern.allMatches(text);
    final results = <String>{};
    for (final match in matches) {
      final doi = normalizeDoi(match.group(0)!);
      if (doi.isNotEmpty) {
        results.add(doi);
      }
    }
    return results.toList();
  }

  /// Resolves DOI metadata querying Crossref first, falling back to OpenAlex and DOI.org content negotiation.
  Future<DoiRecord?> resolve(String rawDoi) async {
    final doi = normalizeDoi(rawDoi);
    if (doi.isEmpty) return null;

    final client = _customHttpClient ?? HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);

    // 1. Try Crossref REST API
    try {
      final uri = Uri.parse('https://api.crossref.org/works/$doi');
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'Alexandria-Preservation-Engine/1.0 (mailto:archive@alexandria.pub)');
      request.headers.set('Accept', 'application/json');

      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        if (json['message'] is Map<String, dynamic>) {
          return DoiRecord.fromCrossref(json['message'] as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('Crossref resolution failed for $doi: $e');
    }

    // 2. Fallback to OpenAlex API
    try {
      final uri = Uri.parse('https://api.openalex.org/works/https://doi.org/$doi');
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'Alexandria-Preservation-Engine/1.0 (mailto:archive@alexandria.pub)');
      request.headers.set('Accept', 'application/json');

      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        return DoiRecord.fromOpenAlex(json);
      }
    } catch (e) {
      debugPrint('OpenAlex resolution failed for $doi: $e');
    }

    // 3. Fallback to DOI.org CSL-JSON content negotiation
    try {
      final uri = Uri.parse('https://doi.org/$doi');
      final request = await client.getUrl(uri);
      request.headers.set('Accept', 'application/vnd.citationstyles.csl+json');

      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        return DoiRecord.fromCrossref(json);
      }
    } catch (e) {
      debugPrint('DOI content negotiation failed for $doi: $e');
    }

    return null;
  }

  /// Hard cap on a single PDF download — a hostile or buggy endpoint
  /// streaming unbounded bytes would otherwise exhaust node memory
  /// (red minor-observation hardening).
  static const int maxPdfBytes = 64 * 1024 * 1024; // 64 MiB

  /// Attempts to download PDF bytes for open-access papers.
  /// Aborts and returns null once the response exceeds [maxPdfBytes].
  ///
  /// SSRF gate (round-3 red finding): `pdfUrl` is publisher/Crossref
  /// metadata — attacker-influenced remote input. Before ANY connection
  /// is opened the URL must pass [UrlSafety.requirePublicFetchUri]
  /// (https-only, public host, DNS-checked). Redirects are followed
  /// manually and re-gated per hop so a public landing page cannot 302
  /// the fetch into private space.
  Future<Uint8List?> downloadPdf(String pdfUrl) async {
    final initial = Uri.tryParse(pdfUrl);
    if (initial == null) return null;
    var uri = initial;
    try {
      final client = _customHttpClient ?? HttpClient();
      client.connectionTimeout = const Duration(seconds: 25);
      for (var hop = 0; hop <= UrlSafety.maxRedirectHops; hop++) {
        await UrlSafety.requirePublicFetchUri(uri);
        final request = await client.getUrl(uri);
        // (round-3 red finding) never let the transport auto-follow —
        // each Location target re-enters the SSRF gate above.
        request.followRedirects = false;
        request.headers.set('User-Agent', 'Mozilla/5.0 (compatible; Alexandria/1.0; +https://alexandria.pub)');

        final response = await request.close();
        final location = response.headers.value('location');
        if (_isRedirect(response.statusCode) && location != null) {
          final next = Uri.tryParse(location);
          if (next == null) return null;
          uri = uri.resolveUri(next);
          continue;
        }
        if (response.statusCode == 200) {
          final bytesBuilder = BytesBuilder();
          var oversized = false;
          await for (final chunk in response) {
            if (bytesBuilder.length + chunk.length > maxPdfBytes) {
              oversized = true;
              break;
            }
            bytesBuilder.add(chunk);
          }
          if (oversized) {
            debugPrint('PDF download aborted: exceeds $maxPdfBytes bytes ($pdfUrl)');
            return null;
          }
          final data = bytesBuilder.toBytes();
          // Verify PDF magic header %PDF
          if (data.length > 4 && data[0] == 0x25 && data[1] == 0x50 && data[2] == 0x44 && data[3] == 0x46) {
            return data;
          }
        }
        return null;
      }
    } catch (e) {
      debugPrint('PDF download failed for $pdfUrl: $e');
    }
    return null;
  }

  static bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;
}

/// The First Flagship Plugin: DOI Scientific Harvester.
///
/// Implements [AlexandriaPlugin] to provide autonomous resolution, preservation,
/// and indexing of peer-reviewed scientific literature into Alexandria's indestructible safe harbor.
class DoiHarvesterPlugin implements AlexandriaPlugin {
  PluginContext? _context;
  bool _enabled = true;
  final DoiResolver _resolver;

  DoiHarvesterPlugin([DoiResolver? resolver])
      : _resolver = resolver ?? DoiResolver();

  @override
  PluginManifest get manifest => const PluginManifest(
        id: 'org.alexandria.plugin.doi-harvester',
        name: 'DOI Scientific Harvester',
        version: '1.0.0',
        author: 'Alexandria Preservation Working Group',
        description:
            'Authoritative resolution, metadata extraction, and archival preservation of peer-reviewed scientific literature into the decentralized library.',
        homepage: 'https://alexandria.pub/plugins/doi-harvester',
        entrypoint: 'doi_harvester_plugin.dart',
        permissions: [
          PluginPermission.networkFetch,
          PluginPermission.contentWrite,
          PluginPermission.storagePersist,
        ],
        hooks: [
          PluginHook.onStartup,
          PluginHook.onContentAdded,
        ],
        uiSlots: [
          UISlot.detailActions,
          UISlot.searchFilters,
          UISlot.settingsSection,
        ],
        maxMemoryMb: 128,
        timeoutMs: 30000,
      );

  @override
  bool get isEnabled => _enabled;

  @override
  set isEnabled(bool value) => _enabled = value;

  @override
  Future<void> initialize(PluginContext context) async {
    _context = context;
    debugPrint('DOI Scientific Harvester plugin initialized.');
  }

  @override
  List<PluginActionDefinition> get actions => const [
        PluginActionDefinition(
          id: 'resolve_doi',
          name: 'Resolve DOI Metadata',
          description: 'Fetch and parse scholarly metadata for a given DOI.',
          parameters: {'doi': 'string'},
        ),
        PluginActionDefinition(
          id: 'harvest_doi',
          name: 'Harvest & Ingest DOI',
          description: 'Resolve DOI, download open-access PDF (if available), and ingest into Alexandria.',
          parameters: {
            'doi': 'string',
            'downloadPdf': 'boolean',
          },
        ),
        PluginActionDefinition(
          id: 'harvest_batch',
          name: 'Batch Harvest DOIs',
          description: 'Extract and preserve multiple DOIs from text, list, or bibliography.',
          parameters: {
            'input': 'string or list of strings',
            'downloadPdf': 'boolean',
          },
        ),
        PluginActionDefinition(
          id: 'extract_dois',
          name: 'Extract DOIs From Text',
          description: 'Scan raw text and extract all unique, valid DOIs.',
          parameters: {'text': 'string'},
        ),
      ];

  @override
  Future<PluginActionResult> executeAction(
    String actionId,
    Map<String, dynamic> parameters,
  ) async {
    switch (actionId) {
      case 'extract_dois':
        final text = parameters['text']?.toString() ?? '';
        final dois = DoiResolver.extractDoisInText(text);
        return PluginActionResult.ok(
          'Extracted ${dois.length} DOI(s)',
          {'dois': dois, 'count': dois.length},
        );

      case 'resolve_doi':
        final rawDoi = parameters['doi']?.toString() ?? '';
        final record = await _resolver.resolve(rawDoi);
        if (record == null) {
          return PluginActionResult.error('Could not resolve DOI: $rawDoi');
        }
        return PluginActionResult.ok('Successfully resolved DOI', record.toMap());

      case 'harvest_doi':
        final rawDoi = parameters['doi']?.toString() ?? '';
        final downloadPdf = parameters['downloadPdf'] as bool? ?? true;
        final record = await _resolver.resolve(rawDoi);
        if (record == null) {
          return PluginActionResult.error('Resolution failed for DOI: $rawDoi');
        }

        final result = await ingestRecord(record, downloadPdf: downloadPdf);
        if (result['success'] == true) {
          return PluginActionResult.ok(
            'Ingested scientific document into Alexandria: ${record.title}',
            result,
          );
        } else {
          return PluginActionResult.error(
            'Ingestion failed: ${result['error']}',
            result,
          );
        }

      case 'harvest_batch':
        final rawInput = parameters['input'];
        final downloadPdf = parameters['downloadPdf'] as bool? ?? true;

        List<String> dois = [];
        if (rawInput is List) {
          dois = rawInput.map((e) => DoiResolver.normalizeDoi(e.toString())).where((e) => e.isNotEmpty).toList();
        } else if (rawInput is String) {
          dois = DoiResolver.extractDoisInText(rawInput);
        }

        // Bound batch work: each entry costs network resolution plus a
        // possible download — an unbounded list is a resource-exhaustion
        // vector (red minor-observation hardening).
        const maxBatchSize = 50;
        if (dois.length > maxBatchSize) {
          dois = dois.sublist(0, maxBatchSize);
        }

        if (dois.isEmpty) {
          return PluginActionResult.error('No valid DOIs found in input.');
        }

        final batchResults = <Map<String, dynamic>>[];
        var successCount = 0;

        for (final doi in dois) {
          try {
            final record = await _resolver.resolve(doi);
            if (record != null) {
              final res = await ingestRecord(record, downloadPdf: downloadPdf);
              if (res['success'] == true) successCount++;
              batchResults.add({'doi': doi, ...res});
            } else {
              batchResults.add({'doi': doi, 'success': false, 'error': 'Resolution failed'});
            }
          } catch (e) {
            batchResults.add({'doi': doi, 'success': false, 'error': e.toString()});
          }
        }

        return PluginActionResult.ok(
          'Batch processing complete: $successCount of ${dois.length} preserved.',
          {'results': batchResults, 'total': dois.length, 'successCount': successCount},
        );

      default:
        return PluginActionResult.error('Unknown action: $actionId');
    }
  }

  /// Ingests a resolved [DoiRecord] into Alexandria's repository, database, and IPFS node.
  Future<Map<String, dynamic>> ingestRecord(
    DoiRecord record, {
    bool downloadPdf = true,
  }) async {
    final context = _context;
    if (context == null || !context.hasReader) {
      return {'success': false, 'error': 'Plugin context not initialized with Riverpod reader.'};
    }

    try {
      final repository = context.read(contentRepositoryProvider);
      // (round-3 red finding) a denied capability resolves to an inert
      // object, not a ContentRepository — fail closed rather than
      // operating on a capability shell.
      if (repository is! ContentRepository) {
        return {
          'success': false,
          'error': 'Plugin lacks content repository permission.',
        };
      }

      Uint8List fileBytes;
      String format = 'md';
      bool capturedPdf = false;

      // Try downloading open-access PDF if available
      if (downloadPdf && record.pdfUrl != null && record.pdfUrl!.isNotEmpty) {
        final pdfBytes = await _resolver.downloadPdf(record.pdfUrl!);
        if (pdfBytes != null && pdfBytes.isNotEmpty) {
          fileBytes = pdfBytes;
          format = 'pdf';
          capturedPdf = true;
        } else {
          // Fallback to rich markdown dossier
          fileBytes = Uint8List.fromList(utf8.encode(record.toMarkdownDossier()));
          format = 'md';
        }
      } else {
        fileBytes = Uint8List.fromList(utf8.encode(record.toMarkdownDossier()));
        format = 'md';
      }

      final tags = <String>[
        'doi',
        'academic',
        'scientific-paper',
        if (record.journal.isNotEmpty) record.journal.toLowerCase(),
        ...record.subjects.map((s) => s.toLowerCase()),
      ];

      final uuid = await repository.createContent(
        title: record.title,
        author: record.formattedAuthors,
        description: record.abstractText ?? 'Archived scientific document from DOI ${record.doi}',
        fileData: fileBytes,
        category: 'academicAndScience',
        format: format,
        tags: tags.take(8).toList(),
        extraMetadata: {
          ...record.toMap(),
          'capturedPdf': capturedPdf,
          'ingestedAt': DateTime.now().toIso8601String(),
          'harvesterPlugin': manifest.id,
        },
      );

      final savedManifest = await repository.getManifestByUuid(uuid);

      return {
        'success': true,
        'uuid': uuid,
        'title': record.title,
        'doi': record.doi,
        'format': format,
        'capturedPdf': capturedPdf,
        'author': record.formattedAuthors,
        'manifestId': savedManifest?.id,
      };
    } catch (e, stack) {
      debugPrint('Error ingesting DOI record: $e\n$stack');
      return {'success': false, 'error': e.toString()};
    }
  }

  @override
  Future<void> onHook(PluginHook hook, dynamic payload) async {
    if (hook == PluginHook.onStartup) {
      debugPrint('DOI Harvester hook onStartup executed.');
    }
  }
}
