// Safety 6c — releaseEscrow: the cancel/refund half of debitEscrow.
// Covers: exact-once refund, replay refusal, restart durability via the
// deterministic tx_escrow_release_* row id, unknown/empty referenceId
// refusal without id-burn, in-memory operation, and the hold-vs-spend
// distinction (a plain debit under the same referenceId is not an
// escrow hold). Plus the Safety 6f txId monotonicity check.
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart' hide CreditTransaction;
import 'package:alexandria/services/credits/credit_service.dart';

void main() {
  group('releaseEscrow (Safety 6c — escrow is no longer a one-way burn)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    CreditService svc() => CreditService(db: db, initialBalance: 0.0);

    /// Seed the wallet with self-certified value so an escrow hold has
    /// something to draw on.
    void fund(CreditService s, double amount) {
      s.awardVerificationCredits(action: 'seed', targetId: 't', amount: amount);
    }

    test(
        'refunds the ORIGINAL debited amount exactly once — replay '
        'refused', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      expect(s.debitEscrow(amount: 20.0, referenceId: 'bounty_1'), isTrue);
      expect(s.balance, 30.0);

      expect(await s.releaseEscrow(referenceId: 'bounty_1'), 20.0);
      expect(s.balance, 50.0);

      // Replay: the in-memory dedup set refuses — no second mint.
      expect(await s.releaseEscrow(referenceId: 'bounty_1'), 0.0);
      expect(s.balance, 50.0);

      // The persisted release row carries the deterministic id — the
      // durable "already released" record.
      await s.settled;
      final rows = await db.getCreditTransactions();
      final release =
          rows.singleWhere((r) => r['id'] == 'tx_escrow_release_bounty_1');
      expect(release['amount'], 20.0);
      expect(release['referenceId'], 'bounty_1');
      expect(release['isAttested'], isFalse);
      expect(release['description'], contains('Escrow Release (bounty_1)'));
    });

    test(
        'restart durability: a fresh CreditService on the same db '
        'refuses a re-release (deterministic row id)', () async {
      final first = svc();
      await first.ready;
      fund(first, 50.0);
      first.debitEscrow(amount: 20.0, referenceId: 'bounty_2');
      expect(await first.releaseEscrow(referenceId: 'bounty_2'), 20.0);
      await first.settled;

      // "Restart": fresh instance, same database. Hydration replays the
      // hold AND the release (net-zero) and rebuilds
      // _releasedEscrowIds from the persisted tx_escrow_release_* row.
      final second = svc();
      await second.ready;
      expect(second.balance, 50.0);
      expect(await second.releaseEscrow(referenceId: 'bounty_2'), 0.0,
          reason: 'restart must not re-refund: the persisted row id '
              'tx_escrow_release_bounty_2 is the durable dedup record');
      expect(second.balance, 50.0);
    });

    test('a persisted hold survives restart and remains releasable', () async {
      final first = svc();
      await first.ready;
      fund(first, 50.0);
      first.debitEscrow(amount: 20.0, referenceId: 'bounty_3');
      await first.settled;

      final second = svc();
      await second.ready;
      expect(second.balance, 30.0);
      expect(await second.releaseEscrow(referenceId: 'bounty_3'), 20.0);
      expect(second.balance, 50.0);
    });

    test(
        'refuses an unknown referenceId — and the refused probe does '
        'NOT consume the id (a later real hold still releases)', () async {
      final s = svc();
      await s.ready;
      expect(await s.releaseEscrow(referenceId: 'bounty_late'), 0.0);

      // The escrow is posted AFTER the probe — refusal gates run before
      // the dedup set-add, so the probe did not burn the id.
      fund(s, 50.0);
      expect(s.debitEscrow(amount: 10.0, referenceId: 'bounty_late'), isTrue);
      expect(await s.releaseEscrow(referenceId: 'bounty_late'), 10.0);
      expect(await s.releaseEscrow(referenceId: 'bounty_late'), 0.0);
    });

    test('refuses an empty referenceId', () async {
      final s = svc();
      await s.ready;
      expect(await s.releaseEscrow(referenceId: ''), 0.0);
    });

    test(
        'a plain spendCredits debit under the same referenceId is not '
        'an escrow hold and is not releasable', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      expect(
          s.spendCredits(
              amount: 15.0, reason: 'priority pin', referenceId: 'bounty_4'),
          isTrue);
      expect(await s.releaseEscrow(referenceId: 'bounty_4'), 0.0);
      expect(s.balance, 35.0);
    });

    test('two holds under one referenceId release their sum once', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      s.debitEscrow(amount: 10.0, referenceId: 'bounty_5');
      s.debitEscrow(amount: 5.0, referenceId: 'bounty_5');
      expect(s.balance, 35.0);
      expect(await s.releaseEscrow(referenceId: 'bounty_5'), 15.0);
      expect(s.balance, 50.0);
      expect(await s.releaseEscrow(referenceId: 'bounty_5'), 0.0);
    });

    test('works without a database (pure in-memory mode)', () async {
      final s = CreditService(initialBalance: 30.0);
      await s.ready;
      expect(s.debitEscrow(amount: 10.0, referenceId: 'b1'), isTrue);
      expect(s.balance, 20.0);
      expect(await s.releaseEscrow(referenceId: 'b1'), 10.0);
      expect(s.balance, 30.0);
      expect(await s.releaseEscrow(referenceId: 'b1'), 0.0);
      expect(await s.releaseEscrow(referenceId: 'nope'), 0.0);
    });

    test(
        'release call racing hydration still lands correctly — it '
        'awaits hydration internally', () async {
      // Seed a hold, settle, then release from a FRESH service without
      // awaiting ready first — releaseEscrow awaits _hydrated itself.
      final first = svc();
      await first.ready;
      fund(first, 50.0);
      first.debitEscrow(amount: 20.0, referenceId: 'bounty_6');
      await first.settled;

      final second = svc();
      // No `await second.ready` — the call itself must wait for the
      // persisted ledger rather than refuse on phantom state.
      expect(await second.releaseEscrow(referenceId: 'bounty_6'), 20.0);
      expect(second.balance, 50.0);
    });
  });

  group('txId generation (Safety 6f — monotonic per-process seq)', () {
    test('rapid _recordTransaction calls produce distinct ids', () async {
      final s = CreditService(initialBalance: 0.0);
      await s.ready;
      // Back-to-back mints — under the old micros+_transactions.length
      // scheme, identical micros on successive rows were safe only
      // within one list; the static seq makes collision impossible
      // in-process regardless of timing.
      s.awardVerificationCredits(action: 'a', targetId: 't1', amount: 1);
      s.awardVerificationCredits(action: 'a', targetId: 't2', amount: 1);
      s.awardVerificationCredits(action: 'a', targetId: 't3', amount: 1);
      final ids = s.transactions.map((t) => t.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids.every((id) => id.startsWith('tx_')), isTrue);
    });

    test(
        'ids stay distinct ACROSS service instances in one process — '
        'the seq never resets to a known value', () async {
      final a = CreditService(initialBalance: 0.0);
      final b = CreditService(initialBalance: 0.0);
      await a.ready;
      await b.ready;
      a.awardVerificationCredits(action: 'a', targetId: 't', amount: 1);
      b.awardVerificationCredits(action: 'a', targetId: 't', amount: 1);
      // Old scheme: both lists were length 0 — a shared micros stamp
      // would collide and the second insertOrIgnore would drop a real
      // ledger row. The process-wide seq suffix can never collide.
      expect(a.transactions.first.id, isNot(b.transactions.first.id));
    });
  });
}
