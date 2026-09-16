import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/credits/credit_models.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/crypto_bridge_service.dart';

class _FakeCreditService extends CreditService {
  _FakeCreditService() : super();

  double _bal = 100.0;
  double _attested = 50.0;

  @override
  double get balance => _bal;

  @override
  double get attestedBalance => _attested;

  @override
  bool spendCredits({
    required double amount,
    required String reason,
    String? referenceId,
    CreditType debitType = CreditType.priorityAccessDebit,
    bool isAttested = false,
  }) {
    // Mirror the real contract: an attested spend must be covered by the
    // attested pool and consumes it — the cumulative egress budget is
    // enforced inside the debit, atomically, not by the advisory gate.
    if (isAttested && _attested < amount) return false;
    if (_bal >= amount) {
      _bal -= amount;
      if (isAttested) _attested -= amount;
      return true;
    }
    return false;
  }
}

void main() {
  group('CryptoBridgeService Tests', () {
    test('CashuProof and CashuToken serialization & deserialization', () {
      const proof1 = CashuProof(id: 'k1', amount: 8, secret: 's1', c: 'c1');
      const proof2 = CashuProof(id: 'k1', amount: 2, secret: 's2', c: 'c2');

      final token = const CashuToken(
        mint: 'https://mint.example.com',
        proofs: [proof1, proof2],
      );

      expect(token.totalAmountSats, 10);
      final serialized = token.serialize();
      expect(serialized.startsWith('cashuA'), isTrue);

      final deserialized = CashuToken.deserialize(serialized);
      expect(deserialized, isNotNull);
      expect(deserialized!.mint, 'https://mint.example.com');
      expect(deserialized.proofs.length, 2);
      expect(deserialized.totalAmountSats, 10);

      // Deserialization with invalid input
      expect(CashuToken.deserialize('invalid_token'), isNull);
      expect(CashuToken.deserialize('cashuAinvalidbase64'), isNull);
    });

    test('SweepResult serialization', () {
      const result = SweepResult(
        success: true,
        status: 'confirmed',
        sats: 100,
        bolt11: 'lnbc100...',
        paymentPreimage: 'preimage_xyz',
      );

      final json = result.toJson();
      expect(json['success'], isTrue);
      expect(json['status'], 'confirmed');
      expect(json['sats'], 100);
      expect(json['bolt11'], 'lnbc100...');
    });

    test('Lightning address validation', () {
      expect(CryptoBridgeService.isValidLightningAddress('alice@stacker.news'), isTrue);
      expect(CryptoBridgeService.isValidLightningAddress('satoshi@bitcoin.org'), isTrue);
      expect(CryptoBridgeService.isValidLightningAddress('notanaddress'), isFalse);
      expect(CryptoBridgeService.isValidLightningAddress('invalid@'), isFalse);
    });

    test('egress and payout kill-switch invariant', () {
      final creditService = _FakeCreditService();
      final bridge = CryptoBridgeService(creditService: creditService);

      // Payouts are disabled by default
      expect(CryptoBridgeService.payoutsEnabled, isFalse);
      expect(bridge.egressRejectionReason(10.0), CryptoBridgeService.payoutsDisabledReason);

      // Invalid amounts
      expect(bridge.egressRejectionReason(-5.0), 'Invalid egress amount.');
      expect(bridge.egressRejectionReason(double.nan), 'Invalid egress amount.');

      // Cashu token export blocked
      expect(bridge.exportCreditsAsCashuToken(10.0), isNull);

      // Lightning sweep blocked
      expect(bridge.sweepToLightningAddress(creditsToSweep: 10.0, customAddress: 'alice@domain.com'), isFalse);

      // Redeem voucher returns 0.0 with rejection
      const sampleProof = CashuProof(id: 'k1', amount: 10, secret: 'sec123', c: 'c123');
      final sampleToken = const CashuToken(mint: 'https://mint.example.com', proofs: [sampleProof]);
      expect(bridge.redeemCashuToken(sampleToken.serialize()), 0.0);
      expect(bridge.redeemCashuToken('bad_token'), 0.0);
    });

    test('configuration getters and setters notify listeners', () async {
      final creditService = _FakeCreditService();
      final bridge = CryptoBridgeService(creditService: creditService);

      var notified = 0;
      bridge.addListener(() => notified++);

      bridge.setLightningAddress('user@getalby.com');
      expect(bridge.lightningAddress, 'user@getalby.com');
      expect(notified, 1);

      await bridge.setCashuMint('https://mint.custom.org');
      expect(bridge.preferredCashuMint, 'https://mint.custom.org');
      expect(notified, 2);
    });

    test('live sweep returns error when egress is blocked', () async {
      final creditService = _FakeCreditService();
      final bridge = CryptoBridgeService(creditService: creditService);

      final res = await bridge.sweepToLightningAddressLive(
        creditsToSweep: 10.0,
        customAddress: 'user@domain.com',
      );

      expect(res.success, isFalse);
      expect(res.status, 'failed');
      expect(res.error, CryptoBridgeService.payoutsDisabledReason);
    });

    test('enabled payouts allows export, simulated sweep, and checks attested balance', () {
      final creditService = _FakeCreditService();
      final bridge = CryptoBridgeService(
        creditService: creditService,
        overridePayoutsAllowed: true,
      );

      // Exceeds attested balance (attested is 50, request 60): the
      // advisory gate stays a request-level check — the cumulative
      // attested budget is enforced atomically inside the debit
      // (isAttested spend), which refuses here.
      expect(bridge.egressRejectionReason(60.0), isNull);
      expect(bridge.exportCreditsAsCashuToken(60.0), isNull);
      expect(bridge.sweepToLightningAddress(creditsToSweep: 60.0, customAddress: 'alice@domain.com'), isFalse);

      // Within attested balance (20 credits)
      expect(bridge.egressRejectionReason(20.0), isNull);

      // Export as Cashu token
      final token = bridge.exportCreditsAsCashuToken(20.0);
      expect(token, isNotNull);
      expect(token!.totalAmountSats, 200); // 20 * 10 sats
      expect(bridge.exportedTokensHistory, isNotEmpty);

      // Simulated sweep to Lightning Address
      final swept = bridge.sweepToLightningAddress(
        creditsToSweep: 10.0,
        customAddress: 'alice@domain.com',
      );
      expect(swept, isTrue);
    });
  });
}
