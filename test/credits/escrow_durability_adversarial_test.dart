// SCRATCH RE-EVALUATOR FILE - REV4a fix-diff verification + regression hunt.
// Probes ONLY holes the fix diffs themselves introduced:
//   A  releaseEscrow never re-checks _paidBountyIds AFTER the awaited
//      payout-row probe - a same-isolate awardBountyEscrow landing in the
//      probe window mints AND the release refunds (TOCTOU double-dip).
//   B  `_txSeq` resets per process - a hold id `tx_escrow_hold_<ref>_<seq>`
//      can collide with a pre-restart row for a recycled referenceId →
//      insertOrIgnore drops a REAL debit → release refunds a hold the
//      durable ledger never recorded (phantom mint on next hydrate).
//   B2 pre-REV4a hold rows (auto-id + 'Bounty Escrow Hold' description)
//      no longer match the id-prefix release predicate → stranded escrow
//      on upgrade.
//   C  delete-path history record end-to-end (never-read key → delete →
//      reinstall → self-vouch claim must still refuse).
//   D  a hydrated hold row carrying a non-finite amount is refused.
// Every test asserts the SECURE expectation - a FAILURE marks a LIVE hole.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart'
    hide CreditTransaction, WorkReceipt;
import 'package:drift/drift.dart' show Value;
import 'package:alexandria/services/agent/beacon_models.dart'
    show bytesToHex, hexToBytes;
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/work_receipt.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

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

/// Parks the releaseEscrow payout probe behind [probeGate] and (when
/// [holdPayoutRows]) parks the durable payout-row insert behind
/// [payoutGate]. Lets a synchronous awardBountyEscrow run INSIDE the
/// probe await - the window between the probe and the no-await
/// check/scan/add region.
class _ProbeGateDb extends AppDatabase {
  final Completer<void> probeGate = Completer<void>();
  final Completer<void> payoutGate = Completer<void>();
  bool armProbe = false;
  bool holdPayoutRows = false;
  bool probeParked = false;

  @override
  Future<bool> hasCreditTransaction(String id) async {
    if (armProbe) {
      probeParked = true;
      await probeGate.future;
    }
    return super.hasCreditTransaction(id);
  }

  @override
  Future<void> insertCreditTransaction(Map<String, dynamic> data) async {
    final id = data['id'] as String?;
    if (holdPayoutRows && id != null && id.startsWith('tx_bounty_payout_')) {
      await payoutGate.future;
    }
    return super.insertCreditTransaction(data);
  }
}

