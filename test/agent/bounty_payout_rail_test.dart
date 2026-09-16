// Cross-ledger payout rail tests (ALX-006/ALX-012 REV4): the poster-side
// escrow-release path that evaluates VERIFIED remote claim events as
// settlement evidence. A verified claim must durably consume the
// poster's escrow (never refund it — the claimant's payout already
// minted on its own ledger, so refunding the backing hold is the
// round-1 cross-ledger double-mint); unproven escrows stay locked
// unless an operator explicitly reconciles.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart' show AppDatabase;
import 'package:alexandria/services/agent/beacon_models.dart';
import 'package:alexandria/services/agent/bounty_claim_event.dart';
import 'package:alexandria/services/agent/escrow_attestation.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';

Future<SimpleKeyPair> _newKey() => Ed25519().newKeyPair();

Future<String> _pubHex(SimpleKeyPair kp) async =>
    bytesToHex((await kp.extractPublicKey()).bytes);

/// Foreign-attestor signature over the canonical escrow attestation —
/// what makes a remote announcement claimable (the announcer's own
/// `funded` flag is forgeable and stripped at ingest).
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

/// Issues a signed claim event for [bountyId]/[cid] and wraps it in a
/// Beacon envelope signed by the same claimant key — the transport
/// binding `envelope.agentId == claimantAgentId` requires.
Future<BeaconEnvelope> _claimEnvelope(
  SimpleKeyPair claimant, {
  required String bountyId,
  required String cid,
}) async {
  final event = await BountyClaimEvent.issue(
      keyPair: claimant, bountyId: bountyId, cid: cid);
  return event.toEnvelope(claimant);
}

