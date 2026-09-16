// RED TEAM PoC — ledger-replay divergence: clamped debits create
// durable "phantom debt" that resurfaces on hydration and eats later
// earnings.
//
// awardStorageCredits(porPassed: false) writes a −5.0 ledger row even
// when the runtime balance is clamped at 0 (credit_service.dart:431-438)
// — the in-memory floor is applied per-operation, but _rebuildBalance
// (1249-1266) replays the raw rows with NO per-row floor. Every penalty
// recorded while the balance was already 0 is durable debt that was
// never actually deducted at runtime — and it comes back on the next
// restart to consume real, later-minted value. The same divergence hits
// the ATTESTED balance: _burnForDebit clamps _attestedBalance at 0 per
// op (1163-1166) while replay lets it run negative mid-history, so
// later attested mints are silently eaten too.
//
// Asserts the SECURE expectation — restart must preserve the balance
// the runtime reported. A failure is a live accounting divergence.
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart' hide CreditTransaction;
import 'package:alexandria/services/credits/credit_service.dart';

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
  test(
      'penalties clamped at runtime floor replay as real debt — '
      'a later honest mint is eaten after restart', () async {
    final db = AppDatabase();
    addTearDown(db.close);
    final s = CreditService(db: db, initialBalance: 10.0);
    await s.ready;
    expect(s.balance, 10.0);

    // Three failed PoR challenges: −5 each. Runtime clamps at 0, but
    // all three −5 rows are persisted to the durable ledger.
    for (var i = 0; i < 3; i++) {
      s.awardStorageCredits(
          sizeBytes: 1, peerCount: 1, porPassed: false, cid: 'c$i');
    }
    expect(s.balance, 0.0);

    // Honest +50 verification reward earned afterwards.
    s.awardVerificationCredits(action: 'audit', targetId: 't', amount: 50.0);
    expect(s.balance, 50.0);
    await s.settled;

    // Replay: 10 −15 +50 = 45 — the clamped-at-runtime penalties come
    // back as durable debt and consume 5 ℭ of real earnings.
    final s2 = CreditService(db: db, initialBalance: 0.0);
    await s2.ready;
    expect(s2.balance, 50.0,
        reason: 'runtime reported 50 — hydration replays to '
            '${s2.balance}; clamped penalties must not create durable '
            'debt the runtime never actually deducted');
  });

  test(
      'attested balance diverges the same way — a later attested mint '
      'is eaten by phantom penalty debt', () async {
    final db = AppDatabase();
    addTearDown(db.close);
    // Seed a +10 ATTESTED credit (as a foreign-verifier claim would).
    await db.insertCreditTransaction(_txRow(
      id: 'seed_attested',
      timestamp: DateTime(2024, 1, 1),
      amount: 10.0,
      isAttested: true,
    ));

    final s = CreditService(db: db, initialBalance: 0.0);
    await s.ready;
    expect(s.balance, 10.0);
    expect(s.attestedBalance, 10.0);

    // Three penalties: runtime floors _balance at 0; _attestedBalance
    // is untouched by the penalty path, and _burnForDebit never runs.
    for (var i = 0; i < 3; i++) {
      s.awardStorageCredits(
          sizeBytes: 1, peerCount: 1, porPassed: false, cid: 'c$i');
    }
    // Drift persists dateTime() at SECOND resolution — force the mint
    // into a strictly later second so replay order is deterministic:
    // penalties replay BEFORE the mint and must burn the attested pool.
    await Future.delayed(const Duration(seconds: 2));
    // Now mint +50 UNATTESTED on top.
    s.awardVerificationCredits(action: 'audit', targetId: 't', amount: 50.0);
    expect(s.balance, 50.0);
    expect(s.attestedBalance, 10.0,
        reason: 'runtime still holds the 10 ℭ attested pool');
    await s.settled;

    // Replay: penalties burn through the attested pool and drag `a`
    // negative mid-history; the final clamp hides it — the hydrated
    // node reports attestedBalance 0 where runtime reported 10.
    final s2 = CreditService(db: db, initialBalance: 0.0);
    await s2.ready;
    expect(s2.attestedBalance, 10.0,
        reason: 'runtime reported 10 attested — replay shows '
            '${s2.attestedBalance}: egress-eligible value silently '
            'vanished after restart');
    expect(s2.balance, 50.0,
        reason: 'runtime 50 vs replay ${s2.balance} — phantom debt');
  });
}
