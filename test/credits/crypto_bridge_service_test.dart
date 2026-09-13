import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:alexandria/services/credits/cashu_mint_client.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/crypto_bridge_service.dart';
import 'package:alexandria/services/credits/lnurl_service.dart';
import 'package:alexandria/services/credits/poch_service.dart';

void main() {
  group('CryptoBridgeService Edge Rails Tests (ALX-005)', () {
    late PoCHService pochService;
    late CreditService creditService;
    late CryptoBridgeService bridgeService;

    setUp(() {
      pochService = PoCHService();
      creditService = CreditService(
        pochService: pochService,
        initialBalance: 100.0,
      );
      bridgeService = CryptoBridgeService(creditService: creditService);
    });

    test('initializes with default mint and empty lightning address', () {
      expect(bridgeService.preferredCashuMint, contains('mint.minibits.cash'));
      expect(bridgeService.lightningAddress, isEmpty);
      expect(bridgeService.exportedTokensHistory, isEmpty);
    });

    test('validates Lightning Address formats correctly', () {
      expect(CryptoBridgeService.isValidLightningAddress('satoshi@stacker.news'), isTrue);
      expect(CryptoBridgeService.isValidLightningAddress('alexandria@getalby.com'), isTrue);
      expect(CryptoBridgeService.isValidLightningAddress('invalid-address'), isFalse);
      expect(CryptoBridgeService.isValidLightningAddress('missing_domain@'), isFalse);
      expect(CryptoBridgeService.isValidLightningAddress('@nodomain.com'), isFalse);
    });

    test('updates Lightning Address and Mint configurations', () {
      bridgeService.setLightningAddress('curator@fountain.fm');
      expect(bridgeService.lightningAddress, 'curator@fountain.fm');

      bridgeService.setCashuMint('https://legend.lnbits.com/cashu/api/v1/4gr9Xcm93Q9kzUkNuqtHzQ');
      expect(bridgeService.preferredCashuMint, contains('legend.lnbits.com'));
    });

    test('exports credits to Cashu E-Cash token with power-of-two proof decomposition', () {
      final initialBalance = creditService.balance; // 100.0
      // 10 credits = 100 sats
      final token = bridgeService.exportCreditsAsCashuToken(10.0);

      expect(token, isNotNull);
      expect(token!.totalAmountSats, 100);
      expect(creditService.balance, initialBalance - 10.0);

      // Verify power-of-two decomposition of 100 (64 + 32 + 4)
      final amounts = token.proofs.map((p) => p.amount).toList()..sort();
      expect(amounts, [4, 32, 64]);

      // Verify serialized format
      final serialized = token.serialize();
      expect(serialized.startsWith('cashuA'), isTrue);
      expect(bridgeService.exportedTokensHistory.length, 1);
      expect(bridgeService.exportedTokensHistory.first, serialized);
    });

    test('rejects Cashu export when balance is insufficient or invalid', () {
      final tokenExcess = bridgeService.exportCreditsAsCashuToken(500.0);
      expect(tokenExcess, isNull);

      final tokenZero = bridgeService.exportCreditsAsCashuToken(0.0);
      expect(tokenZero, isNull);

      final tokenNegative = bridgeService.exportCreditsAsCashuToken(-5.0);
      expect(tokenNegative, isNull);
    });

    test('redeems Cashu E-Cash token voucher and prevents double-spending', () {
      final initialBalance = creditService.balance;

      // 1. Export 20 credits (200 sats)
      final token = bridgeService.exportCreditsAsCashuToken(20.0);
      expect(token, isNotNull);
      expect(creditService.balance, initialBalance - 20.0);

      final serialized = token!.serialize();

      // 2. Deserialization verification
      final deserialized = CashuToken.deserialize(serialized);
      expect(deserialized, isNotNull);
      expect(deserialized!.totalAmountSats, 200);

      // 3. Redeem the token
      final redeemedCredits = bridgeService.redeemCashuToken(serialized);
      expect(redeemedCredits, 20.0);
      expect(creditService.balance, initialBalance);

      // 4. Attempt double-spend of the same token voucher
      final doubleSpendCredits = bridgeService.redeemCashuToken(serialized);
      expect(doubleSpendCredits, 0.0);
      expect(creditService.balance, initialBalance);
    });

    test('handles malformed Cashu token strings gracefully', () {
      expect(bridgeService.redeemCashuToken('invalid_token_string'), 0.0);
      expect(bridgeService.redeemCashuToken('cashuA_not_valid_base64!'), 0.0);
      expect(CashuToken.deserialize('cashuA'), isNull);
    });

    test('executes Lightning payout sweeps and validates debit accounting', () {
      bridgeService.setLightningAddress('preservationist@getalby.com');
      final initialBalance = creditService.balance; // 100.0

      // Sweep 15 credits (150 sats)
      final success = bridgeService.sweepToLightningAddress(creditsToSweep: 15.0);
      expect(success, isTrue);
      expect(creditService.balance, initialBalance - 15.0);

      // Verify custom recipient override
      final customSuccess = bridgeService.sweepToLightningAddress(
        creditsToSweep: 10.0,
        customAddress: 'archive_node@blink.sv',
      );
      expect(customSuccess, isTrue);
      expect(creditService.balance, initialBalance - 25.0);

      // Reject invalid lightning address
      final failedAddress = bridgeService.sweepToLightningAddress(
        creditsToSweep: 5.0,
        customAddress: 'not-an-email-or-lightning-address',
      );
      expect(failedAddress, isFalse);

      // Reject sweep exceeding balance
      final excessSweep = bridgeService.sweepToLightningAddress(creditsToSweep: 1000.0);
      expect(excessSweep, isFalse);
    });

    test('executes live Lightning sweep via mock LNURL and Cashu melt quote', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/.well-known/lnurlp/bob') {
          return http.Response(
            jsonEncode({
              'tag': 'payRequest',
              'callback': 'https://getalby.com/lnurlp/callback/bob',
              'minSendable': 1000,
              'maxSendable': 100000000,
            }),
            200,
          );
        } else if (request.url.path == '/lnurlp/callback/bob') {
          return http.Response(
            jsonEncode({
              'pr': 'lnbc2500n1p_live_test_invoice',
              'routes': [],
            }),
            200,
          );
        } else if (request.url.path.endsWith('/v1/melt/quote/bolt11')) {
          return http.Response(
            jsonEncode({
              'quote': 'melt_quote_live_99',
              'amount': 250,
              'fee_reserve': 2,
              'paid': false,
              'expiry': 1735689600,
            }),
            200,
          );
        } else if (request.url.path.endsWith('/v1/melt/bolt11')) {
          return http.Response(
            jsonEncode({
              'paid': true,
              'payment_preimage': 'preimage_live_settled_123',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final lnurlService = LnurlService(client: mockClient);
      final mintClient = CashuMintClient(client: mockClient);

      final liveBridge = CryptoBridgeService(
        creditService: creditService,
        lnurlService: lnurlService,
        mintClient: mintClient,
      );

      final initialBalance = creditService.balance; // 100.0

      final result = await liveBridge.sweepToLightningAddressLive(
        creditsToSweep: 25.0,
        customAddress: 'bob@getalby.com',
      );

      expect(result.success, isTrue);
      expect(result.status, 'confirmed');
      expect(result.sats, 250);
      expect(result.bolt11, 'lnbc2500n1p_live_test_invoice');
      expect(result.paymentPreimage, 'preimage_live_settled_123');
      expect(creditService.balance, initialBalance - 25.0);
    });
  });
}
