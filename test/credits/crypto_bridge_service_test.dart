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
      expect(
          CryptoBridgeService.isValidLightningAddress('satoshi@stacker.news'),
          isTrue);
      expect(
          CryptoBridgeService.isValidLightningAddress('alexandria@getalby.com'),
          isTrue);
      expect(CryptoBridgeService.isValidLightningAddress('invalid-address'),
          isFalse);
      expect(CryptoBridgeService.isValidLightningAddress('missing_domain@'),
          isFalse);
      expect(CryptoBridgeService.isValidLightningAddress('@nodomain.com'),
          isFalse);
    });

    test('updates Lightning Address and Mint configurations', () async {
      bridgeService.setLightningAddress('curator@fountain.fm');
      expect(bridgeService.lightningAddress, 'curator@fountain.fm');

      await bridgeService.setCashuMint(
          'https://legend.lnbits.com/cashu/api/v1/4gr9Xcm93Q9kzUkNuqtHzQ');
      expect(bridgeService.preferredCashuMint, contains('legend.lnbits.com'));
    });

    test(
        'rejects Cashu export while the service-level payout gate is closed (ALX-010)',
        () {
      final initialBalance = creditService.balance; // 100.0

      // Sufficient balance - still rejected: the service-level gate holds even
      // for direct callers that bypass the MCP wrapper.
      final token = bridgeService.exportCreditsAsCashuToken(10.0);
      expect(token, isNull);

      // Reason string is surfaced verbatim for UI/API callers.
      expect(
        bridgeService.egressRejectionReason(10.0),
        CryptoBridgeService.payoutsDisabledReason,
      );

      // Nothing was debited and no bearer token was recorded.
      expect(creditService.balance, initialBalance);
      expect(bridgeService.exportedTokensHistory, isEmpty);
    });

    test('rejects Cashu export when balance is insufficient or invalid', () {
      final tokenExcess = bridgeService.exportCreditsAsCashuToken(500.0);
      expect(tokenExcess, isNull);

      final tokenZero = bridgeService.exportCreditsAsCashuToken(0.0);
      expect(tokenZero, isNull);

      final tokenNegative = bridgeService.exportCreditsAsCashuToken(-5.0);
      expect(tokenNegative, isNull);
    });

    test('redeemCashuToken never credits fabricated proofs (ALX-010)', () {
      final initialBalance = creditService.balance;

      // Fabricate a well-formed cashuA voucher with locally invented proofs -
      // the exact forgery the old code path used to credit.
      final fabricated = const CashuToken(
        mint: 'https://mint.example.com/Bitcoin',
        proofs: [
          CashuProof(
              id: 'fake_keyset', amount: 128, secret: 'deadbeef', c: 'cafe'),
          CashuProof(
              id: 'fake_keyset', amount: 64, secret: 'beefdead', c: 'face'),
        ],
      ).serialize();

      // Parses fine, but must NOT credit: a local spent-set is not proof of
      // mint backing until NUT-03 swap + /v1/checkstate verification lands.
      final redeemedCredits = bridgeService.redeemCashuToken(fabricated);
      expect(redeemedCredits, 0.0);
      expect(creditService.balance, initialBalance);

      // Repeated submissions are equally fruitless.
      expect(bridgeService.redeemCashuToken(fabricated), 0.0);
      expect(creditService.balance, initialBalance);
    });

    test('handles malformed Cashu token strings gracefully', () {
      expect(bridgeService.redeemCashuToken('invalid_token_string'), 0.0);
      expect(bridgeService.redeemCashuToken('cashuA_not_valid_base64!'), 0.0);
      expect(CashuToken.deserialize('cashuA'), isNull);
    });

    test(
        'simulated Lightning sweep is closed by the service-level gate (ALX-010)',
        () {
      bridgeService.setLightningAddress('preservationist@getalby.com');
      final initialBalance = creditService.balance; // 100.0

      // The simulated sweep was the fake-success fallback that burned real
      // credits - it is a ℭ→external-value path and must stay closed too.
      final success =
          bridgeService.sweepToLightningAddress(creditsToSweep: 15.0);
      expect(success, isFalse);
      expect(creditService.balance, initialBalance);

      final customSuccess = bridgeService.sweepToLightningAddress(
        creditsToSweep: 10.0,
        customAddress: 'archive_node@blink.sv',
      );
      expect(customSuccess, isFalse);
      expect(creditService.balance, initialBalance);
    });

    test(
        'live Lightning sweep fails closed with surfaced reason before any network IO',
        () async {
      // Any request reaching the wire proves the gate did not short-circuit.
      var networkTouched = false;
      final mockClient = MockClient((request) async {
        networkTouched = true;
        return http.Response('Gate must short-circuit before this', 500);
      });

      final liveBridge = CryptoBridgeService(
        creditService: creditService,
        lnurlService: LnurlService(client: mockClient),
        mintClient: CashuMintClient(client: mockClient),
      );

      final initialBalance = creditService.balance; // 100.0

      // Sufficient balance - still rejected at the service layer.
      final result = await liveBridge.sweepToLightningAddressLive(
        creditsToSweep: 25.0,
        customAddress: 'bob@getalby.com',
      );

      expect(result.success, isFalse);
      expect(result.status, 'failed');
      expect(result.error, CryptoBridgeService.payoutsDisabledReason);
      expect(networkTouched, isFalse);
      expect(creditService.balance, initialBalance);
    });

    test(
        'rejects NaN, Infinity, zero, and negative egress amounts without throwing or debiting',
        () async {
      final initialBalance = creditService.balance; // 100.0

      // `NaN > x` is false, so these inputs used to slip past the
      // attested-balance comparison and crash on
      // `(amount * satsPerCredit).toInt()`. Every egress path must now
      // short-circuit on 'Invalid egress amount.' - no throw, no debit.
      final invalidAmounts = <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
        0.0,
        -5.0,
      ];

      for (final amount in invalidAmounts) {
        expect(
          bridgeService.egressRejectionReason(amount),
          'Invalid egress amount.',
          reason: 'amount=$amount must be rejected before any balance check',
        );

        // Export path: null, never a throw.
        expect(
          bridgeService.exportCreditsAsCashuToken(amount),
          isNull,
          reason: 'export must reject amount=$amount',
        );

        // Simulated sweep: false, never a throw.
        expect(
          bridgeService.sweepToLightningAddress(
            creditsToSweep: amount,
            customAddress: 'preservationist@getalby.com',
          ),
          isFalse,
          reason: 'simulated sweep must reject amount=$amount',
        );

        // Live sweep: failed SweepResult, never a throw - the UnsupportedError
        // from NaN.toInt() previously escaped OUTSIDE the try/catch.
        final result = await bridgeService.sweepToLightningAddressLive(
          creditsToSweep: amount,
          customAddress: 'preservationist@getalby.com',
        );
        expect(result.success, isFalse, reason: 'amount=$amount');
        expect(result.status, 'failed');
        expect(result.error, isNotNull);
      }

      // No path debited the wallet or minted a bearer token.
      expect(creditService.balance, initialBalance);
      expect(bridgeService.exportedTokensHistory, isEmpty);
    });

    // ------------------------------------------------------------------
    // ALX-010 contract notes (no test seam - payoutsEnabled is a const and
    // these tests exercise a REAL CreditService, not a stub):
    //
    // * attestedBalance must be NET of attested spending: attested debit
    //   transactions decrement it (orchestrator-owned fix in
    //   credit_service.dart). Once payoutsEnabled flips, the expected
    //   semantics are: attest 100 ℭ → egress 60 ℭ → attestedBalance == 40
    //   and any further egress > 40 ℭ is rejected. A gross sum would let
    //   already-egressed attested value leave twice - if a future change
    //   breaks that, add a seam test here asserting
    //   `egressRejectionAmount(attestedNet + ε)` returns the ALX-010 reason.
    //
    // * Debit-failure path in sweepToLightningAddressLive is intentionally
    //   untested while payoutsEnabled == false: the gate rejects before any
    //   network IO, so spendCredits is unreachable from this suite. The
    //   result IS captured in the service - on false it returns
    //   SweepResult(status: 'failed', error: 'Payment settled but local
    //   debit failed - manual reconciliation required') instead of falsely
    //   reporting 'confirmed'. When a seam exists, cover it by forcing
    //   spendCredits to return false post-melt (e.g. a CreditService
    //   subclass whose balance drops below creditsToSweep between the gate
    //   check and the debit, or a mock returning false).
    // ------------------------------------------------------------------
  });
}
