// Tests for the schema-v8 sufficient attested-egress gate:
// `insertAttestedDebitIfCovered` now sums scoped attested MINTS minus
// every durable `burned_attested` — the same mints−burns quantity the
// service's in-memory `_attestedBurned` cache tracks — so the gate is
// SUFFICIENT, not merely necessary (WORKING_ON residual closure).
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart';

Map<String, dynamic> _tx({
  required String id,
  required double amount,
  bool isAttested = false,
  String type = 'storageReward',
  String? attestedPubkey,
  double burnedAttested = 0.0,
}) =>
    {
      'id': id,
      'timestamp': DateTime.now(),
      'type': type,
      'amount': amount,
      'description': 'seeded $id',
      'hash': 'h_$id',
      'isAttested': isAttested,
      'attestedPubkey': attestedPubkey,
      'burnedAttested': burnedAttested,
    };

Map<String, dynamic> _debit(String id, double amount) => _tx(
      id: id,
      amount: -amount,
      isAttested: true,
      type: 'priorityAccessDebit',
    );

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  group('insertAttestedDebitIfCovered (sufficient since v8)', () {
    test(
        'an ordinary debit\'s recorded attested burn is subtracted — '
        'the old necessary-only sum would have permitted', () async {
      // 100 attested minted (unscoped bucket) + an ordinary debit that
      // burned 70 attested. Durable truth: 30 attested remain.
      await db.insertCreditTransaction(
          _tx(id: 'm1', amount: 100.0, isAttested: true));
      await db.insertCreditTransaction(_tx(
          id: 'ord1',
          amount: -70.0,
          type: 'priorityAccessDebit',
          burnedAttested: 70.0));

      // The pre-v8 formula saw only the minted sum (100) and would
      // have permitted 40 — the sufficient gate must refuse.
      expect(
          await db.insertAttestedDebitIfCovered(_debit('eg_over', 40.0),
              heldAttestedPubkeys: const {}, requiredCredits: 40.0),
          isFalse);
      expect(await db.hasCreditTransaction('eg_over'), isFalse,
          reason: 'a refused gate writes nothing');

      // 30 is exactly covered.
      expect(
          await db.insertAttestedDebitIfCovered(_debit('eg_ok', 30.0),
              heldAttestedPubkeys: const {}, requiredCredits: 30.0),
          isTrue);
    });

    test(
        'the inserted egress row is stamped with its own burn, so the '
        'gate stays sufficient for the NEXT writer', () async {
      await db.insertCreditTransaction(
          _tx(id: 'm1', amount: 50.0, isAttested: true));
      expect(
          await db.insertAttestedDebitIfCovered(_debit('eg1', 20.0),
              heldAttestedPubkeys: const {}, requiredCredits: 20.0),
          isTrue);

      final rows = await db.getCreditTransactions(limit: 10);
      final eg = rows.firstWhere((r) => r['id'] == 'eg1');
      expect(eg['burnedAttested'], 20.0,
          reason: 'the egress row burns attested in full — stamping it '
              'keeps the durable sum honest');

      // Only 30 attested now remain: a 31 egress must refuse even
      // though minted(50) alone looks sufficient.
      expect(
          await db.insertAttestedDebitIfCovered(_debit('eg2', 31.0),
              heldAttestedPubkeys: const {}, requiredCredits: 31.0),
          isFalse);
      expect(
          await db.insertAttestedDebitIfCovered(_debit('eg2', 30.0),
              heldAttestedPubkeys: const {}, requiredCredits: 30.0),
          isTrue);
    });

    test(
        'prover-key scoping still applies to mints; burns are '
        'wallet-wide', () async {
      // 60 minted under held key k1, 60 under foreign key kX (not
      // held), 20 unscoped legacy, and an ordinary debit that burned
      // 30 attested (burns draw on the all-keys pool).
      await db.insertCreditTransaction(_tx(
          id: 'm_k1', amount: 60.0, isAttested: true, attestedPubkey: 'k1'));
      await db.insertCreditTransaction(_tx(
          id: 'm_kx', amount: 60.0, isAttested: true, attestedPubkey: 'kx'));
      await db.insertCreditTransaction(
          _tx(id: 'm_legacy', amount: 20.0, isAttested: true));
      await db.insertCreditTransaction(_tx(
          id: 'ord1',
          amount: -30.0,
          type: 'priorityAccessDebit',
          burnedAttested: 30.0));

      // Held {k1}: mints 60 + 20 = 80, minus burns 30 → 50 available.
      expect(
          await db.insertAttestedDebitIfCovered(_debit('eg_a', 50.0),
              heldAttestedPubkeys: const {'k1'}, requiredCredits: 50.0),
          isTrue);
      expect(
          await db.insertAttestedDebitIfCovered(_debit('eg_b', 1.0),
              heldAttestedPubkeys: const {'k1'}, requiredCredits: 1.0),
          isFalse,
          reason: 'kX\'s mints do not back egress for keys not held');

      // Held {k1, kx}: mints 140 − (30 + the 50 eg_a just burned) → 60.
      expect(
          await db.insertAttestedDebitIfCovered(_debit('eg_c', 60.0),
              heldAttestedPubkeys: const {'k1', 'kx'}, requiredCredits: 60.0),
          isTrue);
    });

    test('the balance floor still applies (available <= ledger net)', () async {
      // Attested mint 100 but a huge ordinary debit left net 10 — the
      // ledger itself can't cover 20 regardless of burn attribution.
      await db.insertCreditTransaction(
          _tx(id: 'm1', amount: 100.0, isAttested: true));
      await db.insertCreditTransaction(_tx(
          id: 'ord1',
          amount: -90.0,
          type: 'priorityAccessDebit',
          burnedAttested: 90.0));
      expect(
          await db.insertAttestedDebitIfCovered(_debit('eg', 20.0),
              heldAttestedPubkeys: const {}, requiredCredits: 20.0),
          isFalse);
      expect(
          await db.insertAttestedDebitIfCovered(_debit('eg', 10.0),
              heldAttestedPubkeys: const {}, requiredCredits: 10.0),
          isTrue);
    });

    test('a duplicate id loses the CAS even when covered', () async {
      await db.insertCreditTransaction(
          _tx(id: 'm1', amount: 100.0, isAttested: true));
      expect(
          await db.insertAttestedDebitIfCovered(_debit('dup', 10.0),
              heldAttestedPubkeys: const {}, requiredCredits: 10.0),
          isTrue);
      // Same id again — INSERT OR IGNORE drops it, changes() reports 0.
      expect(
          await db.insertAttestedDebitIfCovered(_debit('dup', 10.0),
              heldAttestedPubkeys: const {}, requiredCredits: 10.0),
          isFalse);
    });
  });

  group('burned_attested plumbing', () {
    test(
        'insertCreditTransaction persists the column and reads it '
        'back; omitted data defaults to 0', () async {
      await db.insertCreditTransaction(_tx(
          id: 'with_burn',
          amount: -15.0,
          type: 'priorityAccessDebit',
          burnedAttested: 7.5));
      await db.insertCreditTransaction(
          _tx(id: 'no_burn', amount: 5.0)..remove('burnedAttested'));

      final rows = await db.getCreditTransactions(limit: 10);
      expect(rows.firstWhere((r) => r['id'] == 'with_burn')['burnedAttested'],
          7.5);
      expect(
          rows.firstWhere((r) => r['id'] == 'no_burn')['burnedAttested'], 0.0);
    });
  });
}
