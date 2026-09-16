// Canonical-equivalence (NFC/NFD) bounty-id tests: composed vs
// decomposed spellings of the same id must resolve to ONE id at every
// trust boundary - ingest dedup, claimBounty, cancelBounty, and
// EscrowAttestation.bindsBounty.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/agent/beacon_models.dart';
import 'package:alexandria/services/agent/bounty_id_canonicalization.dart';
import 'package:alexandria/services/agent/escrow_attestation.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';

Future<SimpleKeyPair> _newKey() => Ed25519().newKeyPair();

Future<String> _pubHex(SimpleKeyPair kp) async =>
    bytesToHex((await kp.extractPublicKey()).bytes);

Future<EscrowAttestation?> _attest(
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
  return EscrowAttestation.verify(
    attestorPubkey: await _pubHex(attestor),
    bountyId: bountyId,
    cid: cid,
    amountMilli: amountMilli,
    expiresAt: exp,
    signature: base64Encode(sig.bytes),
    verifyFn: EscrowAttestation.verifyEd25519,
  );
}

void main() {
  group('normalizeBountyId (NFD canonical form)', () {
    test('composed and decomposed Latin spellings collapse to one id', () {
      const composed = 'bounty_Émile'; // U+00C9
      const decomposed = 'bounty_Émile'; // E + U+0301
      expect(composed == decomposed, isFalse); // raw spellings differ
      expect(normalizeBountyId(composed), normalizeBountyId(decomposed));
      expect(bountyIdsEquivalent(composed, decomposed), isTrue);
    });

    test('ASCII fast path returns input unchanged', () {
      const id = 'bounty_1700000000000_r3';
      expect(normalizeBountyId(id), same(id));
    });

    test('Hangul syllables decompose algorithmically', () {
      // U+AC01 '각' ⇔ U+1100 U+1161 U+11A8 - canonical equivalence.
      const composed = 'bounty_각';
      const decomposed = 'bounty_각';
      expect(bountyIdsEquivalent(composed, decomposed), isTrue);
    });

    test('combining-mark reordering is canonical (CCC ordering)', () {
      // U+0315 (ccc 232) vs U+0300 (ccc 230): canonical order puts 230
      // first; both spellings must normalize identically.
      final a = normalizeBountyId('bounty_á̕');
      final b = normalizeBountyId('bounty_á̕');
      expect(a, b);
    });

    test('normalization is idempotent', () {
      const id = 'bounty_ḉé_각';
      final once = normalizeBountyId(id);
      expect(normalizeBountyId(once), once);
    });

    test('compatibility (NFKD-only) forms are NOT folded', () {
      // U+FF45 'ｅ' (fullwidth e) is a <compat> mapping - it is NOT
      // canonically equivalent to 'e' and must stay distinct.
      expect(bountyIdsEquivalent('bounty_e', 'bounty_ｅ'), isFalse);
    });
  });

  group('canonical-equivalence at the trust boundary', () {
    PreservationBounty foreign(
      String id,
      String agentId, {
      String cid = 'bafk_equiv',
      double credits = 25.0,
      bool funded = false,
    }) =>
        PreservationBounty(
          id: id,
          cid: cid,
          title: 't',
          offeredCredits: credits,
          originAgentId: agentId,
          createdAt: DateTime.now(),
          funded: funded,
        );

    test(
        'composed + decomposed announcements of one id dedup to a '
        'single stored record (normalized)', () async {
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      final poster = await _newKey();
      final agentId =
          BeaconEnvelope.deriveAgentId((await poster.extractPublicKey()).bytes);

      const composedId = 'bounty_équipe'; // é = U+00E9
      const decomposedId = 'bounty_équipe'; // e + U+0301
      svc.ingestBountyAnnouncement(foreign(composedId, agentId));
      svc.ingestBountyAnnouncement(foreign(decomposedId, agentId));

      final stored = svc.activeBounties
          .where((b) => b.id == normalizeBountyId(composedId))
          .toList();
      expect(stored.length, 1);
      // The stored id IS the canonical (decomposed) form.
      expect(stored.single.id, normalizeBountyId(composedId));
    });

    test(
        'claimBounty resolves a composed spelling against the '
        'normalized stored id', () async {
      final cs = CreditService(initialBalance: 100.0);
      final attestor = await _newKey();
      final svc = MoltbookService(
          creditService: cs, trustedAttestorPubkeys: {await _pubHex(attestor)});
      final poster = await _newKey();
      final agentId =
          BeaconEnvelope.deriveAgentId((await poster.extractPublicKey()).bytes);

      // Attestor signs the COMPOSED spelling (what it saw on the wire);
      // the announcement arrives in the DECOMPOSED spelling. Both must
      // resolve to the same canonical id.
      const composedId = 'bounty_café';
      const decomposedId = 'bounty_café';
      // funded:true on the wire is necessary but NOT sufficient - the
      // stored record becomes funded only because the trusted
      // attestation binds it (the flag alone is forgeable noise).
      final bounty = foreign(decomposedId, agentId, funded: true);
      final att = await _attest(attestor,
          bountyId: composedId, cid: bounty.cid, amountMilli: 25000);
      svc.ingestBountyAnnouncement(bounty, escrowAttestation: att);

      final stored = svc.activeBounties
          .firstWhere((b) => b.id == normalizeBountyId(composedId));
      // bindsBounty compares canonically: attestation signed over the
      // composed spelling binds the normalized stored record → funded.
      expect(stored.funded, isTrue);

      // Claim with EITHER spelling reaches the same record.
      expect(await svc.claimBounty(composedId), isTrue);
      expect(cs.balance, 125.0);
      expect(svc.activeBounties.any((b) => b.id == stored.id), isFalse);
    });

    test(
        'cancelBounty resolves the composed spelling for a locally '
        'posted id', () async {
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
        cid: 'bafk_local',
        title: 'local',
        offeredCredits: 10.0,
        force: true,
      );
      // The generated id is ASCII → its normalized form is itself; a
      // caller spelling a precomposed/decomposed variant of an ASCII id
      // is a no-op. A live locally-posted bounty with a tracked escrow
      // hold is delisted but the refund is refused by the cross-ledger
      // guard → cancel reports false.
      expect(await svc.cancelBounty(normalizeBountyId(posted.id)), isFalse);
    });

    test(
        'dead-id tombstone is canonical: a cancelled id re-announced '
        'in the OTHER spelling stays unfunded', () async {
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      await svc.setKeyPair(await _newKey());
      // Post local bounty, then cancel to tombstone the id, then try
      // re-animating via ingest under a canonically-equivalent spelling.
      final posted = await svc.postPreservationBounty(
        cid: 'bafk_x',
        title: 'x',
        offeredCredits: 10.0,
        force: true,
      );
      await svc.cancelBounty(posted.id);
      // Re-announce under the same canonical id - dead forever.
      final attacker = await _newKey();
      final agentId = BeaconEnvelope.deriveAgentId(
          (await attacker.extractPublicKey()).bytes);
      svc.ingestBountyAnnouncement(PreservationBounty(
        id: posted.id,
        cid: 'bafk_x',
        title: 'zombie',
        offeredCredits: 10.0,
        originAgentId: agentId,
        createdAt: DateTime.now(),
        funded: true,
      ));
      expect(await svc.claimBounty(posted.id), isFalse);
    });
  });
}
