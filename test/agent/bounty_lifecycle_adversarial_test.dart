// REV4b ADVERSARIAL EVALUATION — exploit tests attacking the just-landed
// REV4 review changes: the CAS-loss claim healer, the startup
// claimed_bounties sweep, cancelBounty/releaseEscrow, the canonical
// bounty-id gate, the bounded _bounties registry, the verified
// ingestBountyEnvelope seam, the SecurityOverviewService PoR
// delegation, and the PoR pending-challenge cap.
//
// Convention: every test asserts the SECURE expectation. A failing
// test is a LIVE exploit; a passing test is a dead attack class.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:alexandria/data/database.dart'
    show AppDatabase, ClaimedBounty, ClaimedBountiesCompanion;
import 'package:alexandria/models/security_models.dart';
import 'package:alexandria/providers/security_providers.dart';
import 'package:alexandria/services/agent/beacon_models.dart';
import 'package:alexandria/services/agent/escrow_attestation.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/proof_of_retrievability_service.dart';

// ───────────────────────────── fakes ─────────────────────────────

/// IpfsService whose blockstore read parks until [gate] completes,
/// then yields [payload]. Lets a claim freeze inside the evidence
/// phase — i.e. between winning the durable CAS and the payout.
class _GatedIpfs extends IpfsService {
  _GatedIpfs(super.ref);
  final Completer<void> gate = Completer<void>();
  Uint8List payload = Uint8List.fromList(<int>[1]);
  int calls = 0;

  @override
  Stream<Uint8List> getFile(String cid) async* {
    calls++;
    await gate.future;
    yield payload;
  }
}

final _gatedIpfsProvider = Provider<IpfsService>((ref) => _GatedIpfs(ref));

/// The durable payout-row write is LOST (throws → swallowed by
/// CreditService._persistWrite's catchError). Every other write lands.
/// Models sqlite dropping exactly the row the crash-window reconciler
/// treats as "claim durably settled" proof. BOTH write paths must be
/// intercepted: deterministic-id rows (payout/release) persist through
/// the insertCreditTransactionIfAbsent durable gate, everything else
/// through plain insertCreditTransaction.
class _PayoutWriteLostDb extends AppDatabase {
  @override
  Future<void> insertCreditTransaction(Map<String, dynamic> data) async {
    final id = data['id'] as String?;
    if (id != null && id.startsWith('tx_bounty_payout_')) {
      throw StateError('simulated payout-row write loss');
    }
    return super.insertCreditTransaction(data);
  }

  @override
  Future<bool> insertCreditTransactionIfAbsent(
      Map<String, dynamic> data) async {
    final id = data['id'] as String?;
    if (id != null && id.startsWith('tx_bounty_payout_')) {
      throw StateError('simulated payout-row write loss');
    }
    return super.insertCreditTransactionIfAbsent(data);
  }
}

/// The payout-row write never completes → CreditService.settled never
/// resolves → claimBounty hangs forever holding the in-flight mark AND
/// the durable claim row.
class _PayoutWriteHangsDb extends AppDatabase {
  @override
  Future<void> insertCreditTransaction(Map<String, dynamic> data) {
    final id = data['id'] as String?;
    if (id != null && id.startsWith('tx_bounty_payout_')) {
      return Completer<void>().future; // never completes
    }
    return super.insertCreditTransaction(data);
  }

  @override
  Future<bool> insertCreditTransactionIfAbsent(
      Map<String, dynamic> data) {
    final id = data['id'] as String?;
    if (id != null && id.startsWith('tx_bounty_payout_')) {
      return Completer<bool>().future; // never completes
    }
    return super.insertCreditTransactionIfAbsent(data);
  }
}

/// Gates the FIRST hasCreditTransaction call so the startup sweep can
/// be parked mid-iteration while a claim re-heals the same bounty id.
class _SweepProbeGateDb extends AppDatabase {
  int probeCalls = 0;
  bool firstProbeParked = false;
  final Completer<void> probeGate = Completer<void>();

  @override
  Future<bool> hasCreditTransaction(String id) async {
    probeCalls++;
    if (probeCalls == 1) {
      firstProbeParked = true;
      await probeGate.future;
    }
    return super.hasCreditTransaction(id);
  }
}