Map<String, dynamic> _txRow({
  required String id,
  required double amount,
  String type = 'verificationReward',
  String description = 'seeded',
  String? referenceId,
}) =>
    {
      'id': id,
      'timestamp': DateTime.now(),
      'type': type,
      'amount': amount,
      'description': description,
      'referenceId': referenceId,
      'hash': 'h_$id',
      'isAttested': false,
    };

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  CreditService svc({AppDatabase? onDb, double initialBalance = 0.0}) =>
      CreditService(db: onDb ?? db, initialBalance: initialBalance);

  void fund(CreditService s, double amount) {
    s.awardVerificationCredits(action: 'seed', targetId: 't', amount: amount);
  }

  group('RE-A: releaseEscrow probe-window TOCTOU', () {
    test(
        'an awardBountyEscrow landing DURING the payout-probe await '
        'mints while the release still refunds — the in-memory '
        '_paidBountyIds set is never re-checked after the await', () async {
      final gdb = _ProbeGateDb();
      addTearDown(gdb.close);
      final s = svc(onDb: gdb);
      await s.ready;
      fund(s, 50.0);
      expect(s.debitEscrow(amount: 20.0, referenceId: 'victim'), isTrue);
      await s.settled;

      gdb.armProbe = true;
      gdb.holdPayoutRows = true;
      final releaseF = s.releaseEscrow(referenceId: 'victim');
      while (!gdb.probeParked) {
        await Future<void>.delayed(Duration.zero);
      }

      // Interleave: a claim-settlement path (claimBounty →
      // awardBountyEscrow is synchronous) runs while the release's
      // durable probe is parked. The award mints and enqueues its
      // payout row - which stays parked so the probe cannot see it.
      expect(s.awardBountyEscrow(amount: 20.0, bountyId: 'victim', cid: 'c'),
          20.0);
      expect(s.balance, 50.0); // 50 - 20 hold + 20 payout

      gdb.probeGate.complete(); // probe now reads: row still parked
      final refund = await releaseF;
      expect(refund, 0.0,
          reason: 'the award already minted this escrow in-memory — '
              'the release must observe _paidBountyIds after the await, '
              'not only before it');
      expect(s.balance, 50.0,
          reason: 'refund-on-top-of-payout double-mints to 70');

      gdb.payoutGate.complete();
      await s.settled;

      // Canonical outcome: if both rows landed, the ledger itself
      // records the double-mint - it survives a restart.
      final s2 = svc(onDb: gdb);
      await s2.ready;
      expect(s2.balance, 50.0,
          reason: 'durable ledger must show hold(-20)+payout(+20) = 50, '
              'not +release(20) on top');
    });

    test(
        'control: an award that completed BEFORE the probe still '
        'refuses the release', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      s.debitEscrow(amount: 20.0, referenceId: 'ctl');
      expect(
          s.awardBountyEscrow(amount: 20.0, bountyId: 'ctl', cid: 'c'), 20.0);
      await s.settled;
      expect(await s.releaseEscrow(referenceId: 'ctl'), 0.0);
      expect(s.balance, 50.0);
    });
  });

  group('RE-B: hold-id seq reuse across restart', () {
    test(
        'a re-posted hold whose seq collides with a persisted row is '
        'insertOrIgnore-dropped — the durable ledger loses a real debit '
        'and releaseEscrow refunds BOTH in-memory holds', () async {
      // Model the post-restart collision deterministically: learn the
      // next _txSeq value, then seed a "pre-restart" hold row under the
      // id the next debitEscrow will mint.
      final s1 = svc();
      await s1.ready;
      fund(s1, 100.0);
      expect(s1.debitEscrow(amount: 1.0, referenceId: 'probe'), isTrue);
      final probeRow =
          s1.transactions.firstWhere((t) => t.referenceId == 'probe');
      final seq = int.parse(probeRow.id.split('_').last);
      await s1.settled;

      // The pre-restart hold row for the recycled referenceId - in a
      // real restart _txSeq is 0 again, so `tx_escrow_hold_shared_<n>`
      // repeats; here we force the exact id the NEXT hold will claim.
      await db.insertCreditTransaction(_txRow(
        id: 'tx_escrow_hold_shared_${seq + 1}',
        amount: -20.0,
        type: 'priorityAccessDebit',
        description: 'Bounty Escrow Hold (shared)',
        referenceId: 'shared',
      ));

      // "Restart": a fresh instance hydrates the seeded hold.
      final s2 = svc();
      await s2.ready;
      expect(s2.balance, 79.0); // 100 - 1 probe - 20 seeded hold

      // The re-posted hold mints `tx_escrow_hold_shared_<seq+1>` - the
      // SAME primary key as the seeded row. The in-memory list gains
      // it; the durable insert is insertOrIgnore-DROPPED.
      expect(s2.debitEscrow(amount: 20.0, referenceId: 'shared'), isTrue);
      await s2.settled;
      final holdRows = (await db.getCreditTransactions())
          .where(
              (r) => (r['id'] as String).startsWith('tx_escrow_hold_shared_'))
          .toList();
      expect(holdRows.length, 2,
          reason: 'two distinct debits of -20 must both persist — '
              'insertOrIgnore silently dropped the second');

      // The in-memory scan sees both holds and refunds the SUM - but
      // only one debit is durable.
      expect(await s2.releaseEscrow(referenceId: 'shared'), 40.0);
      await s2.settled;

      final s3 = svc();
      await s3.ready;
      expect(s3.balance, 99.0,
          reason: 'canonical: 100 -1 -20 -20 +40 = 99; a dropped hold '
              'row leaves the durable ledger at 119 — a +20 phantom '
              'mint created by a primary-key collision');
    });

    test(
        'a hold row written by a PRE-REV4a build (auto id + description '
        'marker, no hold-prefix id) is now unreleasable — upgrade '
        'strands existing escrow', () async {
      // Older debitEscrow wrote: id 'tx_<micros>_<len>', description
      // 'Bounty Escrow Hold (<ref>)'. The new release predicate
      // requires the tx_escrow_hold_ id prefix → the legacy row can
      // never be released.
      await db.insertCreditTransaction(_txRow(
        id: 'tx_1700000000000000_7',
        amount: -20.0,
        type: 'priorityAccessDebit',
        description: 'Bounty Escrow Hold (legacy_ref)',
        referenceId: 'legacy_ref',
      ));
      final s = svc(initialBalance: 0.0);
      await s.ready;
      // A node that escrowed 20 before upgrading must be able to refund.
      expect(await s.releaseEscrow(referenceId: 'legacy_ref'), 20.0,
          reason: 'the id-prefix predicate orphaned every hold row '
              'written before the fix — stranded escrow on upgrade');
    });
  });

  group('RE-C: delete-path pubkey history → claim refusal', () {
    final algorithm = Ed25519();

    test(
        'a key installed pre-feature, never read, then DELETED still '
        'refuses its verifier-signed receipts after a fresh install', () async {
      final keyA = await algorithm.newKeyPair();
      final keyB = await algorithm.newKeyPair();
      final pubA = bytesToHex((await keyA.extractPublicKey()).bytes);
      final pubB = bytesToHex((await keyB.extractPublicKey()).bytes);

      final storage = _FakeSecureStorage();
      // Pre-feature install of A - no history blob ever written.
      await storage.write('alexandria_identity_private_key',
          bytesToHex(await keyA.extractPrivateKeyBytes()));
      await storage.write('alexandria_identity_public_key', pubA);
      await storage.write(
          'alexandria_identity_created', DateTime.now().toIso8601String());

      final identity = IdentityService(storage);
      addTearDown(identity.dispose);
      // Delete A without ANY read, then install B.
      await identity.deleteIdentity();
      await identity.importIdentity(
          Uint8List.fromList(await keyB.extractPrivateKeyBytes()));
      expect(await identity.knownLocalPubkeyHexes(), containsAll({pubA, pubB}));

      // Receipt: prover = current key B, verifier = deleted key A.
      final unsigned = WorkReceipt.issue(
        workType: 'storage',
        proverPubkey: pubB,
        verifierPubkey: pubA,
        cid: 'bafy_reeval_c',
        chunkIndices: const [0],
        challengeNonce: 'ab' * 16,
        responseTag: 'cd' * 32,
        workUnits: 2048,
        amount: 25.0,
        epoch: WorkReceipt.epochFor(DateTime.now()),
        expiresAt:
            DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
      );
      final vsig = await algorithm.sign(unsigned.signingPayload, keyPair: keyA);
      var receipt = unsigned.withVerifierSig(base64Encode(vsig.bytes));
      // v3 issuance acknowledgment - prover B counter-signs the ack
      // domain (the claim is still refused on the self-issued guard).
      if (receipt.v >= WorkReceipt.minAckWireVersion) {
        final ack = await algorithm.sign(receipt.ackPayload, keyPair: keyB);
        receipt = receipt.withProverSig(base64Encode(ack.bytes));
      }
      await db.insertWorkReceipt(receipt.toDbMap());

      Future<bool> verifier(Uint8List msg, Uint8List sig, String pubHex) async {
        try {
          final pk =
              SimplePublicKey(hexToBytes(pubHex), type: KeyPairType.ed25519);
          return await algorithm.verify(msg,
              signature: Signature(sig, publicKey: pk));
        } catch (_) {
          return false;
        }
      }

      final cs = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: verifier,
        localProverPubkeyHex: () async {
          final id = await identity.getIdentity();
          return id == null ? null : bytesToHex(id.publicKey);
        },
        knownLocalPubkeys: identity.knownLocalPubkeyHexes,
      );
      await cs.ready;

      final claimPreimage = Uint8List.fromList(utf8.encode(
          'alexandria:receipt-claim:v${receipt.v}:${receipt.receiptId}'));
      final claimSig = base64Encode(
          (await algorithm.sign(claimPreimage, keyPair: keyB)).bytes);
      expect(
          await cs.claimVerifiedReceipt(receipt, claimSignatureB64: claimSig),
          0.0,
          reason: 'deleted-before-read key A signed this receipt — the '
              'delete-path history record must keep it self-issued');
    });
  });

  group('RE-D: non-finite ledger rows', () {
    test(
        'a hydrated hold row with amount -infinity cannot mint an '
        'infinite refund', () async {
      await db.insertCreditTransaction(_txRow(
        id: 'tx_escrow_hold_inf_0',
        amount: double.negativeInfinity,
        type: 'priorityAccessDebit',
        description: 'Bounty Escrow Hold (inf)',
        referenceId: 'inf',
      ));
      final s = svc();
      await s.ready;
      final refund = await s.releaseEscrow(referenceId: 'inf');
      expect(refund, 0.0);
      expect(s.balance.isFinite, isTrue);
    });
  });
  group('RE-W: hydration-window-bound dedup + hold scan', () {
    test(
        'a payout/hold row older than the 100k hydration window is '
        'invisible to the dedup rebuild AND to the release hold scan — '
        'old paid ids re-mint, old holds strand', () async {
      // Seed an OLD paid escrow pair, then >window newer rows so both
      // fall outside the replay window.
      final base = DateTime.now()
          .subtract(const Duration(days: 30))
          .millisecondsSinceEpoch;
      await db.batch((b) {
        b.insert(
          db.creditTransactions,
          CreditTransactionsCompanion.insert(
            id: 'tx_escrow_hold_old_0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(base),
            type: 'priorityAccessDebit',
            amount: -20.0,
            description: 'Bounty Escrow Hold (old)',
            hash: 'h_hold',
            referenceId: const Value('old'),
          ),
        );
        b.insert(
          db.creditTransactions,
          CreditTransactionsCompanion.insert(
            id: 'tx_bounty_payout_old',
            timestamp: DateTime.fromMillisecondsSinceEpoch(base + 1),
            type: 'verificationReward',
            amount: 20.0,
            description: 'Bounty Escrow Payout (old)',
            hash: 'h_pay',
            referenceId: const Value('cid_old'),
          ),
        );
        b.insert(
          db.creditTransactions,
          CreditTransactionsCompanion.insert(
            id: 'tx_escrow_release_rel',
            timestamp: DateTime.fromMillisecondsSinceEpoch(base + 2),
            type: 'priorityAccessDebit',
            amount: 15.0,
            description: 'Escrow Release (rel)',
            hash: 'h_rel',
            referenceId: const Value('rel'),
          ),
        );
        // A STALE but never-paid, never-released hold - the case the
        // getEscrowHoldRows listing (RE-W closure) exists for.
        b.insert(
          db.creditTransactions,
          CreditTransactionsCompanion.insert(
            id: 'tx_escrow_hold_stale_0',
            timestamp: DateTime.fromMillisecondsSinceEpoch(base + 3),
            type: 'priorityAccessDebit',
            amount: -7.5,
            description: 'Bounty Escrow Hold (stale)',
            hash: 'h_stale',
            referenceId: const Value('stale'),
          ),
        );
      });
      // Fill past the 100k window with newer rows.
      const pad = 100005;
      for (var chunk = 0; chunk < pad; chunk += 5000) {
        await db.batch((b) {
          for (var i = 0; i < 5000; i++) {
            final n = chunk + i;
            b.insert(
              db.creditTransactions,
              CreditTransactionsCompanion.insert(
                id: 'pad_$n',
                timestamp: DateTime.fromMillisecondsSinceEpoch(base + 100 + n),
                type: 'computeReward',
                amount: 0.0001,
                description: 'pad $n',
                hash: 'hp_$n',
              ),
            );
          }
        });
      }

      final s = CreditService(db: db, initialBalance: 0.0);
      await s.ready;
      // Sanity: the window truncated (SUM fallback) - balance is the
      // full-table sum: -20 +20 +15 -7.5 + pads.
      expect(s.balance, greaterThan(17.0));

      // The durable payout row exists - a re-pay must refuse.
      expect(await db.hasCreditTransaction('tx_bounty_payout_old'), isTrue);
      // …but the dedup rebuild only scans the hydrated window:
      expect(s.awardBountyEscrow(amount: 20.0, bountyId: 'old', cid: 'cid_old'),
          0.0,
          reason: 'payout row is beyond the 100k window — refused '
              'because _paidBountyIds is rebuilt from the targeted '
              'prefix listing, not the truncated replay window');
      // The release dedup missed 'rel' for the same reason - but its
      // hold is also beyond the window so the scan still refuses.
      expect(await s.releaseEscrow(referenceId: 'rel'), 0.0);
      // 'old' was durably PAID - releasing its escrow would be the
      // payout↔refund double-dip; the refusal stands even though the
      // beyond-window hold row is unreachable by the in-memory scan.
      expect(await s.releaseEscrow(referenceId: 'old'), 0.0,
          reason: 'a paid bounty id must NEVER refund — the durable '
              'tx_bounty_payout_old row makes the release refuse; '
              'the stranded-hold bound is documented on releaseEscrow');
      // RE-W CLOSED: the unpaid 'stale' hold lives beyond the replay
      // window but IS reachable through getEscrowHoldRows - a stale
      // cancel now refunds instead of stranding.
      final before = s.balance;
      expect(await s.releaseEscrow(referenceId: 'stale'), 7.5,
          reason: 'the durable hold listing is window-independent — '
              'the beyond-window hold must refund');
      expect(s.balance, before + 7.5);
      // And the release tombstone dedups a repeat attempt.
      expect(await s.releaseEscrow(referenceId: 'stale'), 0.0);
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
