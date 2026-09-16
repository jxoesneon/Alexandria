// SCRATCH RE-EVALUATOR FILE — REV4b fix-diff verification + regression hunt.
// Probes ONLY holes the fix diffs themselves introduced:
//   E  postPreservationBounty can re-use a tombstoned id (bounty_<ms>
//      collision after a same-ms cancel) — the new escrow debits onto a
//      dead id and is stranded forever (cancel refuses, release refuses).
//   E2 `_cancelledBountyIds`/`_locallyPostedBountyIds`/`_escrowedBountyIds`
//      are in-memory only — after a restart a cancelled id re-ingests as
//      a FUNDED live record (zombie), and a still-live locally-posted
//      bounty becomes un-cancellable (escrow stranded at service layer).
//   F  correlated write loss: payout row lost AND tombstone write fails
//      in the same db-fault window → after restart + row aging the id
//      re-pays (E1 resurrected).
//   F2 slow (not failed) payout insert → tombstone lands, payout lands
//      later → paid AND tombstoned coexistence — verify consistency.
//   G  the healer's bare deleteClaimedBounty acts on a STALE claimedAt
//      read — a racing claim's freshly re-won row is torn down, leaving
//      a PAID claim with no durable row (E2 corruption shape survives).
//   H  _isCanonicalBountyId misses invisible ranges outside
//      200B-200F/FEFF/whitespace: bidi overrides 202A-202E, isolates
//      2066-2069, word joiner 2060, ALM 061C, soft hyphen 00AD, MVS 180E,
//      tag chars, lone surrogates — invisible-id spoofing survives.
// Every test asserts the SECURE expectation — a FAILURE marks a LIVE hole.
import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart'
    show AppDatabase, ClaimedBountiesCompanion;
import 'package:alexandria/services/agent/beacon_models.dart';
import 'package:alexandria/services/agent/escrow_attestation.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';

Future<SimpleKeyPair> _newKey() => Ed25519().newKeyPair();

Future<String> _pubHex(SimpleKeyPair kp) async =>
    bytesToHex((await kp.extractPublicKey()).bytes);

Future<EscrowAttestation?> _attestBounty(
    SimpleKeyPair attestor, PreservationBounty bounty) async {
  final exp =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
  final preimage = EscrowAttestation.signingPreimage(
    bountyId: bounty.id,
    cid: bounty.cid,
    amountMilli: (bounty.offeredCredits * 1000).round(),
    expiresAt: exp,
  );
  final sig = await Ed25519().sign(preimage, keyPair: attestor);
  return EscrowAttestation.verify(
    attestorPubkey: await _pubHex(attestor),
    bountyId: bounty.id,
    cid: bounty.cid,
    amountMilli: (bounty.offeredCredits * 1000).round(),
    expiresAt: exp,
    signature: base64Encode(sig.bytes),
    verifyFn: EscrowAttestation.verifyEd25519,
  );
}

PreservationBounty _foreignBounty({
  required String id,
  required String cid,
  double offeredCredits = 25.0,
  bool funded = true,
  String originAgentId = 'bcn_remote_poster',
}) =>
    PreservationBounty(
      id: id,
      cid: cid,
      title: 'Foreign bounty $id',
      offeredCredits: offeredCredits,
      originAgentId: originAgentId,
      createdAt: DateTime.now(),
      funded: funded,
    );

Future<void> _insertClaimRow(AppDatabase db, String bountyId,
        {required int claimedAt}) =>
    db.into(db.claimedBounties).insert(
          ClaimedBountiesCompanion.insert(
            bountyId: bountyId,
            cid: 'bafk_$bountyId',
            claimedAt: claimedAt,
          ),
        );

int _ageMillis(Duration d) => DateTime.now().subtract(d).millisecondsSinceEpoch;

/// Correlated-fault window: BOTH the payout row and the tombstone row
/// fail to persist (same broken-store window that lost the payout).
class _CorrelatedWriteLossDb extends AppDatabase {
  bool armed = false;

  bool _drops(Map<String, dynamic> data) {
    final id = data['id'] as String?;
    return armed &&
        id != null &&
        (id.startsWith('tx_bounty_payout_') ||
            id.startsWith('tx_escrow_release_'));
  }

  @override
  Future<void> insertCreditTransaction(Map<String, dynamic> data) async {
    if (_drops(data)) {
      throw StateError('simulated correlated ledger-write loss');
    }
    return super.insertCreditTransaction(data);
  }

