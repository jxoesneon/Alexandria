// RED TEAM PoC - LnurlService fetches the LNURL `callback` URL with
// zero validation → server-side request forgery (SSRF).
//
// lib/services/credits/lnurl_service.dart: the callback comes from the
// .well-known/lnurlp JSON of a user-supplied lightning domain. It is
// passed verbatim to _client.get - no scheme check, no host check, no
// private-range filter. A hostile LNURL endpoint (phished lightning
// address, compromised resolver, or simply user@evil-domain the victim
// is induced to "pay") can point the callback at:
//   * http://169.254.169.254/... cloud metadata endpoints,
//   * http://192.168.x.x / RFC-1918 LAN hosts (router admin, internal
//     services),
//   * cleartext http:// downgrades.
// Alexandria then issues the request FROM the victim's device/network.
//
// Asserts the SECURE expectation: the callback must be https on a
// public host (or at minimum refuse private/link-local/cleartext
// targets). Failure marks a live SSRF primitive.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' show MockClient;
import 'package:alexandria/services/credits/lnurl_service.dart';

void main() {
  final captured = <Uri>[];

  MockClient maliciousServer() {
    return MockClient((request) async {
      captured.add(request.url);
      if (request.url.path.contains('.well-known/lnurlp')) {
        return http.Response(
          jsonEncode({
            'tag': 'payRequest',
            'minSendable': 1000,
            'maxSendable': 100000000,
            // The attack: callback aimed at the link-local cloud
            // metadata service over cleartext HTTP.
            'callback': 'http://169.254.169.254/latest/meta-data/iam',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      // Callback "response": anything that fails invoice parsing -
      // the request was already issued, which is the vulnerability.
      return http.Response(jsonEncode({'pr': 'lnbc1fake'}), 200,
          headers: {'content-type': 'application/json'});
    });
  }

  test('LNURL callback aimed at a private/link-local host must be refused',
      () async {
    captured.clear();
    final svc = LnurlService(client: maliciousServer());

    Object? thrown;
    try {
      await svc.resolveAddressToInvoice(
          lightningAddress: 'victim@example.com', amountSats: 1000);
    } catch (e) {
      thrown = e; // invoice parse failure is fine - we watch the wire
    }

    final hitMetadata =
        captured.any((u) => u.host == '169.254.169.254' || u.scheme == 'http');
    expect(hitMetadata, isFalse,
        reason: 'the LNURL callback was fetched verbatim: the service issued '
            'a request to ${captured.join(", ")} — a cleartext/link-local '
            'SSRF straight from the victim device. '
            '(thrown=$thrown)');
  });

  test('non-https callback scheme must be refused outright', () async {
    captured.clear();
    final svc = LnurlService(client: MockClient((request) async {
      captured.add(request.url);
      if (request.url.path.contains('.well-known/lnurlp')) {
        return http.Response(
          jsonEncode({
            'tag': 'payRequest',
            'callback': 'http://192.168.1.1/admin/backup.cfg',
          }),
          200,
        );
      }
      return http.Response('{"pr":"lnbc1x"}', 200);
    }));

    try {
      await svc.resolveAddressToInvoice(
          lightningAddress: 'victim@example.com', amountSats: 1000);
    } catch (_) {}

    final hitLan = captured.any((u) => u.host.startsWith('192.168.'));
    expect(hitLan, isFalse,
        reason: 'callback targeted an RFC-1918 LAN host and was fetched — '
            'internal-network SSRF: ${captured.join(", ")}');
  });
}
