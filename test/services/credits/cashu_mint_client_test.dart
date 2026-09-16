import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alexandria/services/credits/cashu_mint_client.dart';
import 'package:alexandria/services/credits/crypto_bridge_service.dart';

void main() {
  group('CashuMeltQuote & CashuMeltResult models', () {
    test('CashuMeltQuote serialization and calculations', () {
      const quote = CashuMeltQuote(
        quoteId: 'quote-123',
        amountSats: 500,
        feeReserveSats: 5,
        paid: false,
        expiry: 1700000000,
      );

      expect(quote.totalSatsRequired, 505);
      final json = quote.toJson();
      expect(json['quote'], 'quote-123');
      expect(json['amount'], 500);
      expect(json['fee_reserve'], 5);
      expect(json['paid'], isFalse);
      expect(json['expiry'], 1700000000);

      final fromJson = CashuMeltQuote.fromJson(json);
      expect(fromJson.quoteId, 'quote-123');
      expect(fromJson.amountSats, 500);
      expect(fromJson.feeReserveSats, 5);
      expect(fromJson.paid, isFalse);
      expect(fromJson.expiry, 1700000000);
    });

    test('CashuMeltResult serialization', () {
      const result = CashuMeltResult(
        paid: true,
        paymentPreimage: 'preimage-abc',
        quoteId: 'quote-456',
      );

      final json = result.toJson();
      expect(json['paid'], isTrue);
      expect(json['payment_preimage'], 'preimage-abc');
      expect(json['quote'], 'quote-456');

      const unpaidResult = CashuMeltResult(
        paid: false,
        quoteId: 'quote-789',
      );
      expect(unpaidResult.toJson().containsKey('payment_preimage'), isFalse);
    });
  });

  group('CashuMintClient', () {
    test('fetchActiveKeysetIds succeeds and parses keysets', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/v1/keys');
        return http.Response(
          jsonEncode({
            'keysets': [
              {'id': '009a1f293252e140'},
              {'id': '009a1f293252e141'},
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final mintClient = CashuMintClient(client: mockClient);
      final keysets =
          await mintClient.fetchActiveKeysetIds('https://mint.example.com/');
      expect(keysets, ['009a1f293252e140', '009a1f293252e141']);
      mintClient.close();
    });

    test('fetchActiveKeysetIds throws on error status', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      final mintClient = CashuMintClient(client: mockClient);
      expect(
        () => mintClient.fetchActiveKeysetIds('https://mint.example.com'),
        throwsA(isA<StateError>()),
      );
      mintClient.close();
    });

    test('getMeltQuote succeeds', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/v1/melt/quote/bolt11');
        final body = jsonDecode(request.body);
        expect(body['request'], 'lnbc100u1p...');
        expect(body['unit'], 'sat');

        return http.Response(
          jsonEncode({
            'quote': 'quote-xyz',
            'amount': 100,
            'fee_reserve': 2,
            'paid': false,
            'expiry': 1700003600,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final mintClient = CashuMintClient(client: mockClient);
      final quote = await mintClient.getMeltQuote(
        mintUrl: 'https://mint.example.com',
        bolt11: 'lnbc100u1p...',
      );
      expect(quote.quoteId, 'quote-xyz');
      expect(quote.amountSats, 100);
      expect(quote.feeReserveSats, 2);
      expect(quote.totalSatsRequired, 102);
      mintClient.close();
    });

    test('getMeltQuote throws on error status', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Bad Request', 400);
      });

      final mintClient = CashuMintClient(client: mockClient);
      expect(
        () => mintClient.getMeltQuote(
          mintUrl: 'https://mint.example.com',
          bolt11: 'invalid-bolt11',
        ),
        throwsA(isA<StateError>()),
      );
      mintClient.close();
    });

    test('meltProofs succeeds and returns result', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/v1/melt/bolt11');
        final body = jsonDecode(request.body);
        expect(body['quote'], 'quote-xyz');
        expect(body['inputs'], isNotEmpty);

        return http.Response(
          jsonEncode({
            'paid': true,
            'payment_preimage': '000102030405060708090a0b0c0d0e0f',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final mintClient = CashuMintClient(client: mockClient);
      const proof = CashuProof(
        id: '009a1f293252e140',
        amount: 64,
        secret: 'sec-123',
        c: '02abc...',
      );

      final result = await mintClient.meltProofs(
        mintUrl: 'https://mint.example.com',
        quoteId: 'quote-xyz',
        proofs: [proof],
      );

      expect(result.paid, isTrue);
      expect(result.paymentPreimage, '000102030405060708090a0b0c0d0e0f');
      expect(result.quoteId, 'quote-xyz');
      mintClient.close();
    });

    test('meltProofs throws on failure status', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal error', 500);
      });

      final mintClient = CashuMintClient(client: mockClient);
      expect(
        () => mintClient.meltProofs(
          mintUrl: 'https://mint.example.com',
          quoteId: 'quote-xyz',
          proofs: [],
        ),
        throwsA(isA<StateError>()),
      );
      mintClient.close();
    });
  });
}
