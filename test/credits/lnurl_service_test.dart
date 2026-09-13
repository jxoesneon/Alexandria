import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alexandria/services/credits/lnurl_service.dart';

void main() {
  group('LnurlService LUD-16 & LUD-06 Tests', () {
    test('resolves Lightning Address into real BOLT11 invoice', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/.well-known/lnurlp/alice') {
          return http.Response(
            jsonEncode({
              'tag': 'payRequest',
              'callback': 'https://stacker.news/api/lnurlp/callback/alice',
              'minSendable': 1000,      // 1 sat
              'maxSendable': 100000000, // 100,000 sats
              'metadata': '[["text/plain", "Pay to Alice"]]',
            }),
            200,
          );
        } else if (request.url.path == '/api/lnurlp/callback/alice') {
          expect(request.url.queryParameters['amount'], '250000'); // 250 sats in msats
          return http.Response(
            jsonEncode({
              'pr': 'lnbc2500n1p3xxxx...',
              'routes': [],
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final lnurlService = LnurlService(client: mockClient);
      final invoice = await lnurlService.resolveAddressToInvoice(
        lightningAddress: 'alice@stacker.news',
        amountSats: 250,
      );

      expect(invoice.pr, 'lnbc2500n1p3xxxx...');
      expect(invoice.amountSats, 250);
      expect(invoice.recipientAddress, 'alice@stacker.news');
    });

    test('rejects amount below minSendable or above maxSendable', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'tag': 'payRequest',
            'callback': 'https://domain.com/callback',
            'minSendable': 10000, // 10 sats
            'maxSendable': 50000, // 50 sats
          }),
          200,
        );
      });

      final service = LnurlService(client: mockClient);

      // 5 sats is below 10 sats minSendable
      expect(
        () => service.resolveAddressToInvoice(
          lightningAddress: 'user@domain.com',
          amountSats: 5,
        ),
        throwsA(isA<RangeError>()),
      );

      // 100 sats is above 50 sats maxSendable
      expect(
        () => service.resolveAddressToInvoice(
          lightningAddress: 'user@domain.com',
          amountSats: 100,
        ),
        throwsA(isA<RangeError>()),
      );
    });

    test('rejects malformed Lightning Address format', () {
      final service = LnurlService();
      expect(
        () => service.resolveAddressToInvoice(
          lightningAddress: 'not_an_email',
          amountSats: 10,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
