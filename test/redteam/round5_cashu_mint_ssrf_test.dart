// RED TEAM PoC — Round-5: every remote-metadata fetch in the codebase
// was brought under UrlSafety.requirePublicFetchUri (LNURL .well-known
// and callback legs, DOI harvester PDF downloads) EXCEPT
// CashuMintClient, which still fetches a caller-supplied `mintUrl`
// with a plain http.Client — no scheme restriction (http:// is fine),
// no inet_aton/IPv6 literal parsing, no DNS-answer check, and default
// redirect following:
//
//   lib/services/credits/cashu_mint_client.dart:68-75
//     final uri = Uri.parse('$cleanUrl/v1/keys');
//     final res = await _client.get(uri, ...);   // no gate, redirects on
//
// The melt path POSTs bearer Cashu proofs to that URL — a mint URL
// influenced by remote/untrusted configuration, or a 302 from a public
// mint into 169.254.169.254, is SSRF plus cleartext token exfiltration.
// The live sweep caller sits behind the payouts kill switch today, but
// the client is a live class invoked by name; the egress code it serves
// lights up without any change here.
//
// Asserts the SECURE expectation: a private-space or non-https mint URL
// is refused before a single request leaves the client.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alexandria/services/credits/cashu_mint_client.dart';

void main() {
  test(
      'CashuMintClient must refuse private/non-https mint URLs '
      '(no request may leave)', () async {
    var requestCount = 0;
    final mock = MockClient((request) async {
      requestCount++;
      return http.Response('{"keysets": []}', 200);
    });
    final client = CashuMintClient(client: mock);

    for (final mintUrl in [
      'http://169.254.169.254', // cloud metadata endpoint
      'http://10.0.0.1', // RFC-1918
      'http://127.0.0.1:8332', // loopback
      'http://[::1]', // v6 loopback
      'http://localhost', // local name
      'https://0x7f.0.0.1', // inet_aton spelling of loopback
    ]) {
      await expectLater(
        client.fetchActiveKeysetIds(mintUrl),
        throwsA(anything),
        reason: 'mint URL "$mintUrl" must be refused by an SSRF gate before '
            'any request is issued — CashuMintClient is the only remote '
            'fetch surface with no UrlSafety.requirePublicFetchUri.',
      );
    }
    expect(requestCount, 0,
        reason: 'a refused mint URL must never reach the transport — '
            '$requestCount request(s) were issued anyway.');
  });
}
