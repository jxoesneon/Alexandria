// SCRATCH EVALUATOR FILE — adversarial REV4a pass over the landed diff:
//   * CreditService.releaseEscrow (Safety 6c escrow refund)
//   * KnownLocalPubkeysResolver rotation self-vouch guard (Safety item 3)
//   * _txSeq monotonic txId suffix (Safety 6f)
// Every test asserts the SECURE expectation — a FAILURE marks a LIVE
// exploit; passes mark dead classes. Do not promote as-is.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart'
    hide CreditTransaction, WorkReceipt;
import 'package:alexandria/services/agent/beacon_models.dart'
    show bytesToHex, hexToBytes;
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/work_receipt.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

/// In-memory SecureStorageService for IdentityService rotation tests.
class _FakeSecureStorage implements SecureStorageService {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);

  @override
  Future<void> deleteAll() async => data.clear();

  @override
  Future<bool> containsKey(String key) async => data.containsKey(key);
}

/// Db that parks escrow-release row inserts while [armed] — models the
/// crash window between releaseEscrow's in-memory refund and the durable
/// dedup row landing. With [throwWhenArmed] the write errors instead of
/// parking — models a store that loses the release row outright.
class _GatedReleaseInsertDb extends AppDatabase {
  final Completer<void> gate = Completer<void>();
  bool armed = false;
  bool throwWhenArmed = false;

  @override
  Future<void> insertCreditTransaction(Map<String, dynamic> data) async {
    if (armed && (data['id'] as String).startsWith('tx_escrow_release_')) {
      if (throwWhenArmed) {
        throw StateError('simulated release-row write loss');
      }
      await gate.future;
    }
    return super.insertCreditTransaction(data);
  }

  @override
  Future<bool> insertCreditTransactionIfAbsent(
      Map<String, dynamic> data) async {
    // The release row is now persisted through the ifAbsent CAS —
    // gate the same crash window there.
    if (armed && (data['id'] as String).startsWith('tx_escrow_release_')) {
      if (throwWhenArmed) {
        throw StateError('simulated release-row write loss');
      }
      await gate.future;
    }
    return super.insertCreditTransactionIfAbsent(data);
  }
}

Map<String, dynamic> _txRow({
  required String id,
  required DateTime timestamp,
  required double amount,
  String type = 'verificationReward',
  String description = 'seeded',
  String? referenceId,
  bool isAttested = false,
}) =>
    {
      'id': id,
      'timestamp': timestamp,
      'type': type,
      'amount': amount,
      'description': description,
      'referenceId': referenceId,
      'hash': 'h_$id',
      'isAttested': isAttested,
    };

