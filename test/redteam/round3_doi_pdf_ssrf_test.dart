// RED TEAM PoC — DoiResolver.downloadPdf fetches the `pdfUrl` carried
// in upstream Crossref/OpenAlex metadata with NO scheme or host
// validation (lib/services/plugins/doi_harvester_plugin.dart:419-451).
// The only guards are a 64 MiB size cap and a %PDF magic check.
//
// `link[].URL` / `pdf_url` are publisher-deposited fields — a hostile
// registrant (anyone can register a DOI through a predatory publisher,
// and OpenAlex/Crossref do not vet URLs) can point the download at:
//   * http://169.254.169.254/…   cloud metadata (returns non-PDF →
//     discarded, but the REQUEST still fires — blind SSRF probe),
//   * http://127.0.0.1:<port>/…  loopback services on the user's device,
//   * http://192.168.x.x/…       LAN-internal admin panels,
//   * anything serving bytes starting with "%PDF" → ingested into the
//     library as attacker-chosen "content".
//
// flutter_test replaces the ambient HttpClient, so instead of a live
// server we inject a SPY HttpClient that records every getUrl() —
// proving the connection attempt itself is issued for private-space
// URLs. (With the production client the request goes on the wire;
// the injected seam is the same one the code uses.)
//
// Asserts the SECURE expectation: a resolver fetching
// attacker-influenced URLs must refuse non-public hosts (same SSRF
// class as the LNURL gate) — at minimum loopback/RFC-1918/link-local —
// BEFORE issuing the request.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/plugins/doi_harvester_plugin.dart';

/// Records every URL the resolver attempts to open, then aborts the
/// request (the connection attempt is the proof — no bytes needed).
class _SpyHttpClient implements HttpClient {
  final attempted = <Uri>[];

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    attempted.add(url);
    return Future<HttpClientRequest>.error(StateError('spy-abort'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter) return null; // tolerate property sets
    throw UnimplementedError('${invocation.memberName}');
  }
}

void main() {
  final spy = _SpyHttpClient();
  final resolver = DoiResolver(spy);

  for (final url in <String>[
    'http://127.0.0.1:8080/internal/payroll.pdf', // loopback
    'http://169.254.169.254/latest/meta-data/x', // cloud metadata
    'http://192.168.1.1/admin/config.pdf', // LAN admin panel
    'http://10.0.0.4/private/report.pdf', // RFC-1918
  ]) {
    test('downloadPdf must refuse private-space target $url', () async {
      spy.attempted.clear();
      final bytes = await resolver.downloadPdf(url);
      expect(spy.attempted, isEmpty,
          reason: 'downloadPdf opened a connection to $url — pdfUrl is '
              'publisher-controlled upstream metadata, so this is a live '
              'SSRF primitive (blind at minimum; internal bodies '
              'beginning with %PDF are ingested as library content).');
      expect(bytes, isNull);
    });
  }
}