/// Gates isBountyClaimed so a cancelBounty call can be frozen between
/// its positional index computation and `_bounties.removeAt(index)`.
class _GatedClaimCheckDb extends AppDatabase {
  final Completer<void> gate = Completer<void>();
  int calls = 0;

  @override
  Future<bool> isBountyClaimed(String bountyId) async {
    calls++;
    await gate.future;
    return super.isBountyClaimed(bountyId);
  }
}

/// isBountyClaimed throws — models transient sqlite failure on the
/// cancelBounty fail-closed claim-state read.
class _ThrowingClaimCheckDb extends AppDatabase {
  @override
  Future<bool> isBountyClaimed(String bountyId) async =>
      throw StateError('simulated claim-state read failure');
}

/// The sweep's listing query throws — the sweep must swallow it and
/// never surface an unhandled async error from the constructor's
/// fire-and-forget unawaited future.
class _ThrowingSweepDb extends AppDatabase {
  @override
  Future<List<ClaimedBounty>> getClaimedBountiesOlderThan(
          int epochMillis) async =>
      throw StateError('simulated sweep listing failure');
}

/// Probe/age-read failure fake for E3.
class _ThrowingProbeDb extends AppDatabase {
  bool failProbe = true;
  bool failAgeRead = false;

  @override
  Future<bool> hasCreditTransaction(String id) async {
    if (failProbe) throw StateError('simulated probe failure');
    return super.hasCreditTransaction(id);
  }

  @override
  Future<int?> getClaimedBountyClaimedAt(String bountyId) async {
    if (failAgeRead) throw StateError('simulated age-read failure');
    return super.getClaimedBountyClaimedAt(bountyId);
  }
}

/// Healer-path throwing delete for E5. The healer now deletes through
/// the ownership-conditional DAO (RE-REV4b G), so BOTH delete entry
/// points throw here — a delete that can't land must leave the stale
/// row standing and the CAS retry must lose, returning false.
class _HealerThrowingDeleteDb extends AppDatabase {
  @override
  Future<void> deleteClaimedBounty(String bountyId) async =>
      throw StateError('simulated delete failure');

  @override
  Future<int> deleteClaimedBountyIfClaimedAt(
          String bountyId, int claimedAt) async =>
      throw StateError('simulated delete failure');
}

// ───────────────────────────── helpers ─────────────────────────────

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

int _ageMillis(Duration d) =>
    DateTime.now().subtract(d).millisecondsSinceEpoch;

