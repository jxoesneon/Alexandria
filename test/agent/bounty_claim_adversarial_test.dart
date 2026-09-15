// Adversarial regression tests for the bounty-claim dedup + trust-root
// hoist + client_info landing (Review REV3, E-REV4-B). Covers: mutated
// defensive copies, restart replay, evidence-failure release races,
// thrown-CAS mark leaks, unhydrated payout refusal, trust-root freeze,
// and narrowed client_info broadcast.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart' show AppDatabase;
import 'package:alexandria/services/agent/beacon_models.dart';
import 'package:alexandria/services/agent/escrow_attestation.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/ipfs_service.dart';

/// IpfsService whose blockstore read parks until [gate] completes, then
/// yields an EMPTY payload (evidence failure). Lets a test freeze a
/// claim between the durable CAS insert and the release/delete.
class _GatedIpfsService extends IpfsService {
  _GatedIpfsService(super.ref);
  final Completer<void> gate = Completer<void>();

  @override
  Stream<Uint8List> getFile(String cid) async* {
    await gate.future;
    yield Uint8List(0); // replicated-nothing → evidence failure
  }
}

final _gatedIpfsProvider =
    Provider<IpfsService>((ref) => _GatedIpfsService(ref));

/// AppDatabase whose insertClaimedBounty throws once — models a
/// transient sqlite error on the CAS path.
class _FlakyInsertDb extends AppDatabase {
  bool failNext = true;

  @override
  Future<bool> insertClaimedBounty(String bountyId, String cid,
      {int? claimedAt}) async {
    if (failNext) {
      failNext = false;
      throw StateError('simulated sqlite error');
    }
    return super.insertClaimedBounty(bountyId, cid, claimedAt: claimedAt);
  }
}

/// AppDatabase whose deleteClaimedBounty throws — models a transient
/// sqlite error on the claim-release path (E-REV4-Br: an unguarded throw
/// propagated to callers AND leaked the in-flight mark).
class _ThrowingDeleteDb extends AppDatabase {
  @override
  Future<void> deleteClaimedBounty(String bountyId) async {
    throw StateError('simulated sqlite delete error');
  }

  @override
  Future<int> deleteClaimedBountyIfClaimedAt(
      String bountyId, int claimedAt) async {
    throw StateError('simulated sqlite delete error');
  }
}

/// AppDatabase whose hydration parks at the first query until
/// [hydrateGate] completes — models a slow ledger load so a claim can
/// be driven deterministically inside the unhydrated window.
class _GatedHydrateDb extends AppDatabase {
  final Completer<void> hydrateGate = Completer<void>();

  @override
  Future<Map<String, double>> getDailyMinted(String dayKey) async {
    await hydrateGate.future;
    return super.getDailyMinted(dayKey);
  }
}

/// AppDatabase whose deleteClaimedBounty parks until [deleteGate]
/// completes — models real IO latency between claimBounty's in-memory
/// mark release and the durable row delete landing.
class _SlowDeleteDb extends AppDatabase {
  final Completer<void> deleteGate = Completer<void>();
  final List<String> deleteCalls = [];

  @override
  Future<void> deleteClaimedBounty(String bountyId) async {
    deleteCalls.add(bountyId);
    await deleteGate.future;
    return super.deleteClaimedBounty(bountyId);
  }

  @override
  Future<int> deleteClaimedBountyIfClaimedAt(
      String bountyId, int claimedAt) async {
    deleteCalls.add(bountyId);
    await deleteGate.future;
    return super.deleteClaimedBountyIfClaimedAt(bountyId, claimedAt);
  }
}

Future<SimpleKeyPair> _newAttestor() => Ed25519().newKeyPair();

Future<String> _pubHex(SimpleKeyPair kp) async =>
    bytesToHex((await kp.extractPublicKey()).bytes);

