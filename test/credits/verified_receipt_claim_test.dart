// claimVerifiedReceipt — the only path that mints attested (egress-grade)
// value (ALX-010). Locks down the guard chain, the atomic-claim dedup,
// workType mapping and the daily-cap safety floor.
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart'
    hide CreditTransaction, WorkReceipt;
import 'package:alexandria/services/credits/credit_models.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/work_receipt.dart';

WorkReceipt _receipt({
  String workType = 'storage',
  String proverPubkey = 'prover_key_hex',
  String verifierPubkey = 'verifier_key_hex',
  String verifierSig = 'c2ln', // non-empty: isVerifierSigned
  double amount = 25.0,
  int? expiresAt,
}) {
  return WorkReceipt.issue(
    workType: workType,
    proverPubkey: proverPubkey,
    verifierPubkey: verifierPubkey,
    cid: 'bafy_claim_test',
    chunkIndices: const [0, 1],
    challengeNonce: 'ab' * 16,
    responseTag: 'cd' * 32,
    workUnits: 4096,
    amount: amount,
    epoch: WorkReceipt.epochFor(DateTime.now()),
    expiresAt: expiresAt ??
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    verifierSig: verifierSig,
  );
}

void main() {
  group('CreditService.claimVerifiedReceipt (ALX-010 attested mint)', () {
    late AppDatabase db;
    late CreditService svc;

    setUp(() async {
      db = AppDatabase();
      svc = CreditService(db: db, initialBalance: 0.0);
      await svc.ready;
    });

    tearDown(() async {
      await db.close();
    });

    Future<WorkReceipt> persist(WorkReceipt r) async {
      await db.insertWorkReceipt(r.toDbMap());
      return r;
    }

    test('foreign verifier-signed receipt mints attested credit', () async {
      final r = await persist(
          _receipt(proverPubkey: 'local_key_hex', amount: 25.0));
      final minted =
          await svc.claimVerifiedReceipt(r, localPubkeyHex: 'local_key_hex');

      expect(minted, 25.0);
      expect(svc.balance, 25.0);
      expect(svc.attestedBalance, 25.0);
      expect(svc.unattestedBalance, 0.0);
      expect(svc.totalStorageEarned, 25.0);

      final tx = svc.transactions
          .firstWhere((t) => t.referenceId == r.receiptId);
      expect(tx.isAttested, isTrue);
      expect(tx.type, CreditType.storageReward);

      // The receipt row is consumed.
      final row = await db.getWorkReceipt(r.receiptId);
      expect(row!['spent'], isTrue);
    });

    test('replay loses the CAS — a receipt can only ever mint once',
        () async {
      final r = await persist(_receipt(proverPubkey: 'local', amount: 25.0));
      expect(await svc.claimVerifiedReceipt(r, localPubkeyHex: 'local'),
          25.0);
      // Second claim: CAS loses (row already spent) -> 0, nothing mints.
      expect(await svc.claimVerifiedReceipt(r, localPubkeyHex: 'local'),
          0.0);
      expect(await svc.claimVerifiedReceipt(r.markSpent(),
          localPubkeyHex: 'local'), 0.0);
      expect(svc.attestedBalance, 25.0);
      expect(svc.balance, 25.0);
    });

    test('receipt the local node signed itself never mints attested value',
        () async {
      final r = await persist(_receipt(
        proverPubkey: 'other_prover',
        verifierPubkey: 'local_key_hex',
      ));
      expect(
        await svc.claimVerifiedReceipt(r, localPubkeyHex: 'local_key_hex'),
        0.0,
      );
      expect(svc.attestedBalance, 0.0);
      // And the receipt is NOT consumed — it was never claimed.
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('self-issued receipt (prover == verifier) is refused', () async {
      final r = await persist(_receipt(
        proverPubkey: 'same_key',
        verifierPubkey: 'same_key',
      ));
      expect(await svc.claimVerifiedReceipt(r, localPubkeyHex: 'local'),
          0.0);
      expect(svc.attestedBalance, 0.0);
    });

    test('receipt naming a FOREIGN prover is refused — claim theft '
        'protection', () async {
      // A held artifact naming prover X is X's claim instrument, not
      // ours: the local node must never mint it (REV1 C3).
      final r = await persist(_receipt(
        proverPubkey: 'foreign_prover',
        verifierPubkey: 'verifier_key_hex',
        amount: 25.0,
      ));
      expect(await svc.claimVerifiedReceipt(r, localPubkeyHex: 'local'),
          0.0);
      expect(svc.attestedBalance, 0.0);
      // Not consumed — it still belongs to the named prover.
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('unsigned receipt is refused', () async {
      final r = await persist(_receipt(verifierSig: ''));
      expect(await svc.claimVerifiedReceipt(r, localPubkeyHex: 'local'),
          0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('expired receipt is refused', () async {
      final r = await persist(_receipt(
        expiresAt:
            DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
      ));
      expect(await svc.claimVerifiedReceipt(r, localPubkeyHex: 'local'),
          0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('receipt missing from the ledger is refused', () async {
      final r = _receipt(); // never persisted
      expect(await svc.claimVerifiedReceipt(r, localPubkeyHex: 'local'),
          0.0);
      expect(svc.balance, 0.0);
    });

    test('in-memory service has no CAS — claim is refused', () async {
      final mem = CreditService(initialBalance: 0.0);
      await mem.ready;
      expect(await mem.claimVerifiedReceipt(_receipt(), localPubkeyHex: 'l'),
          0.0);
    });

    test('workType maps to the matching credit type', () async {
      final compute = await persist(_receipt(
          workType: 'compute', proverPubkey: 'l', amount: 10.0));
      expect(await svc.claimVerifiedReceipt(compute, localPubkeyHex: 'l'),
          10.0);
      expect(
          svc.transactions
              .firstWhere((t) => t.referenceId == compute.receiptId)
              .type,
          CreditType.computeReward);

      final verify = await persist(_receipt(
          workType: 'verification', proverPubkey: 'l', amount: 10.0));
      expect(await svc.claimVerifiedReceipt(verify, localPubkeyHex: 'l'),
          10.0);
      expect(
          svc.transactions
              .firstWhere((t) => t.referenceId == verify.receiptId)
              .type,
          CreditType.verificationReward);

      expect(svc.totalComputeEarned, 10.0);
      expect(svc.totalVerificationEarned, 10.0);
      expect(svc.attestedBalance, 20.0);
    });

    test('attested mints still respect the daily cap (safety floor)',
        () async {
      // storageReward daily cap is 200 — a 250-credit receipt clamps.
      final r =
          await persist(_receipt(proverPubkey: 'local', amount: 250.0));
      final minted =
          await svc.claimVerifiedReceipt(r, localPubkeyHex: 'local');
      expect(minted, 200.0);
      expect(svc.attestedBalance, 200.0);
      // The receipt is consumed even though the full amount didn't mint —
      // anti-replay: the residual is burned, never re-claimable.
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isTrue);

      // A second receipt the same day finds the cap exhausted: mints
      // nothing, and is still consumed.
      final r2 =
          await persist(_receipt(proverPubkey: 'local', amount: 10.0));
      expect(await svc.claimVerifiedReceipt(r2, localPubkeyHex: 'local'),
          0.0);
      expect((await db.getWorkReceipt(r2.receiptId))!['spent'], isTrue);
    });
  });

  group('CreditTransaction.computeHash', () {
    test('emits the full-width sha256 hex (64 chars)', () {
      final hash = CreditTransaction.computeHash(
        id: 'tx_1',
        timestamp: DateTime(2026, 1, 1),
        type: CreditType.storageReward,
        amount: 5.0,
        description: 'full width hash test',
      );
      expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });
}