void main() {
  group('verified remote claim → poster-side settlement', () {
    test(
        'a verified claim event settles the local escrow durably: '
        'tombstone row, locked hold, dead id', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final svc = MoltbookService(creditService: cs, db: db);
      addTearDown(svc.dispose);
      await svc.setKeyPair(await _newKey());

      final posted = await svc.postPreservationBounty(
          cid: 'bafk_settle',
          title: 'settle me',
          offeredCredits: 20.0,
          force: true);
      expect(cs.balance, 80.0);

      final claimant = await _newKey();
      final env =
          await _claimEnvelope(claimant, bountyId: posted.id, cid: posted.cid);
      expect(await svc.ingestBountyClaimEnvelope(env), isTrue);

      // Settlement evidence recorded + record marked claimed.
      expect(svc.isRemotelyClaimed(posted.id), isTrue);
      expect(svc.remoteClaimFor(posted.id), isNotNull);
      expect(svc.activeBounties.any((b) => b.id == posted.id), isFalse);

      // The durable spent-tombstone landed: the escrow is provably
      // consumed — releaseEscrow refuses it forever (never a refund).
      expect(await db.hasCreditTransaction('tx_escrow_release_${posted.id}'),
          isTrue);
      expect(await cs.releaseEscrow(referenceId: posted.id), 0.0);
      expect(cs.balance, 80.0); // hold consumed, NOT refunded

      // The cross-ledger guard still stands: cancel refuses.
      expect(await svc.cancelBounty(posted.id), isFalse);
      expect(cs.balance, 80.0);
    });

    test('the settlement tombstone survives a service+ledger restart',
        () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final svc = MoltbookService(creditService: cs, db: db);
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_restart', title: 't', offeredCredits: 20.0, force: true);
      await svc.ingestBountyClaimEnvelope(await _claimEnvelope(await _newKey(),
          bountyId: posted.id, cid: posted.cid));
      expect(await db.hasCreditTransaction('tx_escrow_release_${posted.id}'),
          isTrue);
      svc.dispose();

      // Fresh CreditService + MoltbookService on the same durable db:
      // hydration rebuilds the released-escrow set from
      // tx_escrow_release_* rows, so the id is terminally released.
      final cs2 = CreditService(db: db, initialBalance: 0.0);
      await cs2.ready;
      expect(await cs2.releaseEscrow(referenceId: posted.id), 0.0);
      final svc2 = MoltbookService(creditService: cs2, db: db);
      addTearDown(svc2.dispose);
      // The rail sees the terminal release and refuses to re-act on it.
      expect(await svc2.releaseBountyEscrow(posted.id),
          BountyEscrowRelease.refused);
      expect(await svc2.cancelBounty(posted.id), isFalse);
    });

    test(
        'replayed/duplicate claim events settle idempotently — one '
        'tombstone, no extra effect', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final svc = MoltbookService(creditService: cs, db: db);
      addTearDown(svc.dispose);
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_dup', title: 't', offeredCredits: 20.0, force: true);
      final env = await _claimEnvelope(await _newKey(),
          bountyId: posted.id, cid: posted.cid);
      expect(await svc.ingestBountyClaimEnvelope(env), isTrue);
      expect(await svc.ingestBountyClaimEnvelope(env), isTrue);
      expect(await svc.ingestBountyClaimEnvelope(env), isTrue);
      expect(cs.balance, 80.0);
      // releaseBountyEscrow on the already-settled id still resolves to
      // the settled outcome via in-memory evidence (idempotent).
      expect(await svc.releaseBountyEscrow(posted.id),
          BountyEscrowRelease.settledToVerifiedClaim);
      expect(cs.balance, 80.0);
    });
  });

  group('refused claim evidence never settles', () {
    test('a claim for the wrong cid drops before settlement', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final svc = MoltbookService(creditService: cs, db: db);
      addTearDown(svc.dispose);
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_real', title: 't', offeredCredits: 20.0, force: true);

      final env = await _claimEnvelope(await _newKey(),
          bountyId: posted.id, cid: 'bafk_DIFFERENT');
      expect(await svc.ingestBountyClaimEnvelope(env), isFalse);
      expect(await db.hasCreditTransaction('tx_escrow_release_${posted.id}'),
          isFalse);
      expect(svc.isRemotelyClaimed(posted.id), isFalse);
    });

    test(
        'a claim whose envelope signer is NOT the claimant drops '
        '(transport binding enforced)', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final svc = MoltbookService(creditService: cs, db: db);
      addTearDown(svc.dispose);
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_binding', title: 't', offeredCredits: 20.0, force: true);

      // Claimant A signs the event; impostor B wraps it — the
      // envelope-signer/claimant binding must refuse it.
      final claimant = await _newKey();
      final impostor = await _newKey();
      final event = await BountyClaimEvent.issue(
          keyPair: claimant, bountyId: posted.id, cid: posted.cid);
      final badEnv = await event.toEnvelope(impostor);
      expect(await svc.ingestBountyClaimEnvelope(badEnv), isFalse);
      expect(await db.hasCreditTransaction('tx_escrow_release_${posted.id}'),
          isFalse);
      expect(cs.balance, 80.0);
    });

    test(
        'a claim for a foreign bounty id is evidence but settles '
        'nothing local', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final svc = MoltbookService(creditService: cs, db: db);
      addTearDown(svc.dispose);
      await svc.setKeyPair(await _newKey());
      await svc.postPreservationBounty(
          cid: 'bafk_ours', title: 't', offeredCredits: 20.0, force: true);

      final env = await _claimEnvelope(await _newKey(),
          bountyId: 'bounty_foreign_999', cid: 'bafk_theirs');
      expect(await svc.ingestBountyClaimEnvelope(env), isTrue);
      expect(svc.isRemotelyClaimed('bounty_foreign_999'), isTrue);
      // No hold exists for that id on this ledger — nothing released.
      expect(
          await db.hasCreditTransaction('tx_escrow_release_bounty_foreign_999'),
          isFalse);
      expect(await svc.releaseBountyEscrow('bounty_foreign_999'),
          BountyEscrowRelease.refused);
    });
  });

  group('releaseBountyEscrow evidence gate', () {
    test('no verified evidence → refusedUnproven, hold untouched', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final svc = MoltbookService(creditService: cs, db: db);
      addTearDown(svc.dispose);
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_unproven', title: 't', offeredCredits: 25.0, force: true);
      expect(cs.balance, 75.0);

      expect(await svc.releaseBountyEscrow(posted.id),
          BountyEscrowRelease.refusedUnproven);
      expect(cs.balance, 75.0);
      expect(await db.hasCreditTransaction('tx_escrow_release_${posted.id}'),
          isFalse);
    });

    test(
        'explicit operator reconciliation refunds through the public '
        'CreditService API — and only once', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final svc = MoltbookService(creditService: cs, db: db);
      addTearDown(svc.dispose);
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_operator', title: 't', offeredCredits: 25.0, force: true);
      expect(cs.balance, 75.0);

      expect(
          await svc.releaseBountyEscrow(posted.id,
              operatorReconciliation: true),
          BountyEscrowRelease.refunded);
      expect(cs.balance, 100.0); // hold returned to the poster
      // Terminal: a second release attempt is refused outright.
      expect(
          await svc.releaseBountyEscrow(posted.id,
              operatorReconciliation: true),
          BountyEscrowRelease.refused);
      expect(cs.balance, 100.0);
    });

    test(
        'a verified claim beats the operator flag — settlement, '
        'never refund', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final svc = MoltbookService(creditService: cs, db: db);
      addTearDown(svc.dispose);
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_flag', title: 't', offeredCredits: 25.0, force: true);
      await svc.ingestBountyClaimEnvelope(await _claimEnvelope(await _newKey(),
          bountyId: posted.id, cid: posted.cid));

      expect(
          await svc.releaseBountyEscrow(posted.id,
              operatorReconciliation: true),
          BountyEscrowRelease.settledToVerifiedClaim);
      expect(cs.balance, 75.0); // consumed — NOT refunded to the poster
    });

    test(
        'durable claim/payout evidence settles even with no claim '
        'event in memory', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final svc = MoltbookService(creditService: cs, db: db);
      addTearDown(svc.dispose);
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_durable_ev',
          title: 't',
          offeredCredits: 25.0,
          force: true);

      // Settlement evidence that outlives process memory: a durable
      // claim row on this ledger (e.g. written by a previous
      // incarnation's claim path).
      await db.insertClaimedBounty(posted.id, posted.cid);

      expect(await svc.releaseBountyEscrow(posted.id),
          BountyEscrowRelease.settledToVerifiedClaim);
      expect(await db.hasCreditTransaction('tx_escrow_release_${posted.id}'),
          isTrue);
      expect(cs.balance, 75.0);
    });
  });

  group('end-to-end over BountyTransport', () {
    test(
        'claim event published by the claimant settles the poster '
        'escrow automatically — supply conserved', () async {
      final bus = InMemoryBountyTransport();
      final db = AppDatabase();
      addTearDown(db.close);

      // Poster side.
      final csP = CreditService(db: db, initialBalance: 100.0);
      await csP.ready;
      final svcP = MoltbookService(
          creditService: csP, db: db, bountyTransport: bus.attach());
      addTearDown(svcP.dispose);
      await svcP.setKeyPair(await _newKey());
      final posted = await svcP.postPreservationBounty(
          cid: 'bafk_e2e', title: 'e2e', offeredCredits: 30.0, force: true);
      expect(csP.balance, 70.0);

      // Claimant side: holds the poster's record backed by a FOREIGN
      // attestor's escrow attestation — the only admissible funding
      // proof (a self-declared `funded` flag is stripped at ingest).
      final attestor = await _newKey();
      final csC = CreditService(initialBalance: 50.0);
      final svcC = MoltbookService(
          creditService: csC,
          bountyTransport: bus.attach(),
          trustedAttestorPubkeys: {await _pubHex(attestor)});
      addTearDown(svcC.dispose);
      await svcC.setKeyPair(await _newKey());
      final remote = PreservationBounty(
        id: posted.id,
        cid: posted.cid,
        title: posted.title,
        offeredCredits: posted.offeredCredits,
        originAgentId: posted.originAgentId,
        createdAt: posted.createdAt,
        funded: true,
      );
      svcC.ingestBountyAnnouncement(remote,
          escrowAttestation: await _attestBounty(attestor, remote));

      expect(await svcC.claimBounty(posted.id), isTrue);
      expect(csC.balance, 80.0); // claimant minted +30 on its ledger

      // Let the claim event ride the bus into the poster's ingest.
      for (var i = 0; i < 50 && !svcP.isRemotelyClaimed(posted.id); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(svcP.isRemotelyClaimed(posted.id), isTrue);
      expect(await db.hasCreditTransaction('tx_escrow_release_${posted.id}'),
          isTrue);
      expect(await csP.releaseEscrow(referenceId: posted.id), 0.0);
      expect(csP.balance, 70.0); // consumed — never refunded
      expect(await svcP.cancelBounty(posted.id), isFalse);
    });
  });
}