Future<EscrowAttestation?> _attestEscrow(
  SimpleKeyPair attestor, {
  required String bountyId,
  required String cid,
  required int amountMilli,
  int? expiresAt,
}) async {
  final exp = expiresAt ??
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
  final preimage = EscrowAttestation.signingPreimage(
    bountyId: bountyId,
    cid: cid,
    amountMilli: amountMilli,
    expiresAt: exp,
  );
  final sig = await Ed25519().sign(preimage, keyPair: attestor);
  final pub = await attestor.extractPublicKey();
  return EscrowAttestation.verify(
    attestorPubkey: bytesToHex(pub.bytes),
    bountyId: bountyId,
    cid: cid,
    amountMilli: amountMilli,
    expiresAt: exp,
    signature: base64Encode(sig.bytes),
    verifyFn: EscrowAttestation.verifyEd25519,
  );
}

Future<EscrowAttestation?> _attestBounty(
        SimpleKeyPair attestor, PreservationBounty bounty) =>
    _attestEscrow(
      attestor,
      bountyId: bounty.id,
      cid: bounty.cid,
      amountMilli: (bounty.offeredCredits * 1000).round(),
    );

Future<(EscrowAttestation?, String)> _freshTrustedAttestation(
  PreservationBounty bounty,
) async {
  final attestor = await _newAttestor();
  return (await _attestBounty(attestor, bounty), await _pubHex(attestor));
}

PreservationBounty _foreignBounty({
  required String id,
  required String cid,
  double offeredCredits = 25.0,
  bool funded = true,
}) {
  return PreservationBounty(
    id: id,
    cid: cid,
    title: 'Foreign bounty $id',
    offeredCredits: offeredCredits,
    originAgentId: 'bcn_remote_poster',
    createdAt: DateTime.now(),
    funded: funded,
  );
}

