// Verified bounty claim events + remote transport caller tests:
// BountyClaimEvent signature binding/attribution, the
// ingestBountyClaimEnvelope gate chain, the InMemoryBountyTransport
// end-to-end loop (announce → verified origin → claim → claim event →
// poster-side settlement evidence), and the cancelBounty remote-claim
// guard.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/agent/beacon_models.dart';
import 'package:alexandria/services/agent/bounty_claim_event.dart';
import 'package:alexandria/services/agent/escrow_attestation.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';

Future<SimpleKeyPair> _newKey() => Ed25519().newKeyPair();

Future<String> _pubHex(SimpleKeyPair kp) async =>
    bytesToHex((await kp.extractPublicKey()).bytes);

Future<String> _agentId(SimpleKeyPair kp) async =>
    BeaconEnvelope.deriveAgentId((await kp.extractPublicKey()).bytes);

/// A signed escrow-attestation map suitable for embedding in an
/// announcement payload under `escrow_attestation`.
Future<Map<String, dynamic>> _attestationBlock(
  SimpleKeyPair attestor, {
  required String bountyId,
  required String cid,
  required int amountMilli,
}) async {
  final exp =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
  final sig = await Ed25519().sign(
    EscrowAttestation.signingPreimage(
        bountyId: bountyId, cid: cid, amountMilli: amountMilli, expiresAt: exp),
    keyPair: attestor,
  );
  return {
    'attestor_pubkey': await _pubHex(attestor),
    'bounty_id': bountyId,
    'cid': cid,
    'amount_milli': amountMilli,
    'expires_at': exp,
    'sig': base64Encode(sig.bytes),
  };
}