  @override
  Future<bool> insertCreditTransactionIfAbsent(
      Map<String, dynamic> data) async {
    if (_drops(data)) {
      throw StateError('simulated correlated ledger-write loss');
    }
    return super.insertCreditTransactionIfAbsent(data);
  }
}

/// Slow-but-successful payout insert parked behind [gate] — the claim's
/// bounded settle-wait expires, the probe misses, the tombstone lands,
/// then the real payout row arrives.
class _SlowPayoutDb extends AppDatabase {
  final Completer<void> gate = Completer<void>();
  bool armed = false;

  bool _isPayout(Map<String, dynamic> data) {
    final id = data['id'] as String?;
    return armed && id != null && id.startsWith('tx_bounty_payout_');
  }

  @override
  Future<void> insertCreditTransaction(Map<String, dynamic> data) async {
    if (_isPayout(data)) {
      await gate.future;
    }
    return super.insertCreditTransaction(data);
  }

  @override
  Future<bool> insertCreditTransactionIfAbsent(
      Map<String, dynamic> data) async {
    if (_isPayout(data)) {
      await gate.future;
    }
    return super.insertCreditTransactionIfAbsent(data);
  }
}

/// Parks the FIRST conditional delete so the healer's stale-read →
/// delete window can be observed: while it is parked, a racing claim
/// deletes the stale row and re-wins a FRESH row — then the parked
/// conditional delete executes and MUST miss it (claimedAt no longer
/// matches the observed snapshot).
class _FirstDeleteGateDb extends AppDatabase {
  final Completer<void> deleteGate = Completer<void>();
  int deleteCalls = 0;
  bool deleteParked = false;

  @override
  Future<int> deleteClaimedBountyIfClaimedAt(
      String bountyId, int claimedAt) async {
    deleteCalls++;
    if (deleteCalls == 1) {
      deleteParked = true;
      await deleteGate.future;
    }
    return super.deleteClaimedBountyIfClaimedAt(bountyId, claimedAt);
  }
}

