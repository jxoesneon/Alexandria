import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/credits/cashu_mint_client.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/crypto_bridge_service.dart';
import 'package:alexandria/services/credits/lnurl_service.dart';
import 'package:alexandria/services/credits/poch_service.dart';

/// LNURL resolver seam — never touches the network.
class _FakeLnurl extends LnurlService {
  _FakeLnurl({this.onResolve});

  final Future<LnurlPayInvoice> Function(
      String lightningAddress, int amountSats)? onResolve;

  @override
  Future<LnurlPayInvoice> resolveAddressToInvoice({
    required String lightningAddress,
    required int amountSats,
  }) {
    final handler = onResolve;
    if (handler != null) return handler(lightningAddress, amountSats);
    return Future.value(LnurlPayInvoice(
      pr: 'lnbc${amountSats}n1fakeinvoice',
      amountSats: amountSats,
      recipientAddress: lightningAddress,
      paymentHash: 'hash123',
    ));
  }
}

/// Mint client seam — never touches the network.
class _FakeMint extends CashuMintClient {
  _FakeMint({this.onMelt});

  Future<CashuMeltQuote> Function(String mintUrl, String bolt11)? onQuote;
  final Future<CashuMeltResult> Function(
      String mintUrl, String quoteId, List<CashuProof> proofs)? onMelt;

  @override
  Future<CashuMeltQuote> getMeltQuote({
    required String mintUrl,
    required String bolt11,
  }) {
    final handler = onQuote;
    if (handler != null) return handler(mintUrl, bolt11);
    return Future.value(const CashuMeltQuote(
      quoteId: 'quote-1',
      amountSats: 100,
      feeReserveSats: 2,
      expiry: 99999,
    ));
  }

  @override
  Future<CashuMeltResult> meltProofs({
    required String mintUrl,
    required String quoteId,
    required List<CashuProof> proofs,
  }) {
    final handler = onMelt;
    if (handler != null) return handler(mintUrl, quoteId, proofs);
    return Future.value(const CashuMeltResult(
      paid: true,
      paymentPreimage: 'preimage-abc',
      quoteId: 'quote-1',
    ));
  }
}

