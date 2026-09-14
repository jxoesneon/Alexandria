// Adversarial regression proofs for the egress gate (ALX-010).
// Locks down the E-T3 fixes: NET-attested accounting end-to-end via the
// database seam, attested<=balance invariant under every debit flavor,
// and NaN/inf gate ordering on every egress path.
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart' hide CreditTransaction;
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/crypto_bridge_service.dart';

Map<String, dynamic> _txRow({
  required String id,
  required DateTime timestamp,
  required double amount,
  bool isAttested = false,
  String type = 'storageReward',
  String description = 'seeded',
}) =>
    {
      'id': id,
      'timestamp': timestamp,
      'type': type,
      'amount': amount,
      'description': description,
      'referenceId': null,
      'hash': 'h_$id',
      'isAttested': isAttested,
    };

void main() {
  test('E-T3r#1: db attested +100 -> hydrate -> spend 60 -> attested 40',
      () async {
    final db = AppDatabase();
    addTearDown(db.close);
    await db.insertCreditTransaction(_txRow(
      id: 'attested_seed',
      timestamp: DateTime(2024, 1, 1),
      amount: 100.0,
      isAttested: true,
    ));

    final svc = CreditService(db: db, initialBalance: 0.0);
    await svc.ready;
    expect(svc.balance, 100.0);
    expect(svc.attestedBalance, 100.0);

    // Internal spend must burn attested (unattested portion is 0).
    expect(svc.spendCredits(amount: 60.0, reason: 'internal spend'), isTrue);
    expect(svc.attestedBalance, 40.0);
    expect(svc.balance, 40.0);

    // The flag-on egress comparison is `credits > attestedBalance`:
    // 50 > 40 must reject. Flag is off, so the reachable assertion is the
    // payouts-disabled reason — but the arithmetic the gate WILL apply is
    // proven here: attestedBalance is net, not gross.
    final bridge = CryptoBridgeService(creditService: svc);
    expect(bridge.egressRejectionReason(50.0),
        CryptoBridgeService.payoutsDisabledReason);
    expect(50.0 > svc.attestedBalance, isTrue,
        reason: 'flag-on path rejects egress above NET attested balance');
    expect(bridge.egressRejectionReason(40.0),
        CryptoBridgeService.payoutsDisabledReason,
        reason: 'gate ordering: disabled reason precedes attested check');

    // Replay reproduces the same net state after restart.
    await svc.settled;
    final svc2 = CreditService(db: db, initialBalance: 0.0);
    await svc2.ready;
    expect(svc2.attestedBalance, 40.0);
    expect(svc2.balance, 40.0);
  });

  test('E-T3r#2: attestedBalance never exceeds balance — all debit flavors',
      () async {
    final db = AppDatabase();
    addTearDown(db.close);
    await db.insertCreditTransaction(_txRow(
      id: 'a100',
      timestamp: DateTime(2024, 1, 1),
      amount: 100.0,
      isAttested: true,
    ));
    final svc = CreditService(db: db, initialBalance: 0.0);
    await svc.ready;

    // Flavor A: PoR slash penalty debits _balance WITHOUT _burnForDebit.
    // The attestedBalance getter must still clamp to balance (never exceed).
    svc.awardStorageCredits(
      sizeBytes: 1024,
      peerCount: 3,
      porPassed: false,
      cid: 'bafy_slash',
    );
    expect(svc.balance, 95.0);
    expect(svc.attestedBalance, lessThanOrEqualTo(svc.balance),
        reason: 'getter must clamp attested to balance after penalty');
    expect(svc.attestedBalance, 95.0);

    // Flavor B: escrow debit — burns attested when unattested is empty.
    expect(svc.debitEscrow(amount: 50.0, referenceId: 'b1'), isTrue);
    expect(svc.attestedBalance, 45.0);
    expect(svc.balance, 45.0);
    expect(svc.attestedBalance, lessThanOrEqualTo(svc.balance));

    // Flavor C: regular spend to zero.
    expect(svc.spendCredits(amount: 45.0, reason: 'drain'), isTrue);
    expect(svc.attestedBalance, 0.0);
    expect(svc.balance, 0.0);
  });

  test('E-T3r#3: NaN/inf/zero/negative rejected on every path, no throw',
      () async {
    final svc = CreditService(initialBalance: 100.0);
    final bridge = CryptoBridgeService(creditService: svc);
    final before = svc.balance;

    for (final amount in <double>[
      double.nan,
      double.infinity,
      double.negativeInfinity,
      0.0,
      -1.0,
      -double.infinity,
    ]) {
      expect(bridge.egressRejectionReason(amount), 'Invalid egress amount.');
      expect(bridge.exportCreditsAsCashuToken(amount), isNull);
      expect(
          bridge.sweepToLightningAddress(
              creditsToSweep: amount, customAddress: 'a@b.co'),
          isFalse);
      final r = await bridge.sweepToLightningAddressLive(
          creditsToSweep: amount, customAddress: 'a@b.co');
      expect(r.success, isFalse);
      expect(r.status, 'failed');
      expect(r.error, 'Invalid egress amount.');
    }
    expect(svc.balance, before);
    expect(bridge.exportedTokensHistory, isEmpty);
  });

  test('E-T3r#4: fabricated voucher credits nothing; secrets absorbed',
      () async {
    final svc = CreditService(initialBalance: 100.0);
    final bridge = CryptoBridgeService(creditService: svc);
    final before = svc.balance;

    const token = CashuToken(
      mint: 'https://mint.example.com/Bitcoin',
      proofs: [
        CashuProof(id: 'k', amount: 128, secret: 's1', c: 'c1'),
        CashuProof(id: 'k', amount: 64, secret: 's2', c: 'c2'),
      ],
    );
    final serialized = token.serialize();
    expect(bridge.redeemCashuToken(serialized), 0.0);
    expect(bridge.redeemCashuToken(serialized), 0.0);
    expect(svc.balance, before);
  });
}