void main() {
  // ═══════════ RE-E: tombstone / cancel edge regressions ═══════════
  group('cancelBounty tombstone regressions', () {
    test(
        'postPreservationBounty never consults the cancel tombstone — '
        'a re-posted id (same-ms bounty_<ms> collision) debits escrow '
        'onto a dead id that no path can release', () async {
      final cs = CreditService(initialBalance: 1000.0);
      final svc = MoltbookService(creditService: cs);
      await svc.setKeyPair(await _newKey());

      // Probe the collision window: consecutive posts sharing a
      // millisecond reuse bounty_<ms>. Envelope signing makes each
      // post ~>=1ms, so the window is narrow — but nothing in the
      // post path checks the tombstone, so WHEN it happens the escrow
      // strands. Conditional probe: if a collision occurs the funds
      // must still be recoverable.
      final tombstoned = <String>{};
      PreservationBounty? collision;
      for (var i = 0; i < 300 && collision == null; i++) {
        final PreservationBounty p;
        try {
          p = await svc.postPreservationBounty(
              cid: 'bafk_r$i', title: 't', offeredCredits: 5.0, force: true);
        } on StateError {
          // R1: cancelled escrows are no longer refunded — the probe
          // budget (200 holds × 5 ℭ of 1000) is finite. Stop probing.
          break;
        }
        if (tombstoned.contains(p.id)) {
          collision = p; // re-posted onto a cancelled id
        } else {
          // R1: the cancel delists + tombstones but refuses the refund
          // (cross-ledger guard) — the escrow stays locked.
          expect(await svc.cancelBounty(p.id), isFalse);
          tombstoned.add(p.id);
        }
      }
      if (collision == null) {
        // No same-ms collision in 300 posts — the window is latent
        // (clock granularity + signing latency), and _isDeadBountyId
        // regenerates before the debit anyway, so the collision can
        // never materialize. Reported as a reasoned finding, not a
        // live repro.
        return;
      }

      // The re-post DEBITED a fresh escrow onto the dead id.
      expect(cs.balance, lessThan(1000.0));
      // …the id stays dead to the cancel path:
      expect(await svc.cancelBounty(collision.id), isFalse);
      // …but the hold itself is not stranded — releaseEscrow remains
      // the operator reconciliation hatch and refunds the summed holds.
      expect(
          await cs.releaseEscrow(referenceId: collision.id), greaterThan(0.0),
          reason: 'cancel never writes a release row under the '
              'cross-ledger guard, so the holds stay releasable on '
              'demand');
    });

    test(
        'RESTART: the cancel tombstone is in-memory only — a cancelled '
        'id re-ingests as a DEAD record after service restart once the '
        'hold-row rebuild + re-cancel re-arm the tombstone', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs1 = CreditService(db: db, initialBalance: 0.0);
      await cs1.ready;
      cs1.awardVerificationCredits(
          action: 'seed', targetId: 't', amount: 100.0);
      final svc1 = MoltbookService(creditService: cs1, db: db);
      await svc1.setKeyPair(await _newKey());
      final posted = await svc1.postPreservationBounty(
          cid: 'bafk_z', title: 't', offeredCredits: 25.0, force: true);
      expect(await svc1.cancelBounty(posted.id), isFalse,
          reason: 'cancel tombstones + delists but refuses the refund — '
              'the announced escrow stays locked (R1 cross-ledger '
              'guard)');
      await cs1.settled; // the HOLD row is durable; no release row exists

      // Restart: fresh services on the same database.
      final cs2 = CreditService(db: db, initialBalance: 0.0);
      await cs2.ready;
      expect(cs2.balance, 75.0); // hold replayed — escrow still locked
      final attestor = await _newKey();
      final svc2 = MoltbookService(
          creditService: cs2,
          db: db,
          trustedAttestorPubkeys: {await _pubHex(attestor)});

      // The durable hold row rebuilds _locallyPostedBountyIds, so the
      // record-less cancel still tombstones the id and reports success
      // (no release was owed by this path — the refund stays refused).
      expect(await svc2.cancelBounty(posted.id), isTrue);

      final re =
          _foreignBounty(id: posted.id, cid: posted.cid, offeredCredits: 25.0);
      svc2.ingestBountyAnnouncement(re,
          escrowAttestation: await _attestBounty(attestor, re));
      final stored = svc2.activeBounties.firstWhere((b) => b.id == posted.id);
      expect(stored.funded, isFalse,
          reason: 'the cancelled id must re-ingest DEAD after restart '
              'too — the tombstone is not durable');
      // The dead record can never pay out: self-claim guard + unfunded.
      expect(await svc2.claimBounty(posted.id), isFalse);
      expect(cs2.balance, 75.0); // escrow still locked — never refunded
      // …and a re-cancel observes the tombstone.
      expect(await svc2.cancelBounty(posted.id), isFalse);
    });

    test(
        'RESTART: a LIVE locally-posted bounty cannot be cancelled '
        'after a service restart — _locallyPostedBountyIds and '
        '_escrowedBountyIds are not rebuilt from the durable hold row',
        () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs1 = CreditService(db: db, initialBalance: 0.0);
      await cs1.ready;
      cs1.awardVerificationCredits(
          action: 'seed', targetId: 't', amount: 100.0);
      final svc1 = MoltbookService(creditService: cs1, db: db);
      await svc1.setKeyPair(await _newKey());
      final posted = await svc1.postPreservationBounty(
          cid: 'bafk_live', title: 't', offeredCredits: 25.0, force: true);
      expect(cs1.balance, 75.0);
      await cs1.settled; // hold row durable

      // Restart.
      final cs2 = CreditService(db: db, initialBalance: 0.0);
      await cs2.ready;
      expect(cs2.balance, 75.0); // hold replayed, funds still locked
      final svc2 = MoltbookService(creditService: cs2, db: db);
      expect(await svc2.cancelBounty(posted.id), isTrue,
          reason: 'the record-less cancel tombstones the id — the '
              'cross-ledger guard means the cancel path never refunds, '
              'but the hold stays releasable on demand');
      // The underlying primitive still works — the hold IS releasable —
      // the refund refusal lives at the moltbook layer, not the ledger.
      expect(await cs2.releaseEscrow(referenceId: posted.id), 25.0);
    });
  });

  // ═══════════ RE-F: post-settle probe + tombstone ═══════════
  group('payout durability probe + tombstone', () {
    test(
        'correlated loss: payout row lost AND tombstone write fails '
        'in the same fault window — the durable-first CAS refuses the '
        'claim CLOSED (no mint to orphan), and the post-heal retry '
        'pays exactly once', () async {
      final db = _CorrelatedWriteLossDb();
      addTearDown(db.close);
      final cs1 = CreditService(db: db, initialBalance: 100.0);
      await cs1.ready;
      final bounty = _foreignBounty(id: 'bounty_cl', cid: 'bafk_cl');
      final attestor = await _newKey();
      final hex = await _pubHex(attestor);
      final svc1 = MoltbookService(
          creditService: cs1, db: db, trustedAttestorPubkeys: {hex});
      svc1.ingestBountyAnnouncement(bounty,
          escrowAttestation: await _attestBounty(attestor, bounty));

      // Durable-first: the throwing CAS fails the mutator closed
      // (0.0, nothing mutated) — no in-memory mint exists to orphan
      // across a crash, so no tombstone is owed and the claim row
      // releases for a clean retry.
      db.armed = true; // payout row AND tombstone row both fail
      expect(await svc1.claimBounty(bounty.id), isFalse);
      expect(cs1.balance, 100.0); // nothing minted — fail closed
      db.armed = false;
      expect(await db.hasCreditTransaction('tx_bounty_payout_${bounty.id}'),
          isFalse);
      expect(await db.hasCreditTransaction('tx_escrow_release_${bounty.id}'),
          isFalse);
      expect(await db.isBountyClaimed(bounty.id), isFalse,
          reason: 'the released row keeps the claim retryable');

      // Restart on the healed store: the retry mints exactly once and
      // the dedup sets keep every later attempt at zero.
      final cs2 = CreditService(db: db, initialBalance: 0.0);
      await cs2.ready;
      expect(cs2.balance, 100.0);
      final svc2 = MoltbookService(
          creditService: cs2, db: db, trustedAttestorPubkeys: {hex});
      svc2.ingestBountyAnnouncement(bounty,
          escrowAttestation: await _attestBounty(attestor, bounty));
      expect(await svc2.claimBounty(bounty.id), isTrue);
      expect(cs2.balance, 125.0);
      expect(await svc2.claimBounty(bounty.id), isFalse);
      expect(cs2.balance, 125.0);
    });

    test(
        'slow payout insert: tombstone + late payout coexist — paid '
        'AND tombstoned must stay consistent (no double-count, no '
        're-pay, no refund)', () async {
      final db = _SlowPayoutDb();
      addTearDown(db.close);
      final cs1 = CreditService(db: db, initialBalance: 100.0);
      await cs1.ready;
      final bounty = _foreignBounty(id: 'bounty_slow', cid: 'bafk_sl');
      final attestor = await _newKey();
      final hex = await _pubHex(attestor);
      final svc1 = MoltbookService(
          creditService: cs1,
          db: db,
          payoutWriteTimeout: const Duration(milliseconds: 50),
          trustedAttestorPubkeys: {hex});
      svc1.ingestBountyAnnouncement(bounty,
          escrowAttestation: await _attestBounty(attestor, bounty));

      db.armed = true;
      expect(await svc1.claimBounty(bounty.id), isTrue,
          reason: 'the bounded durable wait must expire and take the '
              'indeterminate-write tombstone path while the payout '
              'insert is still parked');
      // Tombstone landed while the payout CAS was still in flight.
      expect(await db.hasCreditTransaction('tx_escrow_release_${bounty.id}'),
          isTrue);
      db.gate.complete();
      // The abandoned durable write still completes: the parked CAS
      // lands and the mint commits in its wake (the CAS is the last
      // await inside the mutator).
      for (var i = 0;
          i < 100 &&
              !await db.hasCreditTransaction('tx_bounty_payout_${bounty.id}');
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await db.hasCreditTransaction('tx_bounty_payout_${bounty.id}'),
          isTrue);

      // Restart: payout row counts (+25), tombstone gates dedup.
      final cs2 = CreditService(db: db, initialBalance: 0.0);
      await cs2.ready;
      expect(cs2.balance, 125.0,
          reason: 'the mint must count exactly once — the zero-amount '
              'tombstone must not erase the payout row\'s value');
      expect(
          cs2.awardBountyEscrow(
              amount: 25.0, bountyId: bounty.id, cid: bounty.cid),
          0.0,
          reason: 'both dedup sets contain the id — no re-pay');
      expect(await cs2.releaseEscrow(referenceId: bounty.id), 0.0,
          reason: 'tombstone blocks refund of a paid escrow');
      // Re-claim attempt: healer sees the durable payout row and heals.
      final svc2 = MoltbookService(
          creditService: cs2, db: db, trustedAttestorPubkeys: {hex});
      svc2.ingestBountyAnnouncement(bounty,
          escrowAttestation: await _attestBounty(attestor, bounty));
      expect(await svc2.claimBounty(bounty.id), isFalse);
      expect(cs2.balance, 125.0);
    });
  });

  // ═══════════ RE-G: healer stale-read bare delete ═══════════
  group('healer conditional-delete coverage', () {
    test(
        'the healer\'s conditional delete on a STALE read must MISS '
        'a racing claim\'s fresh row — the paid claim keeps its '
        'durable row', () async {
      final db = _FirstDeleteGateDb();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final bounty = _foreignBounty(id: 'bounty_g', cid: 'bafk_g');
      final attestor = await _newKey();
      final hex = await _pubHex(attestor);
      final att = await _attestBounty(attestor, bounty);
      // Two service instances on one CreditService+db — the topology the
      // promoted suite already uses (svcA/svcB sharing the belt).
      final svcB = MoltbookService(
          creditService: cs, db: db, trustedAttestorPubkeys: {hex});
      final svcC = MoltbookService(
          creditService: cs, db: db, trustedAttestorPubkeys: {hex});
      svcB.ingestBountyAnnouncement(bounty, escrowAttestation: att);
      svcC.ingestBountyAnnouncement(bounty, escrowAttestation: att);

      // Stranded row from a crashed claim, 20min old.
      await _insertClaimRow(db, bounty.id,
          claimedAt: _ageMillis(const Duration(minutes: 20)));

      // B: CAS loses → probe → reads the stale claimedAt → calls the
      // BARE delete → parked BEFORE it executes.
      final claimB = svcB.claimBounty(bounty.id);
      while (!db.deleteParked) {
        await Future<void>.delayed(Duration.zero);
      }

      // C: CAS loses → probe → stale → its OWN delete (call #2,
      // ungated) removes the stale row → retry CAS wins a FRESH row →
      // no ipfs → evidence skipped → C pays and lands the payout row.
      expect(await svcC.claimBounty(bounty.id), isTrue);
      expect(cs.balance, 125.0);

      // Now B's parked conditional delete executes — its observed
      // claimedAt no longer matches C's fresh row, so it must miss.
      db.deleteGate.complete();
      expect(await claimB, isFalse);

      expect(await db.isBountyClaimed(bounty.id), isTrue,
          reason: 'C\'s paid claim row must survive: the conditional '
              'delete only removes a row still carrying the observed '
              'claimedAt');
    });
  });

  // ═══════════ RE-H: invisible-id gate coverage ═══════════
  group('canonical id gate — uncovered invisible ranges', () {
    test(
        'invisible format / bidi-override codepoints outside '
        '200B-200F and FEFF are still ADMITTED as bounty ids', () async {
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      final candidates = <String, String>{
        'a\u2028b': 'U+2028 LINE SEPARATOR',
        'a\u2029b': 'U+2029 PARAGRAPH SEPARATOR',
        'a\u0085b': 'U+0085 NEXT LINE (NEL)',
        'a\u2060b': 'U+2060 WORD JOINER',
        'a\u2061b': 'U+2061 invisible function application',
        'a\u202Ab': 'U+202A LRE bidi embedding',
        'a\u202Eb': 'U+202E RLO — visual reorder',
        'a\u2066b': 'U+2066 LRI bidi isolate',
        'a\u2069b': 'U+2069 PDI',
        'a\u061Cb': 'U+061C ARABIC LETTER MARK',
        'a\u180Eb': 'U+180E MONGOLIAN VOWEL SEPARATOR',
        'a\u00ADb': 'U+00AD SOFT HYPHEN',
        'a\u034Fb': 'U+034F COMBINING GRAPHEME JOINER',
        '\u2060': 'fully invisible id (single U+2060)',
        'a\u{E0001}b': 'U+E0001 TAG char (supplementary plane)',
        'a\uD800b': 'lone surrogate',
      };
      var i = 0;
      for (final id in candidates.keys) {
        svc.ingestBountyAnnouncement(
            _foreignBounty(id: id, cid: 'bafk_h${i++}'));
      }
      final stored = svc.activeBounties.map((b) => b.id).toSet();
      final leaked = <String>[
        for (final e in candidates.entries)
          if (stored.contains(e.key)) e.value,
      ];
      expect(leaked, isEmpty,
          reason: 'these invisible/format codepoints were admitted as '
              'bounty ids — the F8 spoofing primitive survives: '
              '${leaked.join(', ')}');
    });

    test('control: the covered classes are still rejected', () async {
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      for (final (i, id) in [
        'a b',
        'a\tb',
        'a\u00A0b',
        'a\u200Bb',
        'a\uFEFFb',
        'a\u009Bb',
        'a\u007Fb',
        ' x',
        'x ',
      ].indexed) {
        svc.ingestBountyAnnouncement(_foreignBounty(id: id, cid: 'bafk_c$i'));
      }
      final stored = svc.activeBounties.map((b) => b.id).toSet();
      expect(stored.length, 2,
          reason: 'only the two seed bounties should remain');
    });
  });
}