void main() {
  late CreditService creditService;

  setUp(() {
    creditService = CreditService(
      pochService: PoCHService(),
      initialBalance: 100.0,
    );
  });

  CryptoBridgeService openBridge({_FakeLnurl? lnurl, _FakeMint? mint}) =>
      CryptoBridgeService(
        creditService: creditService,
        lnurlService: lnurl ?? _FakeLnurl(),
        mintClient: mint ?? _FakeMint(),
        // Test seam: opens the compile-time ALX-010 gate so the deeper
        // validation and wire-path branches are reachable.
        overridePayoutsAllowed: true,
      );

  group('CashuToken wire format', () {
    test('serialize/deserialize round-trips proofs and sums sats', () {
      const token = CashuToken(
        mint: 'https://mint.example.com',
        proofs: [
          CashuProof(id: 'ks1', amount: 8, secret: 's1', c: 'c1'),
          CashuProof(id: 'ks1', amount: 2, secret: 's2', c: 'c2'),
        ],
      );
      final serialized = token.serialize();
      expect(serialized, startsWith('cashuA'));
      expect(serialized.contains('='), isFalse); // padding stripped

      final restored = CashuToken.deserialize(serialized);
      expect(restored, isNotNull);
      expect(restored!.mint, 'https://mint.example.com');
      expect(restored.proofs.length, 2);
      expect(restored.totalAmountSats, 10);
    });

    test('deserialize returns null for non-cashuA strings', () {
      expect(CashuToken.deserialize('cashuBxxxx'), isNull);
      expect(CashuToken.deserialize(''), isNull);
    });

    test('deserialize returns null when token list is empty', () {
      final b64 = base64UrlEncode(utf8.encode(jsonEncode({'token': []})));
      expect(CashuToken.deserialize('cashuA$b64'), isNull);
    });

    test('deserialize returns null when JSON shape is wrong', () {
      // Valid base64 of a JSON list — not the expected map.
      final b64 = base64UrlEncode(utf8.encode(jsonEncode([1, 2, 3])));
      expect(CashuToken.deserialize('cashuA$b64'), isNull);
    });

    test('CashuProof.fromJson defaults the keyset id', () {
      final proof = CashuProof.fromJson(const {
        'amount': 4,
        'secret': 'sec',
        'C': 'sig',
      });
      expect(proof.id, 'default_keyset');
      expect(proof.amount, 4);
      expect(proof.toJson()['C'], 'sig');
    });
  });

  group('Cashu/LNURL model serialization', () {
    test('SweepResult.toJson includes optional fields only when set', () {
      const minimal = SweepResult(success: false, status: 'failed', sats: 0);
      expect(minimal.toJson().containsKey('bolt11'), isFalse);
      const full = SweepResult(
        success: true,
        status: 'confirmed',
        sats: 42,
        bolt11: 'lnbc42',
        paymentPreimage: 'pre',
        error: 'none',
      );
      final json = full.toJson();
      expect(json['bolt11'], 'lnbc42');
      expect(json['payment_preimage'], 'pre');
      expect(json['error'], 'none');
    });

    test('CashuMeltQuote serialization and required-total math', () {
      const quote = CashuMeltQuote(
        quoteId: 'q9',
        amountSats: 50,
        feeReserveSats: 3,
        paid: true,
        expiry: 1234,
      );
      expect(quote.totalSatsRequired, 53);
      final json = quote.toJson();
      expect(json['quote'], 'q9');
      expect(json['paid'], isTrue);

      final restored = CashuMeltQuote.fromJson(const {
        'quote': 'q2',
        'amount': 7,
      });
      expect(restored.feeReserveSats, 0);
      expect(restored.expiry, 0);
      expect(restored.totalSatsRequired, 7);
    });

    test('CashuMeltResult.toJson omits null preimage', () {
      const result = CashuMeltResult(paid: false, quoteId: 'q');
      expect(result.toJson().containsKey('payment_preimage'), isFalse);
    });

    test('LnurlPayInvoice.toJson shape', () {
      const invoice = LnurlPayInvoice(
        pr: 'lnbc1x',
        amountSats: 10,
        recipientAddress: 'a@b.c',
      );
      final json = invoice.toJson();
      expect(json['pr'], 'lnbc1x');
      expect(json['recipient_address'], 'a@b.c');
      expect(json.containsKey('payment_hash'), isFalse);
    });
  });

  group('egress paths with the payout gate open', () {
    test('egressRejectionReason returns null for a valid request', () {
      final bridge = openBridge();
      expect(bridge.egressRejectionReason(5.0), isNull);
      expect(
          bridge.egressRejectionReason(double.nan), 'Invalid egress amount.');
    });

    test('export still refuses when the attested pool cannot cover it', () {
      // Welcome credits are unattested — the attested debit must refuse.
      final bridge = openBridge();
      expect(bridge.exportCreditsAsCashuToken(10.0), isNull);
      expect(creditService.balance, 100.0); // nothing debited
      expect(bridge.exportedTokensHistory, isEmpty);
    });

    test('simulated sweep rejects invalid address and insufficient balance',
        () {
      final bridge = openBridge();
      expect(
        bridge.sweepToLightningAddress(
            creditsToSweep: 5.0, customAddress: 'not-an-address'),
        isFalse,
      );
      expect(
        bridge.sweepToLightningAddress(
            creditsToSweep: 500.0, customAddress: 'user@wallet.io'),
        isFalse,
      );
      // Valid address + covered balance — but the attested debit refuses.
      expect(
        bridge.sweepToLightningAddress(
            creditsToSweep: 5.0, customAddress: 'user@wallet.io'),
        isFalse,
      );
      expect(creditService.balance, 100.0);
    });

    test('live sweep reports invalid address before any wire IO', () async {
      var lnurlTouched = false;
      final bridge = openBridge(
        lnurl: _FakeLnurl(onResolve: (_, __) {
          lnurlTouched = true;
          throw StateError('must not be called');
        }),
      );
      final result = await bridge.sweepToLightningAddressLive(
        creditsToSweep: 5.0,
        customAddress: 'bad-address',
      );
      expect(result.success, isFalse);
      expect(result.error, 'Invalid Lightning Address format');
      expect(lnurlTouched, isFalse);
    });

    test('live sweep reports insufficient balance before any wire IO',
        () async {
      var lnurlTouched = false;
      final bridge = openBridge(
        lnurl: _FakeLnurl(onResolve: (_, __) {
          lnurlTouched = true;
          throw StateError('must not be called');
        }),
      );
      final result = await bridge.sweepToLightningAddressLive(
        creditsToSweep: 5000.0,
        customAddress: 'user@wallet.io',
      );
      expect(result.success, isFalse);
      expect(result.error, 'Insufficient credit balance');
      expect(lnurlTouched, isFalse);
    });

    test('live sweep settles on the wire then surfaces the refused debit',
        () async {
      final bridge = openBridge();
      final result = await bridge.sweepToLightningAddressLive(
        creditsToSweep: 5.0,
        customAddress: 'user@wallet.io',
      );
      // Melt succeeded but attestedBalance == 0 — the reconciliation
      // branch must report failure rather than a false 'confirmed'.
      expect(result.success, isFalse);
      expect(result.status, 'failed');
      expect(result.sats, 50);
      expect(result.bolt11, isNotNull);
      expect(result.paymentPreimage, 'preimage-abc');
      expect(result.error, contains('reconciliation'));
      expect(creditService.balance, 100.0);
    });

    test('live sweep reports a mint that cannot route the invoice', () async {
      final bridge = openBridge(
        mint: _FakeMint(
            onMelt: (_, quoteId, __) async =>
                CashuMeltResult(paid: false, quoteId: quoteId)),
      );
      final result = await bridge.sweepToLightningAddressLive(
        creditsToSweep: 5.0,
        customAddress: 'user@wallet.io',
      );
      expect(result.success, isFalse);
      expect(result.error, contains('could not route'));
    });

    test('live sweep surfaces transport failures through the catch path',
        () async {
      final bridge = openBridge(
        lnurl: _FakeLnurl(
            onResolve: (_, __) => Future.error(StateError('lnurl down'))),
      );
      final result = await bridge.sweepToLightningAddressLive(
        creditsToSweep: 5.0,
        customAddress: 'user@wallet.io',
      );
      expect(result.success, isFalse);
      expect(result.error, contains('lnurl down'));
      expect(result.sats, 50);
    });
  });

  group('redeemCashuToken edge cases', () {
    test('well-formed but proofless voucher redeems to zero', () {
      final bridge = CryptoBridgeService(creditService: creditService);
      final empty = const CashuToken(mint: 'm', proofs: []).serialize();
      expect(bridge.redeemCashuToken(empty), 0.0);
    });
  });
}
