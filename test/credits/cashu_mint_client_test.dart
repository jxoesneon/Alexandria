import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alexandria/services/credits/cashu_mint_client.dart';
import 'package:alexandria/services/credits/crypto_bridge_service.dart';

void main() {
  group('CashuMintClient NUT-03 / NUT-05 REST Tests', () {
    test('fetches active keyset IDs from mint (NUT-03)', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/v1/keys')) {
          return http.Response(
            jsonEncode({
              'keysets': [
                {'id': '009a1f293252f331', 'unit': 'sat'},
                {'id': '00a12b3c4d5e6f7a', 'unit': 'usd'},
              ]
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final client = CashuMintClient(client: mockClient);
      final keysets = await client
          .fetchActiveKeysetIds('https://mint.minibits.cash/Bitcoin');

      expect(keysets.length, 2);
      expect(keysets.first, '009a1f293252f331');
    });

    test('requests melt quote for BOLT11 invoice (NUT-05)', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/v1/melt/quote/bolt11')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['request'], contains('lnbc'));
          return http.Response(
            jsonEncode({
              'quote': 'quote_melt_xyz_123',
              'amount': 250,
              'fee_reserve': 2,
              'paid': false,
              'expiry': 1735689600,
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final client = CashuMintClient(client: mockClient);
      final quote = await client.getMeltQuote(
        mintUrl: 'https://mint.minibits.cash/Bitcoin',
        bolt11: 'lnbc2500n1p...',
      );

      expect(quote.quoteId, 'quote_melt_xyz_123');
      expect(quote.amountSats, 250);
      expect(quote.feeReserveSats, 2);
      expect(quote.totalSatsRequired, 252);
    });

    test('melts proofs to settle Lightning invoice (NUT-05)', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/v1/melt/bolt11')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['quote'], 'quote_melt_xyz_123');
          expect((body['inputs'] as List).length, 1);

          return http.Response(
            jsonEncode({
              'paid': true,
              'payment_preimage':
                  '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final client = CashuMintClient(client: mockClient);
      final proof = const CashuProof(
        id: 'keyset_01',
        amount: 252,
        secret: 'sec_1',
        c: 'c_1',
      );

      final result = await client.meltProofs(
        mintUrl: 'https://mint.minibits.cash/Bitcoin',
        quoteId: 'quote_melt_xyz_123',
        proofs: [proof],
      );

      expect(result.paid, isTrue);
      expect(result.paymentPreimage, contains('0123456789abcdef'));
      expect(result.quoteId, 'quote_melt_xyz_123');
    });
  });
}