Future<void> _pump([int n = 20]) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  // ═══════════════════ ITEM 1: CAS-loss healer ═══════════════════
  group('claimBounty CAS-loss healer', () {
    test('E1: a lost payout write refuses the claim CLOSED — the '
        'durable-first CAS mints nothing, releases the claim row, and '
        'leaves the bounty cleanly retryable', () async {
      final db = _PayoutWriteLostDb();
      addTearDown(db.close);
      final cs1 = CreditService(db: db, initialBalance: 100.0);
      await cs1.ready;
      final bounty = _foreignBounty(id: 'bounty_p1', cid: 'bafk_p1');
      final attestor = await _newKey();
      final att = await _attestBounty(attestor, bounty);
      final svc1 = MoltbookService(
          creditService: cs1,
          db: db,
          trustedAttestorPubkeys: {await _pubHex(attestor)});
      svc1.ingestBountyAnnouncement(bounty, escrowAttestation: att);

      // awardBountyEscrowDurable commits the payout row through the
      // CAS BEFORE minting — the write throws, so the mutator fails
      // closed (0.0, nothing mutated) and the claim refuses: no mint,
      // no claim row, no tombstone (there is nothing to tombstone —
      // the mint never happened). This replaces the old mint-first /
      // probe-later path whose crash window needed the tombstone fix.
      expect(await svc1.claimBounty(bounty.id), isFalse);
      expect(cs1.balance, 100.0);
      expect(await db.isBountyClaimed(bounty.id), isFalse,
          reason: 'our claim row was released — the claim is retryable');
      expect(
          await db.hasCreditTransaction('tx_bounty_payout_${bounty.id}'),
          isFalse);
      expect(
          await db
              .hasCreditTransaction('tx_escrow_release_${bounty.id}'),
          isFalse,
          reason: 'nothing minted → no spent tombstone is owed');

      // A retry while the store still loses the write fails closed the
      // same way — and the record is neither poisoned nor claimed.
      expect(await svc1.claimBounty(bounty.id), isFalse);
      expect(cs1.balance, 100.0);
      expect(svc1.activeBounties.any((b) => b.id == bounty.id), isTrue);
    });

    test('E2: healer deletes a row owned by a LIVE >15min in-flight '
        'claim; the dedup-loser then deletes the WINNER\'s row — a paid '
        'claim ends with NO durable claim row', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final gated = container.read(_gatedIpfsProvider) as _GatedIpfs;
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final bounty = _foreignBounty(id: 'bounty_p2', cid: 'bafk_p2');
      final attestor = await _newKey();
      final att = await _attestBounty(attestor, bounty);
      final hex = await _pubHex(attestor);
      final svcA = MoltbookService(
          creditService: cs,
          db: db,
          ipfsService: gated,
          trustedAttestorPubkeys: {hex});
      final svcB = MoltbookService(
          creditService: cs, db: db, trustedAttestorPubkeys: {hex});
      svcA.ingestBountyAnnouncement(bounty, escrowAttestation: att);
      svcB.ingestBountyAnnouncement(bounty, escrowAttestation: att);

      // A wins the CAS and parks in the (stallable, unbounded) evidence
      // phase.
      final claimA = svcA.claimBounty(bounty.id);
      while (!await db.isBountyClaimed(bounty.id)) {
        await Future<void>.delayed(Duration.zero);
      }
      // Backdate A's live row past the stale TTL — B's healer then
      // observes the row's REAL claimedAt, so its ownership-conditional
      // delete still matches (RE-REV4b G). A faked age READ could never
      // authorize the delete.
      await (db.update(db.claimedBounties)
            ..where((t) => t.bountyId.equals(bounty.id)))
          .write(ClaimedBountiesCompanion(
              claimedAt:
                  Value(_ageMillis(const Duration(minutes: 20)))));
      // B: CAS loses → no payout → genuinely stale → deletes A's row →
      // retry CAS wins → no ipfs → pays out.
      expect(await svcB.claimBounty(bounty.id), isTrue);
      expect(cs.balance, 125.0); // single pay — dedup belt holds

      // A's evidence now completes → awardBountyEscrow refused by the
      // belt → A deletes the row — WHICH IS NOW B's WON ROW.
      gated.gate.complete();
      expect(await claimA, isFalse);
      expect(
        await db.isBountyClaimed(bounty.id),
        isTrue,
        reason: 'the paid claim\'s durable row must survive — the '
            'reconciler + restart dedup rely on it',
      );
    });

    test('E3: throwing probes fail closed — row left standing, mark '
        'released, record unpoisoned', () async {
      final db = _ThrowingProbeDb();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final bounty = _foreignBounty(id: 'bounty_p3', cid: 'bafk_p3');
      final attestor = await _newKey();
      final svc = MoltbookService(
          creditService: cs,
          db: db,
          trustedAttestorPubkeys: {await _pubHex(attestor)});
      svc.ingestBountyAnnouncement(bounty,
          escrowAttestation: await _attestBounty(attestor, bounty));
      await db.insertClaimedBounty(bounty.id, bounty.cid);

      expect(await svc.claimBounty(bounty.id), isFalse);
      expect(await db.isBountyClaimed(bounty.id), isTrue);
      expect(svc.activeBounties.any((b) => b.id == bounty.id), isTrue);
      // Throwing claimedAt read: same conservative direction.
      db.failProbe = false;
      db.failAgeRead = true;
      expect(await svc.claimBounty(bounty.id), isFalse);
      expect(await db.isBountyClaimed(bounty.id), isTrue);
      expect(cs.balance, 100.0);
    });

    test('E4: a never-completing payout write cannot park claimBounty '
        'forever — the bounded wait expires into the '
        'indeterminate-write path: spent tombstone, standing claim '
        'row, dead id', () async {
      final db = _PayoutWriteHangsDb();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final bounty = _foreignBounty(id: 'bounty_p4', cid: 'bafk_p4');
      final attestor = await _newKey();
      final svc = MoltbookService(
          creditService: cs,
          db: db,
          payoutWriteTimeout: const Duration(milliseconds: 50),
          trustedAttestorPubkeys: {await _pubHex(attestor)});
      svc.ingestBountyAnnouncement(bounty,
          escrowAttestation: await _attestBounty(attestor, bounty));

      var done = false;
      unawaited(svc.claimBounty(bounty.id).then((_) => done = true));
      for (var i = 0; i < 100 && !done; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(done, isTrue,
          reason:
              'a hung ledger write must not park a won claim forever');
      // The durable claim row stands as the settlement marker, the
      // spent tombstone landed, and the id is dead to re-claims.
      expect(await db.isBountyClaimed(bounty.id), isTrue);
      expect(
          await db
              .hasCreditTransaction('tx_escrow_release_${bounty.id}'),
          isTrue,
          reason: 'the indeterminate write dead-marks the id — '
              'un-payable and un-refundable either way it resolves');
      expect(await svc.claimBounty(bounty.id), isFalse);
    });

    test('E5: stale-row delete throws → retry CAS loses → returns '
        'false without propagating, mark released', () async {
      final db = _HealerThrowingDeleteDb();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final bounty = _foreignBounty(id: 'bounty_p5', cid: 'bafk_p5');
      final attestor = await _newKey();
      final svc = MoltbookService(
          creditService: cs,
          db: db,
          trustedAttestorPubkeys: {await _pubHex(attestor)});
      svc.ingestBountyAnnouncement(bounty,
          escrowAttestation: await _attestBounty(attestor, bounty));
      await _insertClaimRow(db, bounty.id,
          claimedAt: _ageMillis(const Duration(minutes: 20)));

      expect(await svc.claimBounty(bounty.id), isFalse);
      // A later attempt hits the same path cleanly — no leaked mark.
      expect(await svc.claimBounty(bounty.id), isFalse);
      expect(cs.balance, 100.0);
    });
  });

  // ═══════════════════ ITEM 2: startup sweep ═══════════════════
  group('startup reconciliation sweep', () {
    test('E6: the sweep deletes a claim row RE-INSERTED by an '
        'in-flight claimBounty healer — its stale-set snapshot is not '
        're-validated before delete (claim pays with no durable row)',
        () async {
      final db = _SweepProbeGateDb();
      addTearDown(db.close);
      await _insertClaimRow(db, 'bounty_sweeprobe',
          claimedAt: _ageMillis(const Duration(minutes: 20)));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final gated = container.read(_gatedIpfsProvider) as _GatedIpfs;
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final bounty =
          _foreignBounty(id: 'bounty_sweeprobe', cid: 'bafk_sw');
      final attestor = await _newKey();
      final svc = MoltbookService(
          creditService: cs,
          db: db,
          ipfsService: gated,
          trustedAttestorPubkeys: {await _pubHex(attestor)});
      svc.ingestBountyAnnouncement(bounty,
          escrowAttestation: await _attestBounty(attestor, bounty));

      // Let the sweep reach its parked per-row probe FIRST (it has
      // already snapshotted the stale row).
      while (!db.firstProbeParked) {
        await Future<void>.delayed(Duration.zero);
      }
      // Now the claim: CAS loses → probe (call #2, ungated) → stale →
      // delete → retry CAS wins a FRESH row → parks in gated evidence.
      var done = false;
      bool? result;
      unawaited(svc.claimBounty(bounty.id).then((r) {
        result = r;
        done = true;
      }));
      for (var i = 0; i < 50 && gated.calls == 0; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(gated.calls, greaterThan(0),
          reason: 'claim must reach the evidence phase on a won retry');

      // Release the sweep's probe → it deletes the claim's NEW row.
      db.probeGate.complete();
      await _pump();
      // Release the evidence gate → claim pays and reports won.
      gated.gate.complete();
      for (var i = 0; i < 50 && !done; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(done, isTrue);
      expect(result, isTrue);
      expect(cs.balance, 125.0);
      // EXPLOIT ASSERTION: the durable claim row must exist for a won
      // claim — the sweep deleted it out from under the in-flight claim.
      expect(await db.isBountyClaimed(bounty.id), isTrue,
          reason: 'sweep deleted a live claim\'s freshly re-inserted '
              'row — the stale snapshot was never re-validated');
    });

    test('E7: sweep boundary — a row just inside the TTL is kept, one '
        'just past it is swept', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      await _insertClaimRow(db, 'bounty_edge_in',
          claimedAt: _ageMillis(
              const Duration(minutes: 15) - const Duration(seconds: 1)));
      await _insertClaimRow(db, 'bounty_edge_out',
          claimedAt: _ageMillis(
              const Duration(minutes: 15) + const Duration(seconds: 1)));
      final cs = CreditService(initialBalance: 100.0);
      MoltbookService(creditService: cs, db: db);
      await _pump(30);
      expect(await db.isBountyClaimed('bounty_edge_in'), isTrue);
      expect(await db.isBountyClaimed('bounty_edge_out'), isFalse);
    });

    test('E8: throwing sweep listing is swallowed — no unhandled async '
        'error, construction unaffected', () async {
      final db = _ThrowingSweepDb();
      addTearDown(db.close);
      final cs = CreditService(initialBalance: 100.0);
      MoltbookService(creditService: cs, db: db);
      await _pump(20); // an unhandled sweep error would fail this test
    });
  });

  // ═══════════════════ ITEM 3: cancelBounty ═══════════════════
  group('cancelBounty', () {
    test('E9: stale positional index across the isBountyClaimed await '
        '— an ingest during the await shifts the list and cancel '
        'removes the WRONG bounty while stripping the target\'s '
        'self-claim tombstone; the target then PAYS OUT on already-'
        'released escrow after key rotation', () async {
      final db = _GatedClaimCheckDb();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final svc = MoltbookService(creditService: cs, db: db);
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_own', title: 't', offeredCredits: 25.0, force: true);
      expect(cs.balance, 75.0);
      // Registry: [posted, seed1, seed2] — posted at index 0.

      final cancel = svc.cancelBounty(posted.id);
      while (db.calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      // While the claim-state read is parked, ingest shifts indices.
      svc.ingestBountyAnnouncement(
          _foreignBounty(id: 'bounty_victim', cid: 'bafk_victim'));
      db.gate.complete();
      expect(await cancel, isFalse,
          reason: 'the cancel completes (delist + tombstone) but the '
              'refund is refused by the cross-ledger guard');
      expect(cs.balance, 75.0); // escrow stays locked, never refunded

      // Rotate the local key: the cancelled bounty is still listed
      // (the stale index removed a DIFFERENT record) but its
      // _locallyPostedBountyIds tombstone is stripped — the
      // current-identity self-claim guard is the only bar left, and
      // rotation defeats it.
      await svc.setKeyPair(await _newKey());
      final relClaim = await svc.claimBounty(posted.id);
      expect(relClaim, isFalse,
          reason: 'locked escrow paid out again = mint from nothing');
      expect(cs.balance, 75.0);
      // Correct behavior: the cancelled record is gone, and ONLY it.
      expect(svc.activeBounties.any((b) => b.id == posted.id), isFalse,
          reason: 'the cancelled bounty should be delisted');
      expect(svc.activeBounties.any((b) => b.id == 'bounty_victim'),
          isTrue,
          reason: 'an unrelated bounty was delisted by the stale index');
    });

    test('E10: two concurrent cancels of the same id BOTH return true '
        'and the second evicts an innocent bounty (removeAt on a stale '
        'index)', () async {
      final db = _GatedClaimCheckDb();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final svc = MoltbookService(creditService: cs, db: db);
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_dc', title: 't', offeredCredits: 25.0, force: true);

      final c1 = svc.cancelBounty(posted.id);
      final c2 = svc.cancelBounty(posted.id);
      while (db.calls < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      db.gate.complete();
      final r1 = await c1;
      final r2 = await c2;
      expect(r1, isFalse,
          reason: 'the winning cancel refuses the refund (cross-ledger '
              'guard) — the announced escrow stays locked');
      expect(r2, isFalse,
          reason: 'a second concurrent cancel must not report success');
      // The second cancel's stale removeAt(0) evicted a seed bounty.
      expect(
          svc.activeBounties.any((b) => b.id == 'bounty_1001') ||
              svc.activeBounties.any((b) => b.id == 'bounty_1002'),
          isTrue,
          reason: 'an unrelated bounty was silently delisted');
      expect(cs.balance, 75.0); // no refund ever lands
    });

    test('E11: cancel → re-ingest same id (foreign origin, trusted '
        'attestation) → claim → escrow released AND payout awarded — '
        'the cancelled id\'s tombstone was removed so nothing stops '
        'the re-announcement, no rotation needed', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final attestor = await _newKey();
      final svc = MoltbookService(
          creditService: cs,
          db: db,
          trustedAttestorPubkeys: {await _pubHex(attestor)});
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_reingest',
          title: 't',
          offeredCredits: 25.0,
          force: true);
      expect(cs.balance, 75.0);
      expect(await svc.cancelBounty(posted.id), isFalse,
          reason: 'cancel tombstones + delists but refuses the refund — '
              'the announced escrow stays locked (R1)');
      expect(cs.balance, 75.0);

      // Any relayer re-announces the id with a foreign origin claim +
      // a trusted attestation binding id/cid/amount.
      final reannounced = _foreignBounty(
          id: posted.id, cid: posted.cid, offeredCredits: 25.0);
      svc.ingestBountyAnnouncement(reannounced,
          escrowAttestation: await _attestBounty(attestor, reannounced));
      expect(svc.activeBounties.any((b) => b.id == posted.id), isTrue);

      final claim = await svc.claimBounty(posted.id);
      expect(claim, isFalse,
          reason: 'the escrow for this id stays locked — '
              'paying it mints unbacked value');
      expect(cs.balance, 75.0);
    });

    test('E12: fail-closed claim-state read — a throwing '
        'isBountyClaimed must refuse the cancel and leave bounty + '
        'escrow untouched', () async {
      final db = _ThrowingClaimCheckDb();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final svc = MoltbookService(creditService: cs, db: db);
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_fc', title: 't', offeredCredits: 25.0, force: true);
      expect(await svc.cancelBounty(posted.id), isFalse);
      expect(cs.balance, 75.0);
      expect(svc.activeBounties.any((b) => b.id == posted.id), isTrue);
    });

    test('E13: a funded flood can NEVER evict a locally-posted bounty '
        '— local escrow is protected and stays cancellable', () async {
      final cs = CreditService(initialBalance: 100.0);
      final attestor = await _newKey();
      final svc = MoltbookService(
          creditService: cs,
          trustedAttestorPubkeys: {await _pubHex(attestor)});
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_evict', title: 't', offeredCredits: 25.0,
          force: true);
      expect(cs.balance, 75.0);

      // Flood with attested funded announcements — the local record is
      // eviction-protected because its id is in _locallyPostedBountyIds.
      for (var i = 0; i < 520; i++) {
        final b = _foreignBounty(id: 'fl_$i', cid: 'bafk_fl_$i');
        svc.ingestBountyAnnouncement(b,
            escrowAttestation: await _attestBounty(attestor, b));
      }
      expect(svc.activeBounties.any((b) => b.id == posted.id), isTrue,
          reason: 'locally-posted records are never eviction '
              'candidates — their escrow must stay reachable');

      expect(await svc.cancelBounty(posted.id), isFalse,
          reason: 'the escrow stays reachable — the cancel path delists '
              'it, but the cross-ledger guard refuses the refund');
      expect(cs.balance, 75.0);
    });
  });

  // ═══════════ ITEM 4: canonical bounty-id gate ═══════════
  group('canonical bounty-id rejection', () {
    test('E14: boundary — 128 chars admitted, 129 dropped; control '
        'chars at edges and interior rejected', () async {
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      svc.ingestBountyAnnouncement(
          _foreignBounty(id: 'b' * 128, cid: 'bafk_128'));
      svc.ingestBountyAnnouncement(
          _foreignBounty(id: 'b' * 129, cid: 'bafk_129'));
      svc.ingestBountyAnnouncement(
          _foreignBounty(id: 'x', cid: 'bafk_c1'));
      svc.ingestBountyAnnouncement(
          _foreignBounty(id: 'ab', cid: 'bafk_del'));
      svc.ingestBountyAnnouncement(
          _foreignBounty(id: '\tx', cid: 'bafk_tab'));
      final ids = svc.activeBounties.map((b) => b.id).toSet();
      expect(ids.contains('b' * 128), isTrue);
      expect(ids.contains('b' * 129), isFalse);
      expect(ids.contains('x'), isFalse);
      expect(ids.contains('ab'), isFalse);
      expect(ids.contains('\tx'), isFalse);
    });

    test('E15: unicode edge cases — interior NBSP / zero-width space / '
        'C1 controls are all REJECTED (post-fix the gate covers '
        'C0+C1+DEL, invisible format chars, and any whitespace)', () async {
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      svc.ingestBountyAnnouncement(
          _foreignBounty(id: '\u00A0edge', cid: 'bafk_nbsp_edge'));
      svc.ingestBountyAnnouncement(
          _foreignBounty(id: 'a\u00A0b', cid: 'bafk_nbsp_mid'));
      svc.ingestBountyAnnouncement(
          _foreignBounty(id: 'a\u200Bb', cid: 'bafk_zwsp'));
      svc.ingestBountyAnnouncement(
          _foreignBounty(id: 'a\u009Bb', cid: 'bafk_c1ctrl'));
      final ids = svc.activeBounties.map((b) => b.id).toSet();
      expect(ids.contains('\u00A0edge'), isFalse);
      expect(ids.contains('a\u00A0b'), isFalse);
      expect(ids.contains('a\u200Bb'), isFalse);
      expect(ids.contains('a\u009Bb'), isFalse);
    });
  });

  // ═══════════ ITEM 5: bounded _bounties registry ═══════════
  group('bounded registry', () {
    test('E16: unfunded flood can never evict a funded LOCAL bounty — '
        'only funded+attested flood can (see E13 for the consequence)',
        () async {
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_loc', title: 't', offeredCredits: 25.0,
          force: true);
      for (var i = 0; i < 600; i++) {
        svc.ingestBountyAnnouncement(_foreignBounty(
            id: 'uf_$i', cid: 'bafk_uf_$i', funded: false));
      }
      // Unfunded spam only evicts unfunded records — the funded local
      // bounty survives and stays reachable by the cancel path (which
      // delists it while the cross-ledger guard refuses the refund).
      expect(svc.activeBounties.any((b) => b.id == posted.id), isTrue);
      expect(await svc.cancelBounty(posted.id), isFalse);
      expect(cs.balance, 75.0);
    });
  });

  // ═══════════ ITEM 6: ingestBountyEnvelope seam ═══════════
  group('ingestBountyEnvelope', () {
    Future<BeaconEnvelope> envFor(SimpleKeyPair kp, PreservationBounty b,
            {String kind = 'preservation_bounty'}) =>
        BeaconEnvelope.create(kind: kind, keyPair: kp, payload: b.toJson());

    test('E17: payload lies — is_claimed:true + funded:true with NO '
        'attestation must be stored unfunded and unclaimed', () async {
      final poster = await _newKey();
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      final pub = await poster.extractPublicKey();
      final bounty = PreservationBounty(
        id: 'bounty_lie',
        cid: 'bafk_lie',
        title: 't',
        offeredCredits: 25.0,
        originAgentId: BeaconEnvelope.deriveAgentId(pub.bytes),
        createdAt: DateTime.now(),
        isClaimed: true, // wire lie
        funded: true, // wire lie
      );
      await svc.ingestBountyEnvelope(await envFor(poster, bounty));
      final stored =
          svc.activeBounties.firstWhere((b) => b.id == 'bounty_lie');
      expect(stored.funded, isFalse);
      // An unfunded record must refuse payout.
      expect(await svc.claimBounty('bounty_lie'), isFalse);
      expect(cs.balance, 100.0);
    });

    test('E18: attestation bound to a DIFFERENT bounty id passed '
        'alongside a valid envelope → stored unfunded', () async {
      final poster = await _newKey();
      final attestor = await _newKey();
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(
          creditService: cs,
          trustedAttestorPubkeys: {await _pubHex(attestor)});
      final pub = await poster.extractPublicKey();
      final bounty = _foreignBounty(
        id: 'bounty_env_misbind',
        cid: 'bafk_misbind',
        originAgentId: BeaconEnvelope.deriveAgentId(pub.bytes),
      );
      final other = _foreignBounty(id: 'bounty_other', cid: 'bafk_other');
      final wrongAtt = await _attestBounty(attestor, other);
      await svc.ingestBountyEnvelope(await envFor(poster, bounty),
          escrowAttestation: wrongAtt);
      final stored = svc.activeBounties
          .firstWhere((b) => b.id == 'bounty_env_misbind');
      expect(stored.funded, isFalse);
      expect(await svc.claimBounty('bounty_env_misbind'), isFalse);
    });

    test('E19: moltbook_post kind is admitted (it is how posts carry '
        'bounty payloads today); fully uppercase origin spelling of '
        'the signer\'s agent id binds canonically', () async {
      final poster = await _newKey();
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      final pub = await poster.extractPublicKey();
      final bounty = _foreignBounty(
        id: 'bounty_post_kind',
        cid: 'bafk_pk',
        originAgentId:
            BeaconEnvelope.deriveAgentId(pub.bytes).toUpperCase(),
      );
      await svc.ingestBountyEnvelope(
          await envFor(poster, bounty, kind: 'moltbook_post'));
      expect(svc.activeBounties.any((b) => b.id == 'bounty_post_kind'),
          isTrue);
    });

    test('E20: non-string id / malformed payload variants are dropped '
        'without throwing', () async {
      final poster = await _newKey();
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      for (final payload in <Map<String, dynamic>>[
        {'id': 42, 'cid': 'x', 'title': 't', 'offered_credits': 1.0},
        {'id': 'x', 'cid': 'x', 'title': 't'}, // missing offered_credits
        {'id': null},
      ]) {
        final env = await BeaconEnvelope.create(
            kind: 'preservation_bounty',
            keyPair: poster,
            payload: payload);
        await svc.ingestBountyEnvelope(env); // must not throw
      }
      expect(svc.activeBounties.length, 2); // only seeds
    });
  });

  // ═══ ITEM 7+8: SecurityOverview delegation + PoR cap ═══
  group('PoR pending-challenge cap + overview delegation', () {
    test('E21: a legit pending challenge is evicted by flood → proof '
        'unanswerable (availability trade-off — by design but '
        'observable)', () {
      final now = DateTime(2026, 1, 1);
      final c = ProviderContainer(overrides: [
        proofOfRetrievabilityServiceProvider.overrideWith(
            (ref) => ProofOfRetrievabilityService(ref, now: () => now)),
      ]);
      addTearDown(c.dispose);
      final svc = c.read(proofOfRetrievabilityServiceProvider);
      final legit = svc.issueChallenge(cid: 'legit', totalChunks: 1);
      final data = Uint8List.fromList(<int>[1, 2, 3]);
      final proof = svc.generateProof(challenge: legit, chunkData: data);
      for (var i = 0; i < 300; i++) {
        svc.issueChallenge(cid: 'flood_$i', totalChunks: 1);
      }
      expect(svc.pendingChallengeCount, 256);
      // The legit challenge was evicted before anyone could answer it.
      expect(
          svc.verifyProof(
              proof: proof,
              expectedChunkData: data,
              proverPeerId: 'peer'),
          isFalse);
    });

    test('E22: SecurityOverviewService.verifyChallenge consults the '
        'PoR service map only — a live issued challenge verifies '
        'through delegation and is single-consumption; an unknown id '
        'refuses', () async {
      final container = ProviderContainer(overrides: [
        ipfsServiceProvider
            .overrideWith((ref) => _GatedIpfs(ref)..gate.complete()),
      ]);
      addTearDown(container.dispose);
      final overview = container.read(securityOverviewServiceProvider);
      final por = container.read(proofOfRetrievabilityServiceProvider);

      final issued = await overview.issueChallenge('bafk_x', 'peer1');
      expect(await overview.verifyChallenge(issued), isTrue);
      // Single-consumption through the shared map.
      expect(await overview.verifyChallenge(issued), isFalse);
      expect(
          await overview.verifyChallenge(PorChallenge(
              challengeId: 'never_issued',
              cid: 'bafk_x',
              peerId: 'peer1',
              issuedAt: DateTime.now())),
          isFalse);
      expect(por.pendingChallengeCount, 0);
    });
  });
}
