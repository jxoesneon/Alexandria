// Adversarial regression proofs for the persistent credit ledger (ALX-010).
// Locks down every E-T2 exploit class: pre-hydration cap bypass, phantom
// genesis spend, concurrent genesis double-grant, hydration-failure
// divergence — plus NET-attested accounting (_attestedBalance /
// _burnForDebit / replay in _rebuildBalance).
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart' hide CreditTransaction;
import 'package:alexandria/services/credits/credit_models.dart';
import 'package:alexandria/services/credits/credit_service.dart';

String _dayKey() {
  final now = DateTime.now().toUtc();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

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

/// Db whose ledger reads always fail (writes still work).
class _ReadFailsDb extends AppDatabase {
  int failures;
  _ReadFailsDb({this.failures = 1});
  @override
  Future<List<Map<String, dynamic>>> getCreditTransactions(
      {int limit = 200}) {
    if (failures > 0) {
      failures--;
      throw StateError('simulated ledger read failure');
    }
    return super.getCreditTransactions(limit: limit);
  }
}

void main() {
  test('E-T2#1: pre-hydration award cannot bypass persisted cap', () async {
    final db = AppDatabase();
    addTearDown(db.close);
    // Persist 150/200 storage minted for today.
    await db.upsertDailyMinted(_dayKey(), 'storageReward', 150.0);

    final svc = CreditService(db: db, initialBalance: 0.0);
    // Fire BEFORE awaiting ready — must mint nothing.
    final pre = svc.awardStorageCredits(
      sizeBytes: 500 * 1024 * 1024,
      peerCount: 8,
      porPassed: true,
      cid: 'bafy_pre',
    );
    expect(pre, 0.0, reason: 'pre-hydration award must be refused');
    await svc.ready;

    final post = svc.awardStorageCredits(
      sizeBytes: 500 * 1024 * 1024,
      peerCount: 8,
      porPassed: true,
      cid: 'bafy_post',
    );
    expect(post, lessThanOrEqualTo(50.0));
    expect(post, 50.0);
    // Next award must clamp to 0.
    expect(
      svc.awardStorageCredits(
          sizeBytes: 500 * 1024 * 1024,
          peerCount: 8,
          porPassed: true,
          cid: 'bafy_over'),
      0.0,
    );
    await svc.settled;
    final minted = await db.getDailyMinted(_dayKey());
    expect(minted['storageReward'], 200.0);
  });

  test('E-T2#2: phantom-balance spend refused pre-hydration', () async {
    final db = AppDatabase();
    addTearDown(db.close);
    // Ledger balance = 10 via a persisted credit row.
    await db.insertCreditTransaction(_txRow(
      id: 'seed_credit',
      timestamp: DateTime(2024, 1, 1),
      amount: 10.0,
      type: 'computeReward',
    ));

    // initialBalance 0 keeps the seeded ledger at 10 (no genesis granted).
    final svc = CreditService(db: db, initialBalance: 0.0);
    // Phantom balance era: before ready, balance must be 0, never phantom.
    expect(svc.balance, 0.0);
    final rowsBefore = (await db.getCreditTransactions()).length;
    final ok = svc.spendCredits(amount: 90.0, reason: 'pre-hydration drain');
    expect(ok, isFalse);
    final rowsAfter = (await db.getCreditTransactions()).length;
    expect(rowsAfter, rowsBefore, reason: 'no debit row may be persisted');
    await svc.ready;
    // Real ledger balance is authoritative now.
    expect(svc.balance, 10.0);
    expect(svc.spendCredits(amount: 90.0, reason: 'overspend'), isFalse);
    expect(svc.spendCredits(amount: 10.0, reason: 'full drain'), isTrue);
    expect(svc.balance, 0.0);
  });

  test('E-T2#2b: EVERY mutator refused pre-hydration', () async {
    final db = AppDatabase();
    addTearDown(db.close);
    final svc = CreditService(db: db, initialBalance: 0.0);
    expect(
        svc.awardComputeCredits(cauchyMb: 5.0), 0.0,
        reason: 'compute mint pre-hydration');
    expect(
        svc.awardVerificationCredits(action: 'x', targetId: 'y'), 0.0,
        reason: 'verification mint pre-hydration');
    expect(
        svc.awardBountyEscrow(amount: 5, bountyId: 'b', cid: 'c'), 0.0,
        reason: 'escrow payout pre-hydration');
    final receipt = svc.awardSponsorshipKickback(
        campaignId: 'c', grossCredits: 10.0, dwellTimeSeconds: 1.0);
    expect(receipt.clientKickback, 0.0,
        reason: 'sponsorship mint pre-hydration');
    expect(svc.debitEscrow(amount: 1, referenceId: 'r'), isFalse,
        reason: 'escrow debit pre-hydration');
    expect(svc.spendCredits(amount: 1, reason: 'r'), isFalse);
    await svc.ready;
  });

  test('E-T2#3: concurrent genesis on one fresh db => ONE row', () async {
    final db = AppDatabase();
    addTearDown(db.close);
    final a = CreditService(db: db);
    final b = CreditService(db: db);
    await Future.wait([a.ready, b.ready]);
    await Future.wait([a.settled, b.settled]);

    final rows = await db.getCreditTransactions();
    final genesisRows =
        rows.where((r) => (r['description'] as String).contains('Genesis'));
    expect(genesisRows.length, 1,
        reason: 'deterministic genesis id must collapse the race');
    expect(a.balance, 100.0);
    expect(b.balance, 100.0);

    // Third instance must converge, not re-grant.
    final c = CreditService(db: db);
    await c.ready;
    expect(c.balance, 100.0);
    expect(
        c.transactions.where((t) => t.description.contains('Genesis')).length,
        1);
  });

  test('E-T2#4: hydration failure still grants genesis once, recoverable',
      () async {
    final db = _ReadFailsDb(failures: 1);
    addTearDown(db.close);
    final a = CreditService(db: db);
    await a.ready; // degraded path
    await a.settled;
    expect(a.balance, 100.0);
    expect(
        a.transactions.where((t) => t.description.contains('Genesis')).length,
        1);

    // "Restart": reads now succeed; persisted genesis seen; no second grant.
    final b = CreditService(db: db);
    await b.ready;
    await b.settled;
    expect(b.balance, 100.0);
    final rows = await db.getCreditTransactions();
    expect(
        rows
            .where((r) => (r['description'] as String).contains('Genesis'))
            .length,
        1);
  });

  test('E-T2#5: NET-attested end-to-end — spend burns attested', () async {
    final db = AppDatabase();
    addTearDown(db.close);
    await db.insertCreditTransaction(_txRow(
      id: 'attested_seed',
      timestamp: DateTime(2024, 1, 1),
      amount: 100.0,
      isAttested: true,
      type: 'storageReward',
    ));

    final svc = CreditService(db: db, initialBalance: 0.0);
    await svc.ready;
    expect(svc.attestedBalance, 100.0);
    expect(svc.balance, 100.0);

    expect(svc.spendCredits(amount: 40.0, reason: 'internal'), isTrue);
    expect(svc.attestedBalance, 60.0,
        reason: 'unattested=0 so debit must burn attested');
    expect(svc.balance, 60.0);

    expect(svc.spendCredits(amount: 60.0, reason: 'internal'), isTrue);
    expect(svc.attestedBalance, 0.0,
        reason: 'attested fully burned — double-egress must be dead');
    expect(svc.balance, 0.0);
    expect(svc.unattestedBalance, 0.0);
    await svc.settled;

    // Second instance replays the same ledger: attested must rebuild to 0.
    final svc2 = CreditService(db: db, initialBalance: 0.0);
    await svc2.ready;
    expect(svc2.attestedBalance, 0.0,
        reason: 'replay must reproduce net attested');
    expect(svc2.balance, 0.0);
  });

  test('E-T2#5b: attested preserved when unattested covers the debit',
      () async {
    final db = AppDatabase();
    addTearDown(db.close);
    final base = DateTime(2024, 1, 1);
    await db.insertCreditTransaction(
        _txRow(id: 'u50', timestamp: base, amount: 50.0));
    await db.insertCreditTransaction(_txRow(
        id: 'a100',
        timestamp: base.add(const Duration(minutes: 1)),
        amount: 100.0,
        isAttested: true));
    final svc = CreditService(db: db, initialBalance: 0.0);
    await svc.ready;
    expect(svc.balance, 150.0);
    expect(svc.attestedBalance, 100.0);
    expect(svc.unattestedBalance, 50.0);
    // Debit smaller than unattested must NOT touch attested.
    expect(svc.spendCredits(amount: 30.0, reason: 'internal'), isTrue);
    expect(svc.attestedBalance, 100.0);
    expect(svc.balance, 120.0);
    // Debit exceeding unattested burns attested for the remainder:
    // unattested=20 → burn 80 attested → attested 20, balance 20.
    expect(svc.spendCredits(amount: 100.0, reason: 'internal'), isTrue);
    expect(svc.attestedBalance, 20.0);
    expect(svc.balance, 20.0);
    await svc.settled;
    // Replay must agree exactly with the in-memory path.
    final svc2 = CreditService(db: db, initialBalance: 0.0);
    await svc2.ready;
    expect(svc2.attestedBalance, 20.0);
    expect(svc2.balance, 20.0);
  });

  test('E-T2#6a: replay [attested+100, debit-100, attested+50] => 50/50',
      () async {
    final db = AppDatabase();
    addTearDown(db.close);
    final base = DateTime(2024, 1, 1);
    await db.insertCreditTransaction(_txRow(
        id: 'a100',
        timestamp: base,
        amount: 100.0,
        isAttested: true));
    await db.insertCreditTransaction(_txRow(
        id: 'd100',
        timestamp: base.add(const Duration(minutes: 1)),
        amount: -100.0,
        type: 'priorityAccessDebit'));
    await db.insertCreditTransaction(_txRow(
        id: 'a50',
        timestamp: base.add(const Duration(minutes: 2)),
        amount: 50.0,
        isAttested: true));

    final svc = CreditService(db: db, initialBalance: 0.0);
    await svc.ready;
    expect(svc.balance, 50.0);
    expect(svc.attestedBalance, 50.0);
    expect(svc.unattestedBalance, 0.0);
  });

  test('E-T2#6b: replay overspend artifact [attested+100, debit-150] clamps',
      () async {
    final db = AppDatabase();
    addTearDown(db.close);
    final base = DateTime(2024, 1, 1);
    await db.insertCreditTransaction(_txRow(
        id: 'a100',
        timestamp: base,
        amount: 100.0,
        isAttested: true));
    await db.insertCreditTransaction(_txRow(
        id: 'd150',
        timestamp: base.add(const Duration(minutes: 1)),
        amount: -150.0,
        type: 'priorityAccessDebit'));

    final svc = CreditService(db: db, initialBalance: 0.0);
    await svc.ready;
    expect(svc.attestedBalance, greaterThanOrEqualTo(0.0));
    expect(svc.attestedBalance, 0.0);
    expect(svc.balance, 0.0);
    expect(svc.unattestedBalance, 0.0);
  });

  test('ADV: escrow debit also burns attested (no launder via escrow)',
      () async {
    final db = AppDatabase();
    addTearDown(db.close);
    await db.insertCreditTransaction(_txRow(
        id: 'a100',
        timestamp: DateTime(2024, 1, 1),
        amount: 100.0,
        isAttested: true));
    final svc = CreditService(db: db, initialBalance: 0.0);
    await svc.ready;
    expect(svc.debitEscrow(amount: 100.0, referenceId: 'b1'), isTrue);
    expect(svc.attestedBalance, 0.0,
        reason: 'escrow hold must burn attested too');
    expect(svc.balance, 0.0);
    // Then a bounty payout restores unattested, NOT attested.
    expect(svc.awardBountyEscrow(amount: 100.0, bountyId: 'b1', cid: 'c'),
        100.0);
    expect(svc.attestedBalance, 0.0);
    expect(svc.balance, 100.0);
  });
}