void main() {
  group('bounty-claim dedup + trust-root + client_info (REV3 adversarial)',
      () {
    // ── CLASS 1: mutated-copy double-claim ──────────────────────────
    test('C1: mutating activeBounties/postPreservationBounty copies '
        'cannot reopen a claimed bounty (durable db)', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs = CreditService(initialBalance: 100.0);
      final bounty = _foreignBounty(
          id: 'bounty_c1', cid: 'bafk_c1', offeredCredits: 25.0);
      final (att, hex) = await _freshTrustedAttestation(bounty);
      final svc = MoltbookService(
          creditService: cs, db: db, trustedAttestorPubkeys: {hex});
      svc.ingestBountyAnnouncement(bounty, escrowAttestation: att);

      final copy =
          svc.activeBounties.firstWhere((b) => b.id == bounty.id);
      expect(await svc.claimBounty(bounty.id), isTrue);
      expect(cs.balance, 125.0);
      copy.isClaimed = false; // mutate retained copy
      expect(await svc.claimBounty(bounty.id), isFalse);
      expect(await svc.claimBounty(bounty.id), isFalse);
      expect(cs.balance, 125.0);
      // ALSO: postPreservationBounty returns a copy — mutation cannot
      // reach the stored record or the locally-posted guard.
      final cs2 = CreditService(initialBalance: 100.0);
      final poster = MoltbookService(creditService: cs2, db: db);
      await poster.setKeyPair(await Ed25519().newKeyPair());
      final posted = await poster.postPreservationBounty(
          cid: 'bafk_own', title: 'own', offeredCredits: 10.0,
          force: true);
      posted.isClaimed = false;
      posted.funded; // funded is final on the copy anyway
      expect(await poster.claimBounty(posted.id), isFalse);
    });

    // ── CLASS 2: restart replay — independent CreditService ─────────
    test('C2a: restart replay refused by durable CAS even with a FRESH '
        'CreditService (belt dedup not shared)', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final bounty = _foreignBounty(
          id: 'bounty_restart', cid: 'bafk_restart', offeredCredits: 25.0);
      final (att, hex) = await _freshTrustedAttestation(bounty);

      final cs1 = CreditService(db: db, initialBalance: 100.0);
      await cs1.settled;
      final svcA = MoltbookService(
          creditService: cs1, db: db, trustedAttestorPubkeys: {hex});
      svcA.ingestBountyAnnouncement(bounty, escrowAttestation: att);
      expect(await svcA.claimBounty(bounty.id), isTrue);
      await cs1.settled; // flush payout row
      expect(await db.isBountyClaimed(bounty.id), isTrue);

      // Fresh service AND fresh CreditService on the same database.
      final cs2 = CreditService(db: db, initialBalance: 100.0);
      await cs2.ready;
      final svcB = MoltbookService(
          creditService: cs2, db: db, trustedAttestorPubkeys: {hex});
      svcB.ingestBountyAnnouncement(bounty, escrowAttestation: att);
      expect(await svcB.claimBounty(bounty.id), isFalse);
      // Rebuilt _paidBountyIds ALSO refuses a direct re-pay.
      expect(
        cs2.awardBountyEscrow(
            amount: 25.0, bountyId: bounty.id, cid: bounty.cid),
        0.0,
      );
      // Exactly one payout row exists in the durable ledger.
      final rows = await db.getCreditTransactions(limit: 1000);
      expect(
        rows.where(
            (r) => r['id'] == 'tx_bounty_payout_${bounty.id}').length,
        1,
      );
    });

    test('C2b: in-memory fallback (db==null) — two services sharing one '
        'CreditService: second claim is refused by the payout dedup '
        'belt and returns FALSE', () async {
      final cs = CreditService(initialBalance: 100.0);
      final bounty = _foreignBounty(
          id: 'bounty_nodb', cid: 'bafk_nodb', offeredCredits: 25.0);
      final (att, hex) = await _freshTrustedAttestation(bounty);

      final svcA = MoltbookService(
          creditService: cs, trustedAttestorPubkeys: {hex});
      final svcB = MoltbookService(
          creditService: cs, trustedAttestorPubkeys: {hex});
      svcA.ingestBountyAnnouncement(bounty, escrowAttestation: att);
      svcB.ingestBountyAnnouncement(bounty, escrowAttestation: att);

      expect(await svcA.claimBounty(bounty.id), isTrue);
      expect(cs.balance, 125.0);
      // No shared durable state: svcB's in-memory guards don't know —
      // but the shared CreditService's _paidBountyIds belt refuses the
      // payout (0.0), and claimBounty now treats a refused payout as a
      // failed claim: returns false, releases the marks.
      final second = await svcB.claimBounty(bounty.id);
      expect(second, isFalse,
          reason: 'a refused payout must not report a won claim');
      expect(cs.balance, 125.0); // exactly one payout either way
    });

    // ── CLASS 3: evidence-failure release races ─────────────────────
    test('C3a: TWO instances, one db — CAS-loss leaves the loser\'s '
        'stored record unclaimed so it can win after the winner '
        'releases', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final gated = container.read(_gatedIpfsProvider) as _GatedIpfsService;
      final cs = CreditService(initialBalance: 100.0);

      final bounty = _foreignBounty(
          id: 'bounty_release_race',
          cid: 'bafk_release_race',
          offeredCredits: 25.0);
      final (att, hex) = await _freshTrustedAttestation(bounty);

      final svcA = MoltbookService(
          creditService: cs,
          ipfsService: gated,
          db: db,
          trustedAttestorPubkeys: {hex});
      final svcB = MoltbookService(
          creditService: cs, db: db, trustedAttestorPubkeys: {hex});
      svcA.ingestBountyAnnouncement(bounty, escrowAttestation: att);
      svcB.ingestBountyAnnouncement(bounty, escrowAttestation: att);

      // A claims: wins the CAS row, then parks inside the gated
      // evidence stream.
      final claimA = svcA.claimBounty(bounty.id);
      while (!await db.isBountyClaimed(bounty.id)) {
        await Future<void>.delayed(Duration.zero);
      }
      // B loses the CAS → returns false WITHOUT poisoning its stored
      // record (the row proves a claim in flight, not one landed).
      expect(await svcB.claimBounty(bounty.id), isFalse);
      expect(svcB.activeBounties.any((b) => b.id == bounty.id), isTrue);

      // A's evidence fails → the durable row is RELEASED.
      gated.gate.complete();
      expect(await claimA, isFalse);
      expect(await db.isBountyClaimed(bounty.id), isFalse);

      // The bounty is genuinely claimable again — and B's un-poisoned
      // record can now win it (svcB has no ipfsService → the evidence
      // check is skipped → CAS wins → pays out).
      expect(await svcB.claimBounty(bounty.id), isTrue);
      expect(cs.balance, 125.0); // exactly one payout, by B

      // A THIRD fresh instance on the same db is refused — the durable
      // row now stands won.
      final svcC = MoltbookService(
          creditService: cs, db: db, trustedAttestorPubkeys: {hex});
      svcC.ingestBountyAnnouncement(bounty, escrowAttestation: att);
      expect(await svcC.claimBounty(bounty.id), isFalse);
      expect(cs.balance, 125.0);
    });

    test('C3b: SINGLE instance — a claim interleaved during the durable '
        'delete neither wins nor poisons the stored record (no second '
        'service needed)', () async {
      final db = _SlowDeleteDb();
      addTearDown(db.close);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final gated = container.read(_gatedIpfsProvider) as _GatedIpfsService;
      final cs = CreditService(initialBalance: 100.0);

      final bounty = _foreignBounty(
          id: 'bounty_single_race',
          cid: 'bafk_single_race',
          offeredCredits: 25.0);
      final (att, hex) = await _freshTrustedAttestation(bounty);
      final svc = MoltbookService(
          creditService: cs,
          ipfsService: gated,
          db: db,
          trustedAttestorPubkeys: {hex});
      svc.ingestBountyAnnouncement(bounty, escrowAttestation: att);

      // Claim 1: CAS-wins, parks in the gated evidence stream.
      final claim1 = svc.claimBounty(bounty.id);
      while (!await db.isBountyClaimed(bounty.id)) {
        await Future<void>.delayed(Duration.zero);
      }
      // Evidence fails → claim1 calls the (gated) delete FIRST, then
      // releases the in-memory mark only after the row is gone.
      gated.gate.complete();
      // Wait until the delete is in-flight (gate parked).
      while (db.deleteCalls.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      // Claim 2 slips into the window: the durable delete is parked but
      // the in-flight mark is still held (release order is delete-THEN-
      // mark), so claim2 bails cleanly — and even if it reached the CAS
      // it would lose WITHOUT poisoning the stored record.
      expect(await svc.claimBounty(bounty.id), isFalse);
      // Let the delete land.
      db.deleteGate.complete();
      expect(await claim1, isFalse);
      expect(await db.isBountyClaimed(bounty.id), isFalse);

      // NOT poisoned: the stored record is still listed, and a retry
      // reaches the evidence phase cleanly (gated ipfs yields empty →
      // evidence failure → released again), proving the claim path is
      // retryable rather than permanently dead.
      expect(svc.activeBounties.any((b) => b.id == bounty.id), isTrue);
      expect(await svc.claimBounty(bounty.id), isFalse);
      expect(await db.isBountyClaimed(bounty.id), isFalse);
      expect(svc.activeBounties.any((b) => b.id == bounty.id), isTrue);
      expect(cs.balance, 100.0);
    });

    test('C3c: a THROWN insertClaimedBounty fails closed and releases '
        'the in-flight mark — the bounty stays claimable', () async {
      final db = _FlakyInsertDb();
      addTearDown(db.close);
      final cs = CreditService(initialBalance: 100.0);
      final bounty = _foreignBounty(
          id: 'bounty_throw', cid: 'bafk_throw', offeredCredits: 25.0);
      final (att, hex) = await _freshTrustedAttestation(bounty);
      final svc = MoltbookService(
          creditService: cs, db: db, trustedAttestorPubkeys: {hex});
      svc.ingestBountyAnnouncement(bounty, escrowAttestation: att);

      // The CAS insert throws → claimBounty fails closed (returns
      // false, no propagation into callers) AND releases the in-flight
      // mark so the bounty is retryable.
      expect(await svc.claimBounty(bounty.id), isFalse);
      // Bounty still listed as active and NOT marked…
      expect(svc.activeBounties.any((b) => b.id == bounty.id), isTrue);
      // …and the transient error healed — the retry wins the real CAS
      // and pays out (failNext already consumed).
      expect(await svc.claimBounty(bounty.id), isTrue);
      expect(await db.isBountyClaimed(bounty.id), isTrue);
      expect(cs.balance, 125.0);
    });

    test('C3d: a THROWING deleteClaimedBounty fails closed without '
        'propagating and without leaking the in-flight mark '
        '(E-REV4-Br)', () async {
      final db = _ThrowingDeleteDb();
      addTearDown(db.close);
      final cs = CreditService(initialBalance: 100.0);
      final bounty = _foreignBounty(
          id: 'bounty_del_throw', cid: 'bafk_del_throw',
          offeredCredits: 25.0);
      final (att, hex) = await _freshTrustedAttestation(bounty);
      // No ipfsService → evidence check is skipped → claim reaches the
      // payout path. Refuse the payout by pre-consuming the dedup id —
      // that drives claimBounty into the delete-on-refusal path whose
      // delete throws.
      cs.awardBountyEscrow(
          amount: 1.0, bountyId: bounty.id, cid: 'other');
      final svc = MoltbookService(
          creditService: cs, db: db, trustedAttestorPubkeys: {hex});
      svc.ingestBountyAnnouncement(bounty, escrowAttestation: att);

      // The throwing delete must be swallowed inside claimBounty —
      // returns false, never propagates, and releases the in-flight
      // mark so the record stays listed and retryable.
      expect(await svc.claimBounty(bounty.id), isFalse);
      expect(svc.activeBounties.any((b) => b.id == bounty.id), isTrue);
      // Retry reaches the same path cleanly (row CAS still wins — the
      // row was inserted but its delete threw; either way no throw,
      // no deadlock): returns false via CAS-loss or payout-refusal.
      expect(await svc.claimBounty(bounty.id), isFalse);
      expect(cs.balance, 101.0); // only the pre-consumed 1.0 paid
    });

    // ── CLASS 4: bountyId spelling variants ─────────────────────────
    test('C4: bounty ids are NOT canonicalized — case/space variants are '
        'distinct bounties AND claim args must match exactly', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs = CreditService(initialBalance: 100.0);
      final attestor = await _newAttestor();
      final hex = await _pubHex(attestor);
      final svc = MoltbookService(
          creditService: cs, db: db, trustedAttestorPubkeys: {hex});

      // Two SPELLING VARIANTS of "the same" id — the attestor must
      // attest each separately (bindsBounty is raw ==), so each variant
      // is a distinct escrowed bounty, not a dedup bypass.
      for (final id in ['bounty_variant', 'BOUNTY_VARIANT']) {
        final b = _foreignBounty(id: id, cid: 'bafk_$id');
        svc.ingestBountyAnnouncement(b,
            escrowAttestation: await _attestBounty(attestor, b));
      }
      expect(await svc.claimBounty('bounty_variant'), isTrue);
      // A whitespace-padded claim arg does NOT match the stored id.
      expect(await svc.claimBounty(' bounty_variant '), isFalse);
      // The uppercase variant is a separate funded bounty — pays too.
      expect(await svc.claimBounty('BOUNTY_VARIANT'), isTrue);
      expect(cs.balance, 150.0); // two distinct escrows paid once each
      // And each variant's durable row is independent.
      expect(await db.isBountyClaimed('bounty_variant'), isTrue);
      expect(await db.isBountyClaimed('BOUNTY_VARIANT'), isTrue);
      expect(await db.isBountyClaimed(' bounty_variant '), isFalse);
    });

    // ── CLASS 5: trust-root hoist ───────────────────────────────────
    test('C5a: mutating the caller\'s trust set after construction does '
        'NOT widen the frozen trust root', () async {
      final cs = CreditService(initialBalance: 100.0);
      final attestor = await _newAttestor();
      final trust = <String>{};
      final svc = MoltbookService(
          creditService: cs, trustedAttestorPubkeys: trust);
      // Attacker mutates the set it handed in AFTER construction.
      trust.add(await _pubHex(attestor));

      final bounty = _foreignBounty(
          id: 'bounty_trust_mut', cid: 'bafk_trust_mut');
      final att = await _attestBounty(attestor, bounty);
      expect(att, isNotNull);
      svc.ingestBountyAnnouncement(bounty, escrowAttestation: att);
      final stored = svc.activeBounties
          .firstWhere((b) => b.id == bounty.id);
      expect(stored.funded, isFalse); // still fail-closed
      expect(await svc.claimBounty(bounty.id), isFalse);
    });

    test('C5b: no public path inserts into _bounties except '
        'ingest/postPreservationBounty/seed — wire is_claimed and '
        'funded both stripped without a trusted attestation', () async {
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs); // empty trust root
      // Worst-case wire announcement: funded+claimed, no attestation.
      final wire = PreservationBounty.fromJson(_foreignBounty(
        id: 'bounty_wire_flags',
        cid: 'bafk_wire_flags',
      ).toJson()
        ..['funded'] = true
        ..['is_claimed'] = true);
      svc.ingestBountyAnnouncement(wire);
      final stored = svc.activeBounties
          .firstWhere((b) => b.id == 'bounty_wire_flags');
      expect(stored.funded, isFalse);
      expect(stored.isClaimed, isFalse);
      expect(await svc.claimBounty('bounty_wire_flags'), isFalse);
      expect(cs.balance, 100.0);
    });

    // ── CLASS 6: client_info ────────────────────────────────────────
    test('C6: caller-supplied payload client_info is overridden by the '
        'narrowed claimedBroadcastInfo', () async {
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      final post = await svc.createPost(
        submolt: 'open-science',
        title: 'smuggle attempt',
        content: 'x',
        payload: {
          'client_info': {
            'claimed_commit_sha': 'deadbeef' * 5,
            'claimed_client_version': '999.0.0',
          }
        },
      );
      final info = post.beaconEnvelope!.clientInfo!;
      expect(
        info.keys.toSet(),
        equals({
          'claimed_client_version',
          'claimed_build_channel',
          'claimed_protocol_version',
        }),
      );
      expect(info.containsKey('claimed_commit_sha'), isFalse);
      expect(await post.beaconEnvelope!.verify(), isTrue);
      // Tamper check: mutating client_info post-hoc breaks the sig.
      final tampered = BeaconEnvelope(
        kind: post.beaconEnvelope!.kind,
        agentId: post.beaconEnvelope!.agentId,
        ts: post.beaconEnvelope!.ts,
        nonce: post.beaconEnvelope!.nonce,
        pubkey: post.beaconEnvelope!.pubkey,
        sig: post.beaconEnvelope!.sig,
        payload: {
          ...post.beaconEnvelope!.payload,
          'client_info': {'claimed_client_version': '0.0.0'}
        },
      );
      expect(await tampered.verify(), isFalse);
    });

    // ── CLASS 7: copyWith fidelity ──────────────────────────────────
    test('C7: copyWith preserves every field including funded/doi/'
        'targetShards/origin', () {
      final b = PreservationBounty(
        id: 'bounty_copy',
        cid: 'bafk_copy',
        doi: '10.1/x',
        title: 't',
        targetShards: 9,
        offeredCredits: 42.5,
        urgency: 'critical',
        originAgentId: 'bcn_orig',
        createdAt: DateTime.utc(2026, 1, 1),
        isClaimed: false,
        funded: true,
      );
      final c = b.copyWith();
      expect(c.id, b.id);
      expect(c.cid, b.cid);
      expect(c.doi, b.doi);
      expect(c.title, b.title);
      expect(c.targetShards, b.targetShards);
      expect(c.offeredCredits, b.offeredCredits);
      expect(c.urgency, b.urgency);
      expect(c.originAgentId, b.originAgentId);
      expect(c.createdAt, b.createdAt);
      expect(c.isClaimed, b.isClaimed);
      expect(c.funded, b.funded);
      expect(identical(c, b), isFalse);
      expect(b.copyWith(isClaimed: true).isClaimed, isTrue);
      expect(b.isClaimed, isFalse); // original untouched
    });

    // ── awardBountyEscrow durability + hostile ids ──────────────────
    test('C8a: deterministic payout id is restart-durable; hostile '
        'bountyId chars cannot collide rows or dedup', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs1 = CreditService(db: db, initialBalance: 100.0);
      await cs1.ready;
      expect(
          cs1.awardBountyEscrow(
              amount: 10.0, bountyId: 'a', cid: 'c1'),
          10.0);
      expect(
          cs1.awardBountyEscrow(
              amount: 20.0, bountyId: 'a/b', cid: 'c2'),
          20.0);
      expect(
          cs1.awardBountyEscrow(
              amount: 30.0, bountyId: 'a/b/c', cid: 'c3'),
          30.0);
      // Whole-suffix ids: no prefix collisions.
      expect(
          cs1.awardBountyEscrow(
              amount: 99.0, bountyId: 'a', cid: 'c1'),
          0.0);
      await cs1.settled;

      final cs2 = CreditService(db: db, initialBalance: 100.0);
      await cs2.ready;
      // Hydration rebuilt _paidBountyIds for ALL variants, verbatim.
      for (final id in ['a', 'a/b', 'a/b/c']) {
        expect(cs2.awardBountyEscrow(amount: 1.0, bountyId: id, cid: 'x'),
            0.0);
      }
    });

    test('C8b: awardBountyEscrow called before hydration completes is '
        'refused WITHOUT consuming the bountyId — the legit payout '
        'still lands after ready', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      // NOT awaited — hydration still in flight.
      final paid =
          cs.awardBountyEscrow(amount: 25.0, bountyId: 'bounty_pre', cid: 'c');
      expect(paid, 0.0);
      await cs.ready;
      // The refusal did NOT consume the id — the real payout succeeds.
      expect(
          cs.awardBountyEscrow(
              amount: 25.0, bountyId: 'bounty_pre', cid: 'c'),
          25.0);
      await cs.settled;
      final rows = await db.getCreditTransactions(limit: 1000);
      expect(
          rows.any((r) => r['id'] == 'tx_bounty_payout_bounty_pre'),
          isTrue);
      // …and the now-PAID id is refused on replay.
      expect(
          cs.awardBountyEscrow(
              amount: 25.0, bountyId: 'bounty_pre', cid: 'c'),
          0.0);
    });

    test('C8c: mixed-mode claim inside the hydration window returns '
        'FALSE and stays retryable — a refused payout releases the '
        'claim instead of deadlocking the bounty', () async {
      final db = _GatedHydrateDb();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      final bounty = _foreignBounty(
          id: 'bounty_unhydrated', cid: 'bafk_unhydrated');
      final (att, hex) = await _freshTrustedAttestation(bounty);
      // db:null on the moltbook side → no CAS await → the whole claim
      // runs inside the (gated, deterministic) hydration window; the
      // payout is refused and the claim must NOT be marked won.
      final svc = MoltbookService(
          creditService: cs, trustedAttestorPubkeys: {hex});
      svc.ingestBountyAnnouncement(bounty, escrowAttestation: att);
      expect(await svc.claimBounty(bounty.id), isFalse);
      // Balance is still 0.0 — even the genesis grant lives inside the
      // parked hydration.
      expect(cs.balance, 0.0);
      db.hydrateGate.complete();
      await cs.ready;
      // Retry is NOT blocked: the refused payout released the claim, so
      // the hydrated credit service now pays the legit escrow.
      expect(await svc.claimBounty(bounty.id), isTrue);
      expect(cs.balance, 125.0);
    });
  });
}