/// Lets fire-and-forget stream delivery + async ingest settle.
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  group('BountyClaimEvent signature + attribution', () {
    test('issue → verify round-trips; every field binds', () async {
      final kp = await _newKey();
      final event = await BountyClaimEvent.issue(
          keyPair: kp, bountyId: 'bounty_1', cid: 'bafk_1');
      expect(event.claimantAgentId, await _agentId(kp));
      expect(event.claimantPubkey, await _pubHex(kp));

      final verified = await BountyClaimEvent.verify(
        claimantPubkey: event.claimantPubkey,
        claimantAgentId: event.claimantAgentId,
        bountyId: event.bountyId,
        cid: event.cid,
        claimedAt: event.claimedAt,
        claimNonce: event.claimNonce,
        signature: event.signature,
      );
      expect(verified, isNotNull);
      expect(verified!.bountyId, 'bounty_1');
    });

    test('tampered fields fail verification', () async {
      final kp = await _newKey();
      final event = await BountyClaimEvent.issue(
          keyPair: kp, bountyId: 'bounty_1', cid: 'bafk_1');
      // Different bounty id under the same signature → preimage mismatch.
      expect(
        await BountyClaimEvent.verify(
          claimantPubkey: event.claimantPubkey,
          claimantAgentId: event.claimantAgentId,
          bountyId: 'bounty_2',
          cid: event.cid,
          claimedAt: event.claimedAt,
          claimNonce: event.claimNonce,
          signature: event.signature,
        ),
        isNull,
      );
    });

    test('claimantAgentId not derived from the signing key is refused '
        '(no self-asserted identity)', () async {
      final kp = await _newKey();
      final other = await _newKey();
      // Sign the event naming a DIFFERENT agent id than the key derives.
      final preimage = BountyClaimEvent.signingPreimage(
        bountyId: 'bounty_1',
        cid: 'bafk_1',
        claimantAgentId: await _agentId(other), // impostor id
        claimedAt: DateTime.now().millisecondsSinceEpoch,
        claimNonce: 'n1',
      );
      final sig = await Ed25519().sign(preimage, keyPair: kp);
      expect(
        await BountyClaimEvent.verify(
          claimantPubkey: await _pubHex(kp),
          claimantAgentId: await _agentId(other),
          bountyId: 'bounty_1',
          cid: 'bafk_1',
          claimedAt: DateTime.now().millisecondsSinceEpoch,
          claimNonce: 'n1',
          signature: base64Encode(sig.bytes),
        ),
        isNull,
      );
    });

    test('malformed payloads verify to null', () async {
      expect(await BountyClaimEvent.fromPayload({}), isNull);
      expect(
          await BountyClaimEvent.fromPayload({'claim': 'not-a-map'}),
          isNull);
      expect(
        await BountyClaimEvent.fromPayload({
          'claim': {'bounty_id': 'b'} // missing everything else
        }),
        isNull,
      );
    });
  });

  group('ingestBountyClaimEnvelope gate chain', () {
    test('wrong kind / unsigned envelope / mismatched signer are dropped',
        () async {
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      final claimant = await _newKey();
      final event = await BountyClaimEvent.issue(
          keyPair: claimant, bountyId: 'bounty_x', cid: 'bafk_x');

      // Wrong kind.
      final wrongKind = await BeaconEnvelope.create(
          kind: 'moltbook_post',
          keyPair: claimant,
          payload: {'claim': event.toPayloadBlock()});
      expect(await svc.ingestBountyClaimEnvelope(wrongKind), isFalse);
      expect(svc.isRemotelyClaimed('bounty_x'), isFalse);

      // Event signed by claimant but the ENVELOPE signed by a different
      // key — the transport binding refuses it (relayer laundering).
      final relayer = await _newKey();
      final relayerEnv = await event.toEnvelope(relayer);
      expect(await svc.ingestBountyClaimEnvelope(relayerEnv), isFalse);
      expect(svc.isRemotelyClaimed('bounty_x'), isFalse);

      // Forged envelope (garbage signature) is dropped at verify().
      final forged = BeaconEnvelope(
        kind: BountyClaimEvent.envelopeKind,
        agentId: await _agentId(claimant),
        ts: 1,
        nonce: 'n',
        pubkey: await _pubHex(claimant),
        sig: '00' * 64,
        payload: {'claim': event.toPayloadBlock()},
      );
      expect(await svc.ingestBountyClaimEnvelope(forged), isFalse);
    });

    test('a verified claim marks the stored bounty claimed and records '
        'attribution', () async {
      final csA = CreditService(initialBalance: 100.0);
      final svcA = MoltbookService(creditService: csA);
      await svcA.setKeyPair(await _newKey());
      final posted = await svcA.postPreservationBounty(
        cid: 'bafk_r',
        title: 't',
        offeredCredits: 10.0,
        force: true,
      );

      final claimant = await _newKey();
      final event = await BountyClaimEvent.issue(
          keyPair: claimant, bountyId: posted.id, cid: posted.cid);
      final env = await event.toEnvelope(claimant);
      expect(await svcA.ingestBountyClaimEnvelope(env), isTrue);

      // Settlement evidence: the remote claim is attributed to the
      // claimant's signing key.
      expect(svcA.isRemotelyClaimed(posted.id), isTrue);
      final recorded = svcA.remoteClaimFor(posted.id);
      expect(recorded, isNotNull);
      expect(recorded!.claimantAgentId, await _agentId(claimant));
      // The stored record is now claimed — the listing stops offering
      // it and cancelBounty refuses to free the spoken-for escrow.
      expect(svcA.activeBounties.any((b) => b.id == posted.id), isFalse);
      expect(await svcA.cancelBounty(posted.id), isFalse);
      // Escrow stays locked on the ledger (no auto-refund).
      expect(csA.balance, lessThan(100.0));
    });

    test('a claim event over a different cid for the same id is '
        'dropped', () async {
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
        cid: 'bafk_real',
        title: 't',
        offeredCredits: 10.0,
        force: true,
      );
      final claimant = await _newKey();
      final event = await BountyClaimEvent.issue(
          keyPair: claimant, bountyId: posted.id, cid: 'bafk_other');
      expect(await svc.ingestBountyClaimEnvelope(
          await event.toEnvelope(claimant)), isFalse);
      expect(svc.isRemotelyClaimed(posted.id), isFalse);
    });
  });

  group('remote transport caller (InMemoryBountyTransport)', () {
    test('end-to-end: announce → attributed ingest → claim → signed '
        'claim event → poster sees settlement evidence', () async {
      final bus = InMemoryBountyTransport();

      // Poster node.
      final csA = CreditService(initialBalance: 100.0);
      final svcA = MoltbookService(
          creditService: csA, bountyTransport: bus.attach());
      addTearDown(svcA.dispose);
      final posterKp = await _newKey();
      await svcA.setKeyPair(posterKp);

      // Claimant node: trusts the attestor, rides the same bus.
      final attestor = await _newKey();
      final csB = CreditService(initialBalance: 100.0);
      final svcB = MoltbookService(
        creditService: csB,
        bountyTransport: bus.attach(),
        trustedAttestorPubkeys: {await _pubHex(attestor)},
      );
      addTearDown(svcB.dispose);
      await svcB.setKeyPair(await _newKey());

      // 1. Poster announces — the signed envelope flows over the
      //    transport and lands attributed (unfunded: the post carries
      //    no attestation).
      final posted = await svcA.postPreservationBounty(
        cid: 'bafk_e2e',
        title: 'e2e bounty',
        offeredCredits: 20.0,
        force: true,
      );
      await _settle();
      expect(svcB.isOriginVerified(posted.id), isTrue);
      var stored = svcB.activeBounties
          .firstWhere((b) => b.id == posted.id, orElse: () =>
              throw StateError('announcement not ingested'));
      expect(stored.funded, isFalse); // unattested → unfunded
      expect(stored.originAgentId, await _agentId(posterKp));

      // 2. Re-announce WITH an attestor-signed escrow attestation
      //    carried inside the envelope payload → dedup-upgrade to
      //    funded. Signed over the poster's announcement fields.
      final attBlock = await _attestationBlock(attestor,
          bountyId: posted.id,
          cid: posted.cid,
          amountMilli: (posted.offeredCredits * 1000).round());
      final fundedEnv = await BeaconEnvelope.create(
        kind: 'preservation_bounty',
        keyPair: posterKp,
        payload: {
          ...posted.toJson(),
          'escrow_attestation': attBlock,
        },
      );
      await svcB.ingestBountyEnvelope(fundedEnv);
      stored = svcB.activeBounties.firstWhere((b) => b.id == posted.id);
      expect(stored.funded, isTrue);

      // 3. Claimant wins the bounty (no ipfs → evidence check skipped);
      //    the won claim publishes a signed claim event.
      expect(await svcB.claimBounty(posted.id), isTrue);
      expect(csB.balance, 120.0);
      await _settle();

      // 4. Poster's node ingests the claim event: settlement evidence
      //    attributed to the claimant's key, record claimed, cancel
      //    refuses to free the spoken-for escrow.
      expect(svcA.isRemotelyClaimed(posted.id), isTrue);
      expect(await svcA.cancelBounty(posted.id), isFalse);
      expect(csA.balance, 80.0); // escrow still locked
      final claim = svcA.remoteClaimFor(posted.id);
      expect(claim, isNotNull);
      expect(claim!.claimantAgentId, svcB.agentId);
    });

    test('forged claim events injected on the bus are dropped', () async {
      final bus = InMemoryBountyTransport();
      final csA = CreditService(initialBalance: 100.0);
      final svcA = MoltbookService(
          creditService: csA, bountyTransport: bus.attach());
      addTearDown(svcA.dispose);
      await svcA.setKeyPair(await _newKey());

      final posted = await svcA.postPreservationBounty(
        cid: 'bafk_f',
        title: 't',
        offeredCredits: 10.0,
        force: true,
      );

      // An attacker on the bus claims our bounty with a signature that
      // does not bind the posted cid.
      final attacker = await _newKey();
      final bogus = await BountyClaimEvent.issue(
          keyPair: attacker, bountyId: posted.id, cid: 'bafk_wrong');
      await bus.attach().publish(await bogus.toEnvelope(attacker));
      await _settle();
      expect(svcA.isRemotelyClaimed(posted.id), isFalse);
      expect(svcA.activeBounties.any((b) => b.id == posted.id), isTrue);
    });
  });
}
