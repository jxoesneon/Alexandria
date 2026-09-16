// Regression proofs for the durable-first credit mutators (optimistic-
// return residual closure) and the schema-v8 `burned_attested` durable
// burn attribution.
//
// The contract under test: for every `*Durable` mutator — and for the
// reordered `releaseEscrow` — a returned success provably corresponds to
// a durably-committed ledger row at return time (no `settled` wait, no
// post-hoc reconcile). The synchronous UI-convenience forms keep their
// documented optimistic semantics.
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart' hide CreditTransaction;
import 'package:alexandria/services/credits/credit_service.dart';

Map<String, dynamic> _txRow({
  required String id,
  required double amount,
  bool isAttested = false,
  String type = 'storageReward',
  String description = 'seeded',
  String? referenceId,
  String? attestedPubkey,
  double burnedAttested = 0.0,
}) =>
    {
      'id': id,
      'timestamp': DateTime.now(),
      'type': type,
      'amount': amount,
      'description': description,
      'referenceId': referenceId,
      'hash': 'h_$id',
      'isAttested': isAttested,
      'attestedPubkey': attestedPubkey,
      'burnedAttested': burnedAttested,
    };

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  CreditService svc({double initialBalance = 0.0}) =>
      CreditService(db: db, initialBalance: initialBalance);

  void fund(CreditService s, double amount) {
    s.awardVerificationCredits(action: 'seed', targetId: 't', amount: amount);
  }

  group('spendCreditsDurable', () {
    test(
        'returned true ⇒ the debit row is ALREADY durable (no settled '
        'wait)', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);

      expect(await s.spendCreditsDurable(amount: 20.0, reason: 'durable spend'),
          isTrue);
      expect(s.balance, 30.0);

      // The row the debit just wrote — durable at return time, not after
      // a settle window.
      final debitId = s.transactions.firstWhere((t) => t.amount == -20.0).id;
      expect(await db.hasCreditTransaction(debitId), isTrue,
          reason: 'durable mutator: success means the row is committed');
    });

    test('refusals mutate nothing and write nothing', () async {
      final s = svc();
      await s.ready;
      fund(s, 10.0);
      await s.settled;
      final rowCount = (await db.getCreditTransactions(limit: 1000)).length;

      expect(
          await s.spendCreditsDurable(amount: 50.0, reason: 'over'), isFalse);
      expect(await s.spendCreditsDurable(amount: 0.0, reason: 'zero'), isFalse);
      expect(await s.spendCreditsDurable(amount: double.nan, reason: 'nan'),
          isFalse);
      expect(s.balance, 10.0);
      expect((await db.getCreditTransactions(limit: 1000)).length, rowCount);
    });

    test(
        'ordinary debit persists its attested burn into '
        'burned_attested (schema v8)', () async {
      // 100 attested (unscoped) + 30 self-certified: a 60 ordinary
      // debit burns 30 attested under the unattested-first rule.
      await db.insertCreditTransaction(
          _txRow(id: 'att_mint', amount: 100.0, isAttested: true));
      final s = svc();
      await s.ready;
      fund(s, 30.0);
      await s.settled;

      expect(await s.spendCreditsDurable(amount: 60.0, reason: 'mixed burn'),
          isTrue);
      expect(s.attestedBalance, 70.0);

      final rows = await db.getCreditTransactions(limit: 1000);
      final debit = rows.firstWhere((r) => r['amount'] == -60.0);
      expect(debit['burnedAttested'], 30.0,
          reason: 'the durable gate sums this column — it must carry '
              'the same burn the in-memory rule computed');
    });

    test('attested debit persists burned_attested = full amount', () async {
      await db.insertCreditTransaction(
          _txRow(id: 'att_mint', amount: 100.0, isAttested: true));
      final s = svc();
      await s.ready;

      expect(
          await s.spendCreditsDurable(
              amount: 40.0, reason: 'egress', isAttested: true),
          isTrue);
      expect(s.attestedBalance, 60.0);
      final rows = await db.getCreditTransactions(limit: 1000);
      final debit = rows
          .firstWhere((r) => r['amount'] == -40.0 && r['isAttested'] == true);
      expect(debit['burnedAttested'], 40.0);
    });

    test(
        'the durable gate refuses what a STALE in-memory view would '
        'permit — contrast with the optimistic sync path', () async {
      // Shared ledger: 100 unscoped attested mint.
      await db.insertCreditTransaction(
          _txRow(id: 'att_mint', amount: 100.0, isAttested: true));
      final a = svc();
      final b = svc();
      await a.ready;
      await b.ready;
      expect(a.attestedBalance, 100.0);
      expect(b.attestedBalance, 100.0);

      // Instance A durably egresses 80 — B's in-memory view stays at
      // 100 (stale), while the durable pool is now 20.
      expect(
          await a.spendCreditsDurable(
              amount: 80.0, reason: 'A egress', isAttested: true),
          isTrue);
      expect(b.attestedBalance, 100.0,
          reason: 'fixture: B has not replayed A\'s burn');

      // B's fast path passes (100 >= 60) but the durable gate computes
      // mints(100) − durable burns(80) = 20 < 60 → refusal, NOTHING
      // mutates, no artifact emitted. The sync form would have returned
      // true and reconciled after the fact.
      expect(
          await b.spendCreditsDurable(
              amount: 60.0, reason: 'B egress', isAttested: true),
          isFalse);
      expect(b.balance, 100.0);
      expect(b.attestedBalance, 100.0);
      // And nothing was persisted for B's refused debit.
      expect(await db.getLedgerBalanceSum(), 20.0);
    });

    test('pure in-memory mode still works (no db attached)', () async {
      final s = CreditService(initialBalance: 100.0);
      await s.ready;
      expect(await s.spendCreditsDurable(amount: 25.0, reason: 'mem'), isTrue);
      expect(s.balance, 75.0);
    });
  });

  group('debitEscrowDurable', () {
    test(
        'returned true ⇒ the hold row is durable; release finds it '
        'without any settle wait', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);

      expect(
          await s.debitEscrowDurable(amount: 20.0, referenceId: 'b1'), isTrue);
      expect(s.balance, 30.0);
      final holds = await db.getEscrowHoldRows('b1');
      expect(holds, hasLength(1),
          reason: 'the hold must be durable at return — a crash now '
              'must not strand the debit in memory only');
      expect(holds.single['amount'], -20.0);
    });

    test(
        'refusals: empty referenceId, non-finite, overdraw — nothing '
        'persisted', () async {
      final s = svc();
      await s.ready;
      fund(s, 10.0);
      expect(
          await s.debitEscrowDurable(amount: 5.0, referenceId: '  '), isFalse);
      expect(await s.debitEscrowDurable(amount: double.nan, referenceId: 'n'),
          isFalse);
      expect(
          await s.debitEscrowDurable(amount: 99.0, referenceId: 'o'), isFalse);
      expect(s.balance, 10.0);
      expect(await db.getEscrowHoldRows('o'), isEmpty);
    });
  });

  group('awardBountyEscrowDurable', () {
    test(
        'returned amount ⇒ tx_bounty_payout_<id> is durable; dedup '
        'across instances via the CAS', () async {
      final a = svc();
      // B hydrates BEFORE the payout so its in-memory dedup set cannot
      // know about it — the deterministic-id CAS is what refuses.
      final b = svc();
      await a.ready;
      await b.ready;
      expect(
          await a.awardBountyEscrowDurable(
              amount: 10.0, bountyId: 'b1', cid: 'c'),
          10.0);
      expect(a.balance, 10.0);
      expect(await db.hasCreditTransaction('tx_bounty_payout_b1'), isTrue,
          reason: 'the payout row is the durable dedup record — it must '
              'exist at return, not after a settle window');

      // The sibling instance that never saw the payout loses the CAS —
      // no settle, no reconcile, a plain 0.0.
      expect(
          await b.awardBountyEscrowDurable(
              amount: 10.0, bountyId: 'b1', cid: 'c'),
          0.0);
      expect(b.isBountyPayoutRecorded('b1'), isTrue,
          reason: 'the loser absorbs the durable truth');
      expect(await db.getLedgerBalanceSum(), 10.0,
          reason: 'exactly one payout became canonical');
    });

    test(
        'refuses a bountyId with a durable release tombstone it never '
        'saw hydrate (REV4a F1, durable)', () async {
      final s = svc();
      await s.ready;
      // Simulate an out-of-band release landing AFTER hydration.
      await db.insertCreditTransaction(_txRow(
          id: 'tx_escrow_release_dead',
          amount: 20.0,
          type: 'priorityAccessDebit',
          description: 'Escrow Release (dead)',
          referenceId: 'dead'));
      expect(
          await s.awardBountyEscrowDurable(
              amount: 20.0, bountyId: 'dead', cid: 'c'),
          0.0,
          reason: 'paying a durably-released escrow mints from nothing');
      expect(s.isEscrowReleased('dead'), isTrue);
      expect(await db.hasCreditTransaction('tx_bounty_payout_dead'), isFalse);
    });

    test('refusal gates run before any set is consumed', () async {
      final s = svc();
      await s.ready;
      expect(
          await s.awardBountyEscrowDurable(
              amount: 0.0, bountyId: 'b9', cid: 'c'),
          0.0);
      expect(
          await s.awardBountyEscrowDurable(amount: 5.0, bountyId: '', cid: 'c'),
          0.0);
      // A legit payout for the probed id still lands.
      expect(
          await s.awardBountyEscrowDurable(
              amount: 5.0, bountyId: 'b9', cid: 'c'),
          5.0);
    });
  });

  group('releaseEscrow (durable-first reorder)', () {
    test('returned refund ⇒ tx_escrow_release_<id> is already durable',
        () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      expect(
          await s.debitEscrowDurable(amount: 20.0, referenceId: 'r'), isTrue);

      expect(await s.releaseEscrow(referenceId: 'r'), 20.0);
      expect(await db.hasCreditTransaction('tx_escrow_release_r'), isTrue,
          reason: 'the refund must correspond to a committed row at '
              'return — the residual required exactly this');
      expect(s.balance, 50.0);
    });

    test(
        'cross-instance: a sibling finds the durable hold, releases '
        'it once, and the first instance then refuses via the '
        'tombstone', () async {
      final a = svc();
      await a.ready;
      fund(a, 50.0);
      await a.settled;
      final b = svc();
      await b.ready;

      // A posts the hold durably; B never replayed it (hydrated
      // earlier), but the release path's durable hold listing finds it.
      expect(
          await a.debitEscrowDurable(amount: 20.0, referenceId: 'x'), isTrue);
      expect(await b.releaseEscrow(referenceId: 'x'), 20.0,
          reason: 'B must see A\'s durable hold via getEscrowHoldRows');
      expect(b.balance, 70.0);

      // A's own release attempt now hits the durable tombstone.
      expect(await a.releaseEscrow(referenceId: 'x'), 0.0);
      // Exactly one release row exists.
      final rows = await db.getCreditTransactions(limit: 1000);
      expect(rows.where((r) => r['id'] == 'tx_escrow_release_x').length, 1);
      // Net ledger: 50 mint − 20 hold + 20 refund = 50.
      expect(await db.getLedgerBalanceSum(), 50.0);
    });

    test(
        'hold rows written by the SYNC optimistic path stay '
        'releasable and still carry their burn attribution', () async {
      await db.insertCreditTransaction(
          _txRow(id: 'att_mint', amount: 100.0, isAttested: true));
      final s = svc();
      await s.ready;
      expect(s.debitEscrow(amount: 60.0, referenceId: 'mix'), isTrue);
      await s.settled;
      final holds = await db.getEscrowHoldRows('mix');
      expect(holds, hasLength(1));
      expect(holds.single['burnedAttested'], 60.0,
          reason: 'sync hold burned attested (unattested pool was 0) — '
              'the row must record it durably');
      expect(await s.releaseEscrow(referenceId: 'mix'), 60.0);
      expect(s.attestedBalance, 40.0,
          reason: 'release refunds balance but does not un-burn the '
              'attested pool — semantics unchanged');
    });
  });

  group('replay/persistence parity (schema v8)', () {
    test('rehydrated attestedBalance equals mints − durable burns', () async {
      await db.insertCreditTransaction(
          _txRow(id: 'att_mint', amount: 100.0, isAttested: true));
      final s = svc();
      await s.ready;
      fund(s, 30.0);
      // Ordinary debit burns 30 attested; egress burns 20 more.
      expect(await s.spendCreditsDurable(amount: 60.0, reason: 'i'), isTrue);
      expect(
          await s.spendCreditsDurable(
              amount: 20.0, reason: 'e', isAttested: true),
          isTrue);
      expect(s.attestedBalance, 50.0);

      // A fresh instance replays the same ledger — the durable burn
      // column and the replay rule agree row-for-row.
      final s2 = svc();
      await s2.ready;
      expect(s2.attestedBalance, 50.0);
      expect(s2.balance, s.balance);
    });
  });
}
