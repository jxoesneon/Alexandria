import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/logic/content_repository.dart';
import 'package:alexandria/services/plugin_service.dart';

// --- Minimal dart:io HTTP fakes -------------------------------------------

class _FakeHeaders implements HttpHeaders {
  final Map<String, List<String>> _map = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _map[name.toLowerCase()] = ['$value'];
  }

  @override
  String? value(String name) => _map[name.toLowerCase()]?.first;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.statusCode, List<int> body,
      {Map<String, String>? responseHeaders})
      : _body = body {
    responseHeaders?.forEach(headers.set);
  }

  @override
  final int statusCode;

  final List<int> _body;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.fromIterable(<List<int>>[_body]).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this._response);

  final HttpClientResponse _response;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  bool followRedirects = true;

  @override
  Future<HttpClientResponse> close() async => _response;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._responder);

  final HttpClientResponse Function(Uri url) _responder;

  final List<Uri> requestedUrls = [];

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requestedUrls.add(url);
    return _FakeRequest(_responder(url));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

HttpClientResponse _jsonResponse(Map<String, dynamic> body,
        {int statusCode = 200}) =>
    _FakeResponse(statusCode, utf8.encode(jsonEncode(body)));

Map<String, dynamic> _crossrefMessage(String doi) => {
      'message': {
        'DOI': doi,
        'title': ['Resolved Work $doi'],
        'author': [
          {'given': 'Ada', 'family': 'Lovelace'},
        ],
        'container-title': ['Journal of Tests'],
        'issued': {
          'date-parts': [
            [2024, 3]
          ]
        },
        'publisher': 'Test Publisher',
      }
    };

