// RED TEAM PoC — the attested-balance egress gate is NON-CUMULATIVE.
//
// CryptoBridgeService.egressRejectionReason rejects only when the
// *requested* chunk exceeds CreditService.attestedBalance. But every
// egress path settles through CreditService.spendCredits, whose
// _burnForDebit consumes the UNATTESTED portion first
// (credit_service.dart:1160-1167) and touches _attestedBalance only
// once unattested value is exhausted. The attested "quota" is therefore
// never consumed by egress itself: a node holding A attested + U
// unattested can export A+U total, in ≤A-sized chunks, while every
// single call passes the "only verifier-signed attested credit may
// egress" check.
//
// RFC ALX-011 §1/§6 invariant: "only value backed by a *foreign*
// verifier's signature may ever egress; self-certified value is
// internal-only." The test asserts the SECURE expectation — cumulative
// egress must not exceed attested balance. A FAILURE is a live exploit:
// self-certified credits laundered through the egress gate.
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart' hide CreditTransaction;
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/crypto_bridge_service.dart';

Map<String, dynamic> _txRow({
  required String id,
  required DateTime timestamp,
  required double amount,
  bool isAttested = false,
}) =>
    {
      'id': id,
      'timestamp': timestamp,
      'type': 'storageReward',
      'amount': amount,
      'description': 'seeded',
      'referenceId': null,
      'hash': 'h_$id',
      'isAttested': isAttested,
    };

void main() {
  test('egress gate is cumulative: total exported must never exceed the '
      'attested balance', () async {
    final db = AppDatabase();
    addTearDown(db.close);
    // 10 ℭ attested (foreign-verifier-backed) + 90 ℭ self-certified.
    await db.insertCreditTransaction(_txRow(
      id: 'seed_attested',
      timestamp: DateTime(2024, 1, 1),
      amount: 10.0,
      isAttested: true,
    ));
    await db.insertCreditTransaction(_txRow(
      id: 'seed_unattested',
      timestamp: DateTime(2024, 1, 2),
      amount: 90.0,
    ));

    final cs = CreditService(db: db, initialBalance: 0.0);
    await cs.ready;
    expect(cs.balance, 100.0);
    expect(cs.attestedBalance, 10.0);

    // The test-only override exercises the flag-on code path the gate
    // will run once payouts open.
    final bridge = CryptoBridgeService(
        creditService: cs, overridePayoutsAllowed: true);

    var exported = 0.0;
    // Attacker drains the wallet in attested-sized chunks. Every call
    // must satisfy credits <= attestedBalance — and does, forever,
    // because the egress debit never consumes the attested pool.
    while (cs.balance > 0) {
      expect(bridge.egressRejectionReason(10.0), isNull,
          reason: 'each 10-chunk passes the per-call gate — '
              'attestedBalance never decreases');
      final token = bridge.exportCreditsAsCashuToken(10.0);
      if (token == null) break;
      exported += 10.0;
      if (exported > 1000) fail('unbounded loop — gate never closed');
    }

    expect(exported, lessThanOrEqualTo(10.0),
        reason: 'exported $exported ℭ through an egress gate that '
            'permits only the 10 ℭ attested portion — the remaining '
            '${exported - 10.0} ℭ was self-certified value that left '
            'the system (ALX-010/011 invariant violated)');
    expect(cs.attestedBalance, 0.0,
        reason: 'if the gate consumed attested value, quota would be '
            'exhausted — instead unattested burns first');
  });

  test('live sweep path shares the same non-cumulative drain', () async {
    final db = AppDatabase();
    addTearDown(db.close);
    await db.insertCreditTransaction(_txRow(
      id: 'seed_attested',
      timestamp: DateTime(2024, 1, 1),
      amount: 5.0,
      isAttested: true,
    ));
    await db.insertCreditTransaction(_txRow(
      id: 'seed_unattested',
      timestamp: DateTime(2024, 1, 2),
      amount: 45.0,
    ));
    final cs = CreditService(db: db, initialBalance: 0.0);
    await cs.ready;
    final bridge = CryptoBridgeService(
        creditService: cs, overridePayoutsAllowed: true);

    // The *simulated* sweep debits real credits for a pretend payment —
    // the same spend path, the same gate. Loop 5-ℭ sweeps.
    var swept = 0.0;
    while (cs.balance >= 5.0) {
      final ok = bridge.sweepToLightningAddress(
          creditsToSweep: 5.0, customAddress: 'a@b.co');
      if (!ok) break;
      swept += 5.0;
    }
    expect(swept, lessThanOrEqualTo(5.0),
        reason: 'swept $swept ℭ with only 5 ℭ attested — the gate is a '
            'rate limit, not a budget; self-certified value egressed');
  });
}
