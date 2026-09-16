// RED TEAM PoC - Round-3 follow-up on the round-2 LNURL SSRF gate.
//
// lib/services/credits/lnurl_service.dart `_requireSafeCallbackUri`
// only recognises a host as a literal IPv4 when it is EXACTLY four
// dot-separated decimal octets (`_parseLiteralIpv4`). Every other
// numeric spelling sails through as a "hostname" - but the OS resolver
// (getaddrinfo/inet_aton on POSIX, InetAddress on Windows) still parses
// them as IPv4 addresses:
//
//   '127.1'        -> 127.0.0.1   (short form: last part fills 24 bits)
//   '0177.0.0.1'   -> 127.0.0.1   (leading zero = OCTAL to inet_aton;
//                                int.tryParse reads it as DECIMAL 177,
//                                so the gate checks the WRONG address)
//   '0x7f.0.0.1'   -> 127.0.0.1   (hex octets - int.tryParse fails →
//                                classified as hostname → OS parses hex)
//   '2130706433'   -> 127.0.0.1   (single 32-bit decimal)
//   'localhost.'   -> 127.0.0.1   (trailing-dot FQDN: `host == 'localhost'`
//                                and `endsWith('.localhost')` both miss)
//
// Second bypass, independent of spelling: the SSRF check runs ONCE on
// the attacker-supplied callback URL - but package:http over dart:io
// follows redirects by default (HttpClientRequest.followRedirects
// defaults true, maxRedirects 5). A callback on a PUBLIC https host
// answering 302 -> http://169.254.169.254/… is fetched with no
// re-validation: scheme AND host gate both bypassed.
//
// Asserts the SECURE expectation: no request may be issued to a host
// that resolves into loopback/private/link-local space under ANY
// inet_aton spelling, and a redirect target must be re-validated
// (or redirects must not be followed for the callback leg).
import 'dart:convert';
import 'dart:io' show HttpStatus;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' show MockClient;
import 'package:alexandria/services/credits/lnurl_service.dart';

/// Records every URL the service issues a request to.
class _Sniffer {
  final captured = <Uri>[];
  void reset() => captured.clear();

  /// .well-known answers an attacker-controlled callback; the callback
  /// leg answers an (invalid) invoice - we only watch the wire.
  MockClient clientReturning(String callback) {
    return MockClient((request) async {
      captured.add(request.url);
      if (request.url.path.contains('.well-known/lnurlp')) {
        return http.Response(
          jsonEncode({
            'tag': 'payRequest',
            'minSendable': 1000,
            'maxSendable': 100000000,
            'callback': callback,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(jsonEncode({'pr': 'lnbc1x'}), 200,
          headers: {'content-type': 'application/json'});
    });
  }
}

/// A BaseClient that follows redirects the way dart:io's HttpClient
/// does by default (HttpClientRequest.followRedirects == true,
/// maxRedirects 5) - faithfully emulating the production client the
/// service builds when none is injected.
class _RedirectFollowingClient extends http.BaseClient {
  final _Sniffer sniffer;
  _RedirectFollowingClient(this.sniffer);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var current = request;
    for (var i = 0; i < 5; i++) {
      sniffer.captured.add(current.url); // capture every leg, incl. redirects
      http.StreamedResponse res;
      if (current.url.path.contains('.well-known/lnurlp')) {
        res = http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({
              'tag': 'payRequest',
              'minSendable': 1000,
              'maxSendable': 100000000,
              // Public https host - passes the SSRF gate cleanly.
              'callback': 'https://callback.example.com/lnurlp/cb',
            }))),
            200);
      } else if (current.url.host == 'callback.example.com') {
        // The public host redirects into the link-local metadata
        // service over cleartext HTTP.
        res = http.StreamedResponse(const Stream.empty(), HttpStatus.found,
            headers: {
              'location': 'http://169.254.169.254/latest/meta-data/iam'
            },
            isRedirect: true);
      } else {
        res = http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({'pr': 'lnbc1x'}))), 200);
      }
      if (res.isRedirect && res.headers['location'] != null) {
        final loc = Uri.parse(res.headers['location']!);
        final next = http.Request('GET', current.url.resolveUri(loc));
        current = next;
        continue;
      }
      return res;
    }
    return http.StreamedResponse(const Stream.empty(), 508);
  }
}

void main() {
  final sniffer = _Sniffer();

  group('non-canonical IPv4 spellings (inet_aton forms)', () {
    for (final host in <String>[
      '127.1', // short form → 127.0.0.1
      '0177.0.0.1', // octal octet → 127.0.0.1 (gate parses decimal 177!)
      '0x7f.0.0.1', // hex octet → 127.0.0.1
      '2130706433', // single decimal → 127.0.0.1
      'localhost.', // trailing-dot FQDN → loopback
    ]) {
      test('callback host "$host" must be refused before fetch', () async {
        sniffer.reset();
        final svc =
            LnurlService(client: sniffer.clientReturning('https://$host/cb'));
        Object? thrown;
        try {
          await svc.resolveAddressToInvoice(
              lightningAddress: 'victim@example.com', amountSats: 1000);
        } catch (e) {
          thrown = e;
        }
        final hitHost =
            sniffer.captured.any((u) => u.host.toLowerCase() == host);
        expect(hitHost, isFalse,
            reason: 'the callback request was issued to "$host" — the SSRF '
                'gate only recognises dotted-decimal quads, but the OS '
                'resolver maps this spelling to a private/loopback '
                'address. Wire trace: ${sniffer.captured}. '
                '(thrown=$thrown)');
      });
    }
  });

  test(
      'callback redirect target is never re-validated (302 → private '
      'host)', () async {
    sniffer.reset();
    final svc = LnurlService(client: _RedirectFollowingClient(sniffer));
    Object? thrown;
    try {
      await svc.resolveAddressToInvoice(
          lightningAddress: 'victim@example.com', amountSats: 1000);
    } catch (e) {
      thrown = e;
    }

    final hitMetadata = sniffer.captured
        .any((u) => u.host == '169.254.169.254' || u.scheme == 'http');
    expect(hitMetadata, isFalse,
        reason: 'the production client follows redirects (dart:io default), '
            'so a gate-clean https callback can 302 the fetch into '
            'cleartext link-local space with zero re-validation. Wire '
            'trace: ${sniffer.captured}. (thrown=$thrown)');
  });
}