void main() {
  group('DoiRecord parsing edge cases', () {
    test('fromCrossref falls back to publisher for journal and issued date',
        () {
      final record = DoiRecord.fromCrossref({
        'DOI': '10.5555/fallback',
        'title': ['Fallback Fields'],
        // No container-title → journal falls back to publisher.
        'publisher': 'Fallback Press',
        'issued': {
          'date-parts': [
            [2020, 11]
          ]
        },
      });
      expect(record.journal, 'Fallback Press');
      expect(record.year, 2020);
      expect(record.month, 11);
    });

    test('fromCrossref uses default journal and title when absent', () {
      final record = DoiRecord.fromCrossref({'DOI': '10.5555/min'});
      expect(record.title, 'Untitled Scientific Work');
      expect(record.journal, 'Scholarly Publication');
    });

    test('fromOpenAlex falls back to host_venue and biblio pages', () {
      final record = DoiRecord.fromOpenAlex({
        'doi': 'https://doi.org/10.5555/oa-fallback',
        'title': 'OA Fallback Work',
        // No primary_location → host_venue fallback for journal.
        'host_venue': {'display_name': 'Venue Journal'},
        'publication_year': 2019,
        'biblio': {'volume': '7', 'issue': '2', 'first_page': '100'},
        'cited_by_count': 5,
      });
      expect(record.journal, 'Venue Journal');
      expect(record.pages, '100-');
      expect(record.citationCount, 5);
      expect(record.isOpenAccess, isFalse);
    });

    test('fromOpenAlex uses default journal when no venue data exists', () {
      final record = DoiRecord.fromOpenAlex({'doi': 'x', 'title': 'T'});
      expect(record.journal, 'Scholarly Journal');
      expect(record.pages, isNull);
    });
  });

  group('DoiResolver with fake HTTP tiers', () {
    test('resolve returns null for an empty normalized DOI', () async {
      final client = _FakeHttpClient((_) => _jsonResponse({}));
      final resolver = DoiResolver(client);
      expect(await resolver.resolve(''), isNull);
      expect(await resolver.resolve('doi:  '), isNull);
      expect(client.requestedUrls, isEmpty);
    });

    test('resolve succeeds via Crossref when tier 1 returns 200', () async {
      final resolver = DoiResolver(
          _FakeHttpClient((_) => _jsonResponse(_crossrefMessage('10.1/ok'))));
      final record = await resolver.resolve('https://doi.org/10.1/ok');
      expect(record, isNotNull);
      expect(record!.doi, '10.1/ok');
      expect(record.title, 'Resolved Work 10.1/ok');
      expect(record.authors, ['Ada Lovelace']);
      expect(record.sourceApi, 'crossref');
    });

    test('resolve falls back to OpenAlex when Crossref fails', () async {
      final resolver = DoiResolver(_FakeHttpClient((url) {
        if (url.host == 'api.crossref.org') {
          return _FakeResponse(404, const []);
        }
        return _jsonResponse({
          'doi': 'https://doi.org/10.1/oa',
          'title': 'OpenAlex Work',
          'authorships': [
            {
              'author': {'display_name': 'Grace Hopper'}
            }
          ],
          'primary_location': {
            'source': {'display_name': 'OA Journal'}
          },
          'publication_year': 2021,
          'open_access': {'is_oa': true, 'oa_url': 'https://oa.example/x.pdf'},
        });
      }));
      final record = await resolver.resolve('10.1/oa');
      expect(record, isNotNull);
      expect(record!.sourceApi, 'openalex');
      expect(record.title, 'OpenAlex Work');
      expect(record.isOpenAccess, isTrue);
    });

    test('resolve falls back to DOI content negotiation as last resort',
        () async {
      final resolver = DoiResolver(_FakeHttpClient((url) {
        if (url.host == 'doi.org') {
          return _jsonResponse({
            'DOI': '10.1/csl',
            'title': ['CSL Work'],
          });
        }
        return _FakeResponse(500, const []);
      }));
      final record = await resolver.resolve('10.1/csl');
      expect(record, isNotNull);
      expect(record!.title, 'CSL Work');
    });

    test('resolve returns null when every tier fails', () async {
      final resolver =
          DoiResolver(_FakeHttpClient((_) => _FakeResponse(500, const [])));
      expect(await resolver.resolve('10.1/nowhere'), isNull);
    });

    test('resolve tolerates malformed JSON bodies', () async {
      final resolver = DoiResolver(
          _FakeHttpClient((_) => _FakeResponse(200, utf8.encode('{{{{'))));
      expect(await resolver.resolve('10.1/badjson'), isNull);
    });

    test('downloadPdf returns null for unparseable URLs', () async {
      final resolver =
          DoiResolver(_FakeHttpClient((_) => _FakeResponse(200, const [])));
      expect(await resolver.downloadPdf('%'), isNull);
    });

    test('downloadPdf fails closed when the SSRF gate rejects the URL',
        () async {
      final client =
          _FakeHttpClient((_) => _FakeResponse(200, utf8.encode('%PDF-x')));
      final resolver = DoiResolver(client);
      // Plain http fails the https-only gate before any connection.
      expect(await resolver.downloadPdf('http://example.com/a.pdf'), isNull);
      expect(client.requestedUrls, isEmpty);
    });
  });

  group('DoiHarvesterPlugin actions', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    /// Fake resolver whose response embeds the requested DOI so each
    /// batch entry ingests a distinct record (distinct CID).
    DoiHarvesterPlugin makePlugin() =>
        DoiHarvesterPlugin(DoiResolver(_FakeHttpClient((url) {
          final doi = url.pathSegments.length > 1
              ? url.pathSegments.sublist(1).join('/')
              : '10.5555/fake';
          return _jsonResponse(_crossrefMessage(doi));
        })));

    test('resolve_doi returns error when resolution fails', () async {
      final plugin = DoiHarvesterPlugin(
          DoiResolver(_FakeHttpClient((_) => _FakeResponse(503, const []))));
      final res =
          await plugin.executeAction('resolve_doi', {'doi': '10.1/miss'});
      expect(res.success, isFalse);
      expect(res.message, contains('Could not resolve DOI'));
    });

    test('resolve_doi returns the record map on success', () async {
      final plugin = makePlugin();
      final res =
          await plugin.executeAction('resolve_doi', {'doi': '10.9/fake'});
      expect(res.success, isTrue);
      expect((res.data as Map)['doi'], '10.9/fake');
    });

    test('harvest_doi reports resolution failure', () async {
      final plugin = DoiHarvesterPlugin(
          DoiResolver(_FakeHttpClient((_) => _FakeResponse(503, const []))));
      final res =
          await plugin.executeAction('harvest_doi', {'doi': '10.1/miss'});
      expect(res.success, isFalse);
      expect(res.message, contains('Resolution failed'));
    });

    test('harvest_doi ingests a markdown dossier on success', () async {
      final plugin = makePlugin();
      await plugin.initialize(PluginContext(
        container: container,
        pluginId: plugin.manifest.id,
        permissions: plugin.manifest.permissions.toSet(),
      ));

      final res = await plugin.executeAction('harvest_doi', {
        'doi': '10.9/fake',
        'downloadPdf': false,
      });
      expect(res.success, isTrue);
      final data = res.data as Map<String, dynamic>;
      expect(data['format'], 'md');
      expect(data['capturedPdf'], isFalse);
      expect(data['uuid'], isNotNull);

      final repository = container.read(contentRepositoryProvider);
      final manifest =
          await repository.getManifestByUuid(data['uuid'] as String);
      expect(manifest, isNotNull);
      expect(manifest!.tags, contains('doi'));
    });

    test('harvest_doi falls back to markdown when the PDF fetch fails',
        () async {
      final resolver = DoiResolver(_FakeHttpClient((url) {
        // Metadata tiers succeed; the gated PDF fetch will fail in the
        // SSRF gate before hitting this client anyway.
        return _jsonResponse({
          'message': {
            'DOI': '10.9/pdf',
            'title': ['PDF Work'],
            'link': [
              {
                'content-type': 'application/pdf',
                'URL': 'http://insecure.example/paper.pdf',
              }
            ],
          }
        });
      }));
      final plugin = DoiHarvesterPlugin(resolver);
      await plugin.initialize(PluginContext(
        container: container,
        pluginId: plugin.manifest.id,
        permissions: plugin.manifest.permissions.toSet(),
      ));

      final res = await plugin.executeAction('harvest_doi', {
        'doi': '10.9/pdf',
        'downloadPdf': true,
      });
      expect(res.success, isTrue);
      expect((res.data as Map)['capturedPdf'], isFalse);
      expect((res.data as Map)['format'], 'md');
    });

    test('ingestRecord fails closed without the contentWrite permission',
        () async {
      final plugin = makePlugin();
      await plugin.initialize(PluginContext(
        container: container,
        pluginId: plugin.manifest.id,
        permissions: const {}, // no permissions → capability denied
      ));
      final record = DoiRecord(
        doi: '10.9/denied',
        title: 'Denied',
        authors: const ['A'],
        journal: 'J',
      );
      final result = await plugin.ingestRecord(record, downloadPdf: false);
      expect(result['success'], isFalse);
      expect(result['error'], contains('content repository permission'));
    });

    test('harvest_batch processes a list input', () async {
      final plugin = makePlugin();
      await plugin.initialize(PluginContext(
        container: container,
        pluginId: plugin.manifest.id,
        permissions: plugin.manifest.permissions.toSet(),
      ));

      final res = await plugin.executeAction('harvest_batch', {
        'input': ['10.5555/alpha', 'doi:10.5555/beta'],
        'downloadPdf': false,
      });
      expect(res.success, isTrue);
      final data = res.data as Map<String, dynamic>;
      expect(data['total'], 2);
      expect(data['successCount'], 2);
    });

    test('harvest_batch extracts DOIs from raw text and reports failures',
        () async {
      // First DOI resolves; second gets a 500 across every tier.
      final plugin = DoiHarvesterPlugin(DoiResolver(_FakeHttpClient((url) {
        if (url.toString().contains('bad')) {
          return _FakeResponse(500, const []);
        }
        return _jsonResponse(_crossrefMessage('10.5555/good'));
      })));
      await plugin.initialize(PluginContext(
        container: container,
        pluginId: plugin.manifest.id,
        permissions: plugin.manifest.permissions.toSet(),
      ));

      final res = await plugin.executeAction('harvest_batch', {
        'input': 'See 10.5555/good and also 10.5555/bad for details.',
        'downloadPdf': false,
      });
      expect(res.success, isTrue);
      final data = res.data as Map<String, dynamic>;
      expect(data['total'], 2);
      expect(data['successCount'], 1);
      final results = data['results'] as List;
      expect(results.any((r) => r['error'] == 'Resolution failed'), isTrue);
    });

    test('harvest_batch caps input at 50 DOIs', () async {
      final plugin = makePlugin();
      // No context needed — ingest fails closed for every DOI, so the
      // loop records failures; the cap is observable via `total`.
      final dois = List.generate(60, (i) => '10.5555/cap$i');
      final res = await plugin.executeAction('harvest_batch', {
        'input': dois.join('\n'),
        'downloadPdf': false,
      });
      expect(res.success, isTrue);
      expect((res.data as Map)['total'], 50);
    });

    test('harvest_batch list input filters out unparseable entries', () async {
      final plugin = makePlugin();
      final res = await plugin.executeAction('harvest_batch', {
        'input': ['   ', ''],
      });
      // Entries normalize to '' → filtered → empty → error.
      expect(res.success, isFalse);
      expect(res.message, contains('No valid DOIs'));
    });
  });
}
