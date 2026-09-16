// RED TEAM PoC — cross-ledger double-mint: a poster can REFUND their
// escrow after a remote claimant has already been PAID on the
// claimant's own ledger.
//
// The claim lifecycle is ledger-local end to end:
//   * the claimant's claimed_bounties CAS row lives on the CLAIMANT's db,
//   * the tx_bounty_payout_<id> row lives on the CLAIMANT's ledger,
//   * the poster's hold row tx_escrow_hold_<id> lives on the POSTER's
//     ledger.
// MoltbookService.cancelBounty proves "unclaimed" by probing the
// POSTER's own claimed_bounties table and credit_transactions — a
// remote claim never lands there (the shipped code comments even say
// so: "claimed_bounties is CLAIMANT-LOCAL"). Nothing ever notifies the
// poster's ledger that the escrow was paid out. Result: poster cancels,
// releaseEscrow refunds the hold, and the claimant keeps the mint —
// +X ℭ of unbacked supply across the federation.
//
// The escrow attestation is GENUINE here (real Ed25519, honest trusted
// attestor, escrow really was funded) — no collusion needed. The work-
// evidence check is additionally claimant-side only: the claimant's
// MoltbookService has ipfsService == null, so the blockstore check is
// skipped entirely — the funded record pays out with zero replication.
//
// Asserts the SECURE expectation; failure demonstrates the exploit.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart' show AppDatabase;
import 'package:alexandria/services/agent/beacon_models.dart';
import 'package:alexandria/services/agent/escrow_attestation.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';

Future<EscrowAttestation?> _attest(
  SimpleKeyPair attestor, {
  required String bountyId,
  required String cid,
  required int amountMilli,
}) async {
  final exp =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
  final preimage = EscrowAttestation.signingPreimage(
      bountyId: bountyId, cid: cid, amountMilli: amountMilli, expiresAt: exp);
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

void main() {
  test('poster refunds escrow after a remote claim already paid out — '
      'net +X unbacked across the two ledgers', () async {
    final ed = Ed25519();
    final dbPoster = AppDatabase();
    final dbClaimant = AppDatabase();
    addTearDown(dbPoster.close);
    addTearDown(dbClaimant.close);

    // ── POSTER node: 100 ℭ genesis, posts + escrows a 20 ℭ bounty. ──
    final csP = CreditService(db: dbPoster, initialBalance: 100.0);
    await csP.ready;
    final moltP = MoltbookService(creditService: csP, db: dbPoster);
    addTearDown(moltP.dispose);
    await moltP.setKeyPair(await ed.newKeyPair());

    final posted = await moltP.postPreservationBounty(
      cid: 'bafk_rare_doc',
      title: 'Rare doc',
      offeredCredits: 20.0,
      force: true,
    );
    expect(csP.balance, 80.0); // 20 held in escrow

    // ── Honest attestor vouches for the (real) escrow. ──
    final attestor = await ed.newKeyPair();
    final attestorHex =
        bytesToHex((await attestor.extractPublicKey()).bytes);
    final att = await _attest(attestor,
        bountyId: posted.id, cid: posted.cid, amountMilli: 20000);
    expect(att, isNotNull);

    // ── CLAIMANT node: ingests the announcement as FUNDED, claims. ──
    final csC = CreditService(db: dbClaimant, initialBalance: 50.0);
    await csC.ready;
    // No IpfsService injected — exactly what a forked claimant does to
    // skip the "you must already store the bytes" check: it is purely
    // claimant-side and therefore unenforceable against a modified
    // client.
    final moltC = MoltbookService(
        creditService: csC,
        db: dbClaimant,
        trustedAttestorPubkeys: {attestorHex});
    addTearDown(moltC.dispose);
    await moltC.setKeyPair(await ed.newKeyPair());

    moltC.ingestBountyAnnouncement(
      PreservationBounty(
        id: posted.id,
        cid: posted.cid,
        title: posted.title,
        offeredCredits: posted.offeredCredits,
        originAgentId: moltP.agentId,
        createdAt: posted.createdAt,
        funded: true,
      ),
      escrowAttestation: att,
    );

    expect(await moltC.claimBounty(posted.id), isTrue);
    await csC.settled;
    expect(csC.balance, 70.0,
        reason: 'claimant minted the 20 ℭ payout on its own ledger');
    expect(
        await dbClaimant.hasCreditTransaction(
            'tx_bounty_payout_${posted.id}'),
        isTrue);

    // ── POSTER cancels: the claim is INVISIBLE on the poster's db. ──
    final cancelled = await moltP.cancelBounty(posted.id);
    await csP.settled;

    expect(cancelled, isFalse,
        reason: 'SECURE EXPECTATION: the escrow was paid out on the '
            'claimant\u2019s ledger — the poster must not get the hold '
            'back on top of the payout');
    expect(csP.balance, 80.0,
        reason: 'a refund here restores the poster to 100 while the '
            'claimant keeps +20 — 20 ℭ minted from nothing');
  });
}
