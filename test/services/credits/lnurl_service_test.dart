import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alexandria/services/credits/lnurl_service.dart';

void main() {
  group('LnurlPayInvoice model', () {
    test('serialization and fields', () {
      const invoice = LnurlPayInvoice(
        pr: 'lnbc100u1p...',
        amountSats: 100,
        recipientAddress: 'alice@example.com',
        paymentHash: 'hash-abc',
      );

      final json = invoice.toJson();
      expect(json['pr'], 'lnbc100u1p...');
      expect(json['amount_sats'], 100);
      expect(json['recipient_address'], 'alice@example.com');
      expect(json['payment_hash'], 'hash-abc');
    });
  });

  group('LnurlService', () {
    test('validates address format', () async {
      final service = LnurlService();
      expect(
        () => service.resolveAddressToInvoice(
          lightningAddress: 'invalid-address',
          amountSats: 100,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('successful LUD-16 flow with lnbc prefix', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/.well-known/lnurlp/alice')) {
          return http.Response(
            jsonEncode({
              'tag': 'payRequest',
              'callback': 'https://example.com/lnurlp/alice/callback',
              'minSendable': 1000,
              'maxSendable': 10000000,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.url.path.contains('/callback')) {
          expect(request.url.queryParameters['amount'], '100000');
          return http.Response(
            jsonEncode({
              'pr': 'lnbc100u1p9xxxxxxxxxxxxxxxx',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = LnurlService(client: mockClient, callbackTransport: mockClient.get);
      final invoice = await service.resolveAddressToInvoice(
        lightningAddress: 'alice@example.com',
        amountSats: 100,
      );

      expect(invoice.pr, 'lnbc100u1p9xxxxxxxxxxxxxxxx');
      expect(invoice.amountSats, 100);
      expect(invoice.recipientAddress, 'alice@example.com');
      service.close();
    });

    test('handles testnet lntb prefix', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/.well-known/lnurlp/bob')) {
          return http.Response(
            jsonEncode({
              'tag': 'payRequest',
              'callback': 'https://testnet.example.com/callback',
              'minSendable': 1000,
              'maxSendable': 10000000,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else if (request.url.path.contains('/callback')) {
          return http.Response(
            jsonEncode({
              'pr': 'lntb50u1p9yyyyyyyyyyyyyyyy',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = LnurlService(client: mockClient, callbackTransport: mockClient.get);
      final invoice = await service.resolveAddressToInvoice(
        lightningAddress: 'bob@testnet.example.com',
        amountSats: 50,
      );

      expect(invoice.pr, 'lntb50u1p9yyyyyyyyyyyyyyyy');
      service.close();
    });

    test('throws when .well-known endpoint returns error status', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Error', 500);
      });

      final service = LnurlService(client: mockClient, callbackTransport: mockClient.get);
      expect(
        () => service.resolveAddressToInvoice(
          lightningAddress: 'alice@example.com',
          amountSats: 100,
        ),
        throwsA(isA<StateError>()),
      );
      service.close();
    });

    test('throws when tag is not payRequest', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'tag': 'withdrawRequest',
            'callback': 'https://example.com/cb',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = LnurlService(client: mockClient, callbackTransport: mockClient.get);
      expect(
        () => service.resolveAddressToInvoice(
          lightningAddress: 'alice@example.com',
          amountSats: 100,
        ),
        throwsA(isA<StateError>()),
      );
      service.close();
    });

    test('throws when callback URL is missing', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'tag': 'payRequest',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = LnurlService(client: mockClient, callbackTransport: mockClient.get);
      expect(
        () => service.resolveAddressToInvoice(
          lightningAddress: 'alice@example.com',
          amountSats: 100,
        ),
        throwsA(isA<StateError>()),
      );
      service.close();
    });

    test('throws when amount is out of min/max bounds', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'tag': 'payRequest',
            'callback': 'https://example.com/cb',
            'minSendable': 10000, // 10 sats
            'maxSendable': 50000, // 50 sats
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = LnurlService(client: mockClient, callbackTransport: mockClient.get);
      // Below min (5 sats = 5000 msats)
      expect(
        () => service.resolveAddressToInvoice(
          lightningAddress: 'alice@example.com',
          amountSats: 5,
        ),
        throwsA(isA<RangeError>()),
      );

      // Above max (100 sats = 100000 msats)
      expect(
        () => service.resolveAddressToInvoice(
          lightningAddress: 'alice@example.com',
          amountSats: 100,
        ),
        throwsA(isA<RangeError>()),
      );
      service.close();
    });

    test('throws when callback response fails or returns invalid invoice', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('lnurlp')) {
          return http.Response(
            jsonEncode({
              'tag': 'payRequest',
              'callback': 'https://example.com/cb',
              'minSendable': 1000,
              'maxSendable': 1000000,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        } else {
          return http.Response(
            jsonEncode({
              'pr': 'not_a_valid_invoice',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
      });

      final service = LnurlService(client: mockClient, callbackTransport: mockClient.get);
      expect(
        () => service.resolveAddressToInvoice(
          lightningAddress: 'alice@example.com',
          amountSats: 10,
        ),
        throwsA(isA<StateError>()),
      );
      service.close();
    });
  });
}