void main() {
  final algorithm = Ed25519();
  late SimpleKeyPair keyA;
  late String pubA;
  late SimpleKeyPair keyB;
  late String pubB;
  late SimpleKeyPair keyC;
  late String pubC;

  late AppDatabase db;

  setUp(() async {
    keyA = await algorithm.newKeyPair();
    pubA = bytesToHex((await keyA.extractPublicKey()).bytes);
    keyB = await algorithm.newKeyPair();
    pubB = bytesToHex((await keyB.extractPublicKey()).bytes);
    keyC = await algorithm.newKeyPair();
    pubC = bytesToHex((await keyC.extractPublicKey()).bytes);
    db = AppDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  CreditService svc({AppDatabase? onDb}) =>
      CreditService(db: onDb ?? db, initialBalance: 0.0);

  void fund(CreditService s, double amount) {
    s.awardVerificationCredits(action: 'seed', targetId: 't', amount: amount);
  }

  /// Production-equivalent Ed25519 oracle (mirrors provider wiring).
  Future<bool> receiptVerifier(
      Uint8List message, Uint8List sig, String publicKeyHex) async {
    try {
      final pk =
          SimplePublicKey(hexToBytes(publicKeyHex), type: KeyPairType.ed25519);
      return await algorithm.verify(message,
          signature: Signature(sig, publicKey: pk));
    } catch (_) {
      return false;
    }
  }

  Future<String> claimSig(WorkReceipt r, {SimpleKeyPair? prover}) async {
    final preimage = Uint8List.fromList(
        utf8.encode('alexandria:receipt-claim:v${r.v}:${r.receiptId}'));
    final sig = await algorithm.sign(preimage, keyPair: prover ?? keyB);
    return base64Encode(sig.bytes);
  }

  /// Receipt: prover = B (current local key), verifier = [vKey]/[vPub]
  /// (default A — the retired local key). v3 attaches the issuance
  /// acknowledgment ([WorkReceipt.ackPayload]) under [proverKeyPair]
  /// (default B — the prover of record).
  Future<WorkReceipt> signedReceipt({
    String? verifierPubkey,
    SimpleKeyPair? verifierKeyPair,
    String? proverPubkey,
    SimpleKeyPair? proverKeyPair,
    double amount = 25.0,
  }) async {
    final unsigned = WorkReceipt.issue(
      workType: 'storage',
      proverPubkey: proverPubkey ?? pubB,
      verifierPubkey: verifierPubkey ?? pubA,
      cid: 'bafy_omega4a',
      chunkIndices: const [0],
      challengeNonce: 'ab' * 16,
      responseTag: 'cd' * 32,
      workUnits: 2048,
      amount: amount,
      epoch: WorkReceipt.epochFor(DateTime.now()),
      expiresAt:
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    );
    final sig = await algorithm.sign(unsigned.signingPayload,
        keyPair: verifierKeyPair ?? keyA);
    var signed = unsigned.withVerifierSig(base64Encode(sig.bytes));
    if (signed.v >= WorkReceipt.minAckWireVersion) {
      final ack = await algorithm.sign(signed.ackPayload,
          keyPair: proverKeyPair ?? keyB);
      signed = signed.withProverSig(base64Encode(ack.bytes));
    }
    return signed;
  }

  Future<WorkReceipt> persist(WorkReceipt r) async {
    await db.insertWorkReceipt(r.toDbMap());
    return r;
  }

  /// Writes key [kp] into secure storage the way a PRE-FEATURE install
  /// did — no pubkey-history append ever ran for it.
  Future<void> seedStorageWithKey(
      _FakeSecureStorage storage, SimpleKeyPair kp, String pubHex) async {
    await storage.write('alexandria_identity_private_key',
        bytesToHex(await kp.extractPrivateKeyBytes()));
    await storage.write('alexandria_identity_public_key', pubHex);
    await storage.write(
        'alexandria_identity_created', DateTime.now().toIso8601String());
  }

  // ─────────────────────────────────────────────────────────────────
  group('R1: escrow payout vs refund — the two dedup sets never meet', () {
    test(
        'payout THEN release: releaseEscrow must refuse an '
        'already-paid-out escrow', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      expect(s.debitEscrow(amount: 20.0, referenceId: 'b1'), isTrue);
      expect(s.balance, 30.0);
      // The claim settles: escrow is paid to the claimant.
      expect(s.awardBountyEscrow(amount: 20.0, bountyId: 'b1', cid: 'c'), 20.0);
      expect(s.balance, 50.0);
      // The hold row still matches the release predicate — a cancel that
      // lands after the payout must NOT refund a spent escrow.
      final refund = await s.releaseEscrow(referenceId: 'b1');
      expect(refund, 0.0,
          reason: 'escrow already paid out — a refund double-mints');
      expect(s.balance, 50.0, reason: 'balance must stay 50 — not 70');
    });

    test(
        'release THEN payout: awardBountyEscrow must refuse an escrow '
        'that was already refunded', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      s.debitEscrow(amount: 20.0, referenceId: 'b2');
      expect(await s.releaseEscrow(referenceId: 'b2'), 20.0);
      expect(s.balance, 50.0);
      final paid = s.awardBountyEscrow(amount: 20.0, bountyId: 'b2', cid: 'c');
      expect(paid, 0.0,
          reason: 'the hold was released — paying it mints from nothing');
      expect(s.balance, 50.0);
    });

    test(
        'the double-dip survives a restart — the persisted hold row is '
        'still releasable after the payout row lands', () async {
      final first = svc();
      await first.ready;
      fund(first, 50.0);
      first.debitEscrow(amount: 20.0, referenceId: 'b3');
      first.awardBountyEscrow(amount: 20.0, bountyId: 'b3', cid: 'c');
      await first.settled;

      final second = svc();
      await second.ready;
      expect(second.balance, 50.0);
      final refund = await second.releaseEscrow(referenceId: 'b3');
      expect(refund, 0.0,
          reason: 'hydration rebuilt _paidBountyIds — releaseEscrow '
              'must consult it; the hold row alone must not refund');
      expect(second.balance, 50.0);
    });

    test(
        'service-level: cancelBounty refuses a locally-posted bounty '
        'whose payout row is ALREADY durable in this db', () async {
      final cs = svc();
      await cs.ready;
      fund(cs, 50.0);
      final molt = MoltbookService(creditService: cs, db: db);
      addTearDown(molt.dispose);
      final bounty = await molt.postPreservationBounty(
          cid: 'bafy_dip', title: 'dip', offeredCredits: 20.0, force: true);
      expect(cs.balance, 30.0);

      // A settled claim leaves exactly this durable proof-of-payment —
      // the same row the REV4 crash reconciler probes via
      // hasCreditTransaction. claimed_bounties is CLAIMANT-LOCAL: a
      // remote claim never lands in the poster's table.
      await db.insertCreditTransaction(_txRow(
        id: 'tx_bounty_payout_${bounty.id}',
        timestamp: DateTime.now(),
        amount: 20.0,
        description: 'Bounty Escrow Payout (${bounty.id})',
        referenceId: bounty.cid,
      ));

      final cancelled = await molt.cancelBounty(bounty.id);
      expect(cancelled, isFalse,
          reason: 'a bounty with a durable payout row must not refund '
              'its escrow — release-after-payout is a double mint');
      expect(cs.balance, 30.0);

      // …and the ledger itself must not show +20 minted.
      final check = svc();
      await check.ready;
      expect(check.balance, 50.0,
          reason: 'hold(-20)+payout(+20) nets 50; a release on top '
              'replays to 70 — an unbacked mint');
    });

    test(
        'sanity: a claimant-side claimed_bounties row DOES block '
        'cancelBounty (the only guard is claimant-local state)', () async {
      final cs = svc();
      await cs.ready;
      fund(cs, 50.0);
      final molt = MoltbookService(creditService: cs, db: db);
      addTearDown(molt.dispose);
      final bounty = await molt.postPreservationBounty(
          cid: 'bafy_sane', title: 's', offeredCredits: 20.0, force: true);
      await db.insertClaimedBounty(bounty.id, bounty.cid);
      expect(await molt.cancelBounty(bounty.id), isFalse);
      expect(cs.balance, 30.0);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group(
      'R2: description-marker spoofing — any caller-controlled reason '
      'forges a releasable "hold"', () {
    test(
        'spendCredits with a crafted reason mints a releasable '
        'non-escrow debit', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      // The release predicate is (type=priorityAccessDebit, amount<0,
      // description CONTAINS 'Bounty Escrow Hold'). spendCredits writes
      // description='$reason (incl. 5% treasury fee)' — reason is fully
      // caller-controlled, so the marker is forgeable.
      expect(
          s.spendCredits(
              amount: 30.0,
              reason: 'Bounty Escrow Hold (totally legit)',
              referenceId: 'r_sp'),
          isTrue);
      expect(s.balance, 20.0);
      final refund = await s.releaseEscrow(referenceId: 'r_sp');
      expect(refund, 0.0,
          reason: 'a plain spendCredits debit must NEVER be releasable — '
              'the docstring claims exactly this and it is false');
      expect(s.balance, 20.0);
      // The spend legitimately executed and was never refunded — its
      // 5% treasury fee is honestly earned (treasury starts at 50.0).
      expect(s.protocolTreasury, 51.5);
    });

    test(
        'a spoofed spend under a REAL bounty referenceId inflates the '
        'legitimate refund', () async {
      final s = svc();
      await s.ready;
      fund(s, 100.0);
      s.debitEscrow(amount: 10.0, referenceId: 'b_real'); // real hold
      s.spendCredits(
          amount: 40.0,
          reason: 'x Bounty Escrow Hold y',
          referenceId: 'b_real'); // piggybacked fake hold
      expect(s.balance, 50.0);
      final refund = await s.releaseEscrow(referenceId: 'b_real');
      expect(refund, 10.0,
          reason: 'only the genuine hold may refund — the summed scan '
              'cannot distinguish spoofed spend rows');
      expect(s.balance, 60.0);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group('R3: dedup edges', () {
    test(
        'three overlapping releaseEscrow calls on ONE instance pay '
        'exactly once', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      s.debitEscrow(amount: 20.0, referenceId: 'b8');
      final results = await Future.wait([
        s.releaseEscrow(referenceId: 'b8'),
        s.releaseEscrow(referenceId: 'b8'),
        s.releaseEscrow(referenceId: 'b8'),
      ]);
      expect(results.where((r) => r > 0).length, 1);
      expect(s.balance, 50.0);
    });

    test(
        'two live instances racing a release converge on ONE canonical '
        'refund (deterministic row id dedups the durable record)', () async {
      final a = svc();
      await a.ready;
      fund(a, 50.0);
      a.debitEscrow(amount: 20.0, referenceId: 'b9');
      await a.settled;

      // B hydrates while the hold exists but BEFORE A's release.
      final b = svc();
      await b.ready;
      expect(b.balance, 30.0);

      expect(await a.releaseEscrow(referenceId: 'b9'), 20.0);
      await a.settled; // the release tombstone is durable now
      // Stale-view B never saw the release in memory — but the durable
      // release-tombstone probe revalidates at write time, so the
      // second refund now refuses instead of minting an unbacked
      // in-memory artifact (multi-instance stale-view closure).
      expect(await b.releaseEscrow(referenceId: 'b9'), 0.0,
          reason: 'the durable tx_escrow_release_b9 row is the '
              'authority — B\'s stale in-memory view cannot re-refund');
      await Future.wait([a.settled, b.settled]);

      final rows = await db.getCreditTransactions();
      expect(rows.where((r) => r['id'] == 'tx_escrow_release_b9').length, 1,
          reason: 'insertOrIgnore must collapse the identical '
              'deterministic ids into one durable refund');
      final c = svc();
      await c.ready;
      expect(c.balance, 50.0);
    });

    test(
        'a re-posted hold on a stale-view instance re-refunds the OLD '
        'hold — canonical outcome is write-order dependent', () async {
      final a = svc();
      await a.ready;
      fund(a, 50.0);
      a.debitEscrow(amount: 20.0, referenceId: 'b10');
      await a.settled;

      final b = svc();
      await b.ready; // B's view: hold only, released-set empty

      expect(await a.releaseEscrow(referenceId: 'b10'), 20.0);
      await a.settled; // release row durable now

      // B re-posts under the same referenceId (its view never learned
      // of the release) and releases — matching BOTH hold rows in its
      // own view. The durable release-tombstone probe now catches A's
      // release at write time, so the stale-view double-refund refuses.
      b.debitEscrow(amount: 10.0, referenceId: 'b10');
      final refund = await b.releaseEscrow(referenceId: 'b10');
      expect(refund, 0.0,
          reason: 'multi-instance stale-view closure: the durable '
              'tx_escrow_release_b10 row is the authority — B\'s '
              'in-memory released-set being stale can no longer '
              're-refund the old hold');

      await Future.wait([a.settled, b.settled]);
      final rows = await db.getCreditTransactions();
      final releaseRows =
          rows.where((r) => r['id'] == 'tx_escrow_release_b10').toList();
      expect(releaseRows.length, 1);
      expect(releaseRows.single['amount'], 20.0,
          reason: 'exactly one canonical refund — A\'s single-hold '
              'release; the re-posted hold stays stranded by '
              'once-per-referenceId-forever semantics');
    });

    test(
        'crash window CLOSED: a parked release write cannot return '
        'success early; a lost write fails closed and stays '
        're-releasable (exactly one canonical refund)', () async {
      final gdb = _GatedReleaseInsertDb();
      addTearDown(gdb.close);
      final a = svc(onDb: gdb);
      await a.ready;
      fund(a, 50.0);
      a.debitEscrow(amount: 20.0, referenceId: 'b11');
      await a.settled;

      // DURABLE-FIRST (optimistic-return residual): the release call
      // itself awaits the dedup-row CAS — with the write parked the
      // call must NOT return a refund. The old crash window (returned
      // refund while the row was still unwritten) no longer exists.
      gdb.armed = true;
      final inFlight = a.releaseEscrow(referenceId: 'b11');
      var returned = false;
      unawaited(inFlight.then((_) => returned = true));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(returned, isFalse,
          reason: 'a returned refund must correspond to a committed '
              'dedup row — the call waits on the write');
      gdb.gate.complete();
      expect(await inFlight, 20.0);

      // Write-loss variant: the CAS throws → releaseEscrow fails
      // CLOSED (0.0, nothing mutates, the id is unburned for retry).
      // A sibling instance then performs the canonical release exactly
      // once — the self-heal the old crash-window path needed.
      a.debitEscrow(amount: 15.0, referenceId: 'b11w');
      await a.settled;
      gdb.throwWhenArmed = true;
      expect(await a.releaseEscrow(referenceId: 'b11w'), 0.0,
          reason: 'fail closed: a refund that cannot commit must not '
              'mutate the in-memory view');
      expect(a.balance, 35.0);
      gdb.armed = false; // writes flow again — models the post-crash db
      final c = svc(onDb: gdb);
      await c.ready;
      expect(c.balance, 35.0);
      expect(await c.releaseEscrow(referenceId: 'b11w'), 15.0,
          reason: 'the missing dedup row means the refund never '
              'canonically happened — re-release is the correct heal, '
              'not a double-pay');
      await Future.wait([a.settled, c.settled]);
      final rows = await gdb.getCreditTransactions();
      expect(rows.where((r) => r['id'] == 'tx_escrow_release_b11').length, 1);
      expect(rows.where((r) => r['id'] == 'tx_escrow_release_b11w').length, 1);
      final d = svc(onDb: gdb);
      await d.ready;
      expect(d.balance, 50.0);
    });

    test(
        'release-then-repost under the same referenceId: the second '
        'hold is NOT refundable — once-per-referenceId-forever '
        'semantics', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      s.debitEscrow(amount: 20.0, referenceId: 'b12');
      expect(await s.releaseEscrow(referenceId: 'b12'), 20.0);
      // A new bounty re-uses the id (e.g. same-ms postPreservationBounty
      // ids, or any caller that recycles referenceIds).
      expect(s.debitEscrow(amount: 15.0, referenceId: 'b12'), isTrue);
      expect(s.balance, 35.0);
      final refund = await s.releaseEscrow(referenceId: 'b12');
      expect(refund, 0.0,
          reason: 'the deterministic tx_escrow_release_<id> row can '
              'only land once — re-posted holds under a spent '
              'referenceId are stranded by design (cancel = once-ever '
              'per id)');
    });

    test(
        'debitEscrow refuses an EMPTY referenceId — symmetric with '
        'releaseEscrow', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      expect(s.debitEscrow(amount: 10.0, referenceId: ''), isFalse);
      expect(s.balance, 50.0);
      final refund = await s.releaseEscrow(referenceId: '');
      expect(refund, 0.0);
    });

    test(
        'a directly-persisted tx_escrow_release_* row poisons the dedup '
        'set — the matching hold becomes unreleasable', () async {
      // db-level write only — no public CreditService API can mint this
      // id, so it is NOT wire-reachable; documents the blast radius if
      // any future path lets callers choose a row id.
      await db.insertCreditTransaction(_txRow(
        id: 'tx_escrow_release_victim',
        timestamp: DateTime.now(),
        amount: 1.0,
        type: 'priorityAccessDebit',
        description: 'forged',
        referenceId: 'victim',
      ));
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      s.debitEscrow(amount: 10.0, referenceId: 'victim');
      expect(await s.releaseEscrow(referenceId: 'victim'), 0.0,
          reason: 'dedup-record-is-payment-record: a persisted '
              'tx_escrow_release_<id> row marks the id released — '
              'hydration correctly refuses. Not wire-reachable (no '
              'public API can mint the id); documents the blast '
              'radius if a future path lets callers choose row ids');
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group('R4: non-finite / weird amounts', () {
    test(
        'debitEscrow(double.nan) must be refused — NaN defeats every '
        'comparison guard', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      final ok = s.debitEscrow(amount: double.nan, referenceId: 'nan1');
      expect(ok, isFalse,
          reason: 'NaN <= 0 is false and _balance < NaN is false — the '
              'debit sails through and poisons the balance');
      expect(s.balance.isFinite, isTrue);
    });

    test('a NaN hold must not cascade into unbounded spending', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      s.debitEscrow(amount: double.nan, referenceId: 'nan2');
      // If the balance went NaN, `NaN < amount` is false forever —
      // every spend succeeds.
      expect(s.spendCredits(amount: 1e6, reason: 'drain'), isFalse,
          reason: 'a NaN balance must fail closed, not open');
      // releaseEscrow on the NaN row: -NaN < 0 is false → never matched.
      expect(await s.releaseEscrow(referenceId: 'nan2'), 0.0);
    });

    test('spendCredits(double.nan) must be refused', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      expect(s.spendCredits(amount: double.nan, reason: 'nan spend'), isFalse,
          reason: 'same missing isFinite guard as debitEscrow');
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group('R5: rotation self-vouch history', () {
    test(
        'LIVE?: a pre-feature key retired before ANY read escapes the '
        'history — its verifier-signed receipt still mints', () async {
      final storage = _FakeSecureStorage();
      // Install A the way the pre-feature build persisted it — no
      // history append ever ran, and getIdentity is never called.
      await seedStorageWithKey(storage, keyA, pubA);
      final identity = IdentityService(storage);
      addTearDown(identity.dispose);

      // Rotate straight to B: _persistIdentityUnlocked records only the
      // INCOMING key — the outgoing prevPubHex is never appended.
      await identity.importIdentity(
          Uint8List.fromList(await keyB.extractPrivateKeyBytes()));

      final known = await identity.knownLocalPubkeyHexes();
      // Soft-record the history gap (no expect — it must not abort the
      // claim): the gap alone is only a finding if it converts to a
      // mint below.
      final holeObserved = !known.contains(pubA);

      final r = await persist(await signedReceipt());
      final s = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        localProverPubkeyHex: () async => pubB,
        knownLocalPubkeys: identity.knownLocalPubkeyHexes,
      );
      await s.ready;
      final minted =
          await s.claimVerifiedReceipt(r, claimSignatureB64: await claimSig(r));
      expect(minted, 0.0,
          reason: 'a receipt signed by retired key A is self-issued — '
              'it must never mint attested value '
              '(history hole observed: $holeObserved, minted: $minted)');
      expect(s.attestedBalance, 0.0);
    });

    test(
        'same hole via deleteIdentity → fresh install: the deleted '
        'never-read key escapes history', () async {
      final storage = _FakeSecureStorage();
      await seedStorageWithKey(storage, keyA, pubA);
      final identity = IdentityService(storage);
      addTearDown(identity.dispose);

      await identity.deleteIdentity();
      await identity.importIdentity(
          Uint8List.fromList(await keyB.extractPrivateKeyBytes()));

      final known = await identity.knownLocalPubkeyHexes();
      final holeObserved = !known.contains(pubA);

      final r = await persist(await signedReceipt());
      final s = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        localProverPubkeyHex: () async => pubB,
        knownLocalPubkeys: identity.knownLocalPubkeyHexes,
      );
      await s.ready;
      final minted =
          await s.claimVerifiedReceipt(r, claimSignatureB64: await claimSig(r));
      expect(minted, 0.0,
          reason: 'deleted-then-rotated key still self-issued '
              '(history hole observed: $holeObserved, minted: $minted)');
    });

    test(
        'canonical + garbage history entries: padded/uppercase '
        'spellings still refuse, garbage does not break claims', () async {
      // History carries respellings and junk — all must behave.
      CreditService s() => CreditService(
            db: db,
            initialBalance: 0.0,
            receiptVerifier: receiptVerifier,
            localProverPubkeyHex: () async => pubB,
            knownLocalPubkeys: () async =>
                {'!!not-hex!!', pubA.toUpperCase(), '  $pubB  ', ''},
          );
      final r1 = await persist(await signedReceipt());
      final svc1 = s();
      await svc1.ready;
      expect(
          await svc1.claimVerifiedReceipt(r1,
              claimSignatureB64: await claimSig(r1)),
          0.0,
          reason: 'UPPERCASE history entry still canonically matches '
              'retired verifier A');

      final r2 = await persist(
          await signedReceipt(verifierPubkey: pubC, verifierKeyPair: keyC));
      final svc2 = s();
      await svc2.ready;
      expect(
          await svc2.claimVerifiedReceipt(r2,
              claimSignatureB64: await claimSig(r2)),
          25.0,
          reason: 'garbage entries must not poison the guard — the '
              'foreign verifier claim still mints');
    });

    test(
        'A→B→A re-rotation: a B-signed receipt (now doubly-retired) is '
        'still refused', () async {
      final storage = _FakeSecureStorage();
      final identity = IdentityService(storage);
      addTearDown(identity.dispose);
      await identity.importIdentity(
          Uint8List.fromList(await keyA.extractPrivateKeyBytes()));
      await identity.importIdentity(
          Uint8List.fromList(await keyB.extractPrivateKeyBytes()));
      await identity.importIdentity(
          Uint8List.fromList(await keyA.extractPrivateKeyBytes()));

      expect(await identity.knownLocalPubkeyHexes(), containsAll({pubA, pubB}));

      // Current key is A again; receipt prover=A, verifier=B (retired).
      final r = await persist(await signedReceipt(
          verifierPubkey: pubB,
          verifierKeyPair: keyB,
          proverPubkey: pubA,
          proverKeyPair: keyA));
      final s = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        localProverPubkeyHex: () async => pubA,
        knownLocalPubkeys: identity.knownLocalPubkeyHexes,
      );
      await s.ready;
      expect(
          await s.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r, prover: keyA)),
          0.0,
          reason: 'B is in the never-shrinking history — re-rotation '
              'cannot launder it into a foreign verifier');
    });

    test(
        'deleteIdentity keeps history but claims fail closed on the '
        'prover binding — no crash, no false mint', () async {
      final storage = _FakeSecureStorage();
      final identity = IdentityService(storage);
      addTearDown(identity.dispose);
      await identity.importIdentity(
          Uint8List.fromList(await keyA.extractPrivateKeyBytes()));
      await identity.deleteIdentity();

      // History survives deletion…
      expect(await identity.knownLocalPubkeyHexes(), contains(pubA));
      // …but with no current key every claim refuses at the prover
      // binding — the deleted key's receipts cannot become claimable.
      final r = await persist(await signedReceipt());
      final s = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        localProverPubkeyHex: () async {
          final id = await identity.getIdentity();
          return id == null ? null : bytesToHex(id.publicKey);
        },
        knownLocalPubkeys: identity.knownLocalPubkeyHexes,
      );
      await s.ready;
      expect(
          await s.claimVerifiedReceipt(r, claimSignatureB64: await claimSig(r)),
          0.0);
      expect(s.attestedBalance, 0.0);
    });

    test(
        'resolver returning the PROVER key in history does not bar a '
        'foreign verifier claim', () async {
      final r = await persist(
          await signedReceipt(verifierPubkey: pubC, verifierKeyPair: keyC));
      final s = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        localProverPubkeyHex: () async => pubB,
        knownLocalPubkeys: () async => {pubB},
      );
      await s.ready;
      expect(
          await s.claimVerifiedReceipt(r, claimSignatureB64: await claimSig(r)),
          25.0);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group('R6: _txSeq / id construction', () {
    test(
        'deterministic release rows and auto ids stay disjoint across '
        'instances sharing one db', () async {
      final a = svc();
      await a.ready;
      fund(a, 50.0);
      a.debitEscrow(amount: 5.0, referenceId: 'seq1');
      await a.releaseEscrow(referenceId: 'seq1');

      final b = svc();
      await b.ready;
      b.awardVerificationCredits(action: 'x', targetId: 'y', amount: 1.0);
      await Future.wait([a.settled, b.settled]);

      final rows = await db.getCreditTransactions();
      final ids = rows.map((r) => r['id'] as String).toList();
      expect(ids.toSet().length, ids.length,
          reason: 'no persisted row may be silently dropped by an id '
              'collision');
      // The auto-generated ids carry the monotonic seq suffix; the
      // deterministic release row carries the referenceId — disjoint.
      expect(ids.any((id) => id == 'tx_escrow_release_seq1'), isTrue);
    });
  });
}
