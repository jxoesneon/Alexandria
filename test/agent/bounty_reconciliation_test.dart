// Review REV4 regression tests: crash-window claim reconciliation
// (CAS-loss healer), startup claimed_bounties sweep, awaited payout
// durability, escrow cancel path, canonical bounty-id rejection, the
// bounded _bounties registry, and the verified ingestBountyEnvelope seam.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:alexandria/data/database.dart'
    show AppDatabase, ClaimedBountiesCompanion;
import 'package:alexandria/services/agent/beacon_models.dart';
import 'package:alexandria/services/agent/escrow_attestation.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/ipfs_service.dart';

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
}) {
  return PreservationBounty(
    id: id,
    cid: cid,
    title: 'Foreign bounty $id',
    offeredCredits: offeredCredits,
    originAgentId: originAgentId,
    createdAt: DateTime.now(),
    funded: funded,
  );
}

/// Inserts a claimed_bounties row with a caller-chosen claimedAt.
Future<void> _insertClaimRow(
  AppDatabase db,
  String bountyId, {
  required int claimedAt,
}) {
  return db.into(db.claimedBounties).insert(
        ClaimedBountiesCompanion.insert(
          bountyId: bountyId,
          cid: 'bafk_$bountyId',
          claimedAt: claimedAt,
        ),
      );
}

Future<void> _insertPayoutRow(AppDatabase db, String bountyId) {
  return db.insertCreditTransaction({
    'id': 'tx_bounty_payout_$bountyId',
    'timestamp': DateTime.now(),
    'type': 'verificationReward',
    'amount': 25.0,
    'description': 'Bounty Escrow Payout ($bountyId)',
    'hash': 'h_$bountyId',
  });
}

int _ageMillis(Duration d) =>
    DateTime.now().subtract(d).millisecondsSinceEpoch;

/// Runs event-loop turns until [condition] holds (bounded — the startup
/// sweep is fire-and-forget off the constructor).
Future<void> _until(Future<bool> Function() condition) async {
  for (var i = 0; i < 50; i++) {
    if (await condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('crash-window reconciliation (REV4 items 1+2)', () {
    test('CAS-loss + durable payout row → stored record is healed to '
        'claimed (listed-but-paid staleness closed)', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final bounty = _foreignBounty(id: 'bounty_paid', cid: 'bafk_paid');
      final attestor = await _newKey();
      final att = await _attestBounty(attestor, bounty);
      final svc = MoltbookService(
          creditService: cs, db: db, trustedAttestorPubkeys: {await _pubHex(attestor)});
      svc.ingestBountyAnnouncement(bounty, escrowAttestation: att);

      // Simulate a previous incarnation that won the CAS AND landed its
      // payout but never marked the in-memory record (restart+paid).
      await _insertClaimRow(db, bounty.id,
          claimedAt: DateTime.now().millisecondsSinceEpoch);
      await _insertPayoutRow(db, bounty.id);

      expect(await svc.claimBounty(bounty.id), isFalse);
      // Healed: the stored record is now claimed — delisted, and the
      // steward's head-of-line is unblocked.
      expect(
          svc.activeBounties.any((b) => b.id == bounty.id), isFalse);
      expect(await db.isBountyClaimed(bounty.id), isTrue);
      // No second payout: the balance gained nothing.
      expect(cs.balance, 100.0);
    });

    test('CAS-loss + stale claim row + no payout → row deleted, CAS '
        'retried, claim wins normally', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      final bounty =
          _foreignBounty(id: 'bounty_stale', cid: 'bafk_stale');
      final attestor = await _newKey();
      final att = await _attestBounty(attestor, bounty);
      final svc = MoltbookService(
          creditService: cs, db: db, trustedAttestorPubkeys: {await _pubHex(attestor)});
      svc.ingestBountyAnnouncement(bounty, escrowAttestation: att);

      // A claim stranded 20 minutes ago — crash between CAS and payout.
      await _insertClaimRow(db, bounty.id,
          claimedAt: _ageMillis(const Duration(minutes: 20)));

      // The healer deletes the stale row and retries the CAS — the
      // retry wins and the claim proceeds to payout.
      expect(await svc.claimBounty(bounty.id), isTrue);
      expect(await db.isBountyClaimed(bounty.id), isTrue);
      expect(cs.balance, 125.0);
      expect(
          svc.activeBounties.any((b) => b.id == bounty.id), isFalse);
    });

    test('CAS-loss + ORPHANED row (gone between CAS and age read) → '
        'treated as stale: delete no-ops, retry wins', () async {
      // Modelled by a deleteClaimedBounty that removes the row between
      // the lost CAS and the claimedAt read — the simplest faithful
      // stand-in is a claimedAt read that observes a vanished row.
      final db = _DeleteBeforeReadDb();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      final bounty =
          _foreignBounty(id: 'bounty_orphan', cid: 'bafk_orphan');
      final attestor = await _newKey();
      final att = await _attestBounty(attestor, bounty);
      final svc = MoltbookService(
          creditService: cs, db: db, trustedAttestorPubkeys: {await _pubHex(attestor)});
      svc.ingestBountyAnnouncement(bounty, escrowAttestation: att);
      await db.insertClaimedBounty(bounty.id, bounty.cid);

      expect(await svc.claimBounty(bounty.id), isTrue);
      expect(cs.balance, 125.0);
    });

    test('CAS-loss + YOUNG row + no payout → genuinely in-flight '
        'elsewhere: refused, record stays listed and unpoisoned',
        () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      final bounty =
          _foreignBounty(id: 'bounty_young', cid: 'bafk_young');
      final attestor = await _newKey();
      final att = await _attestBounty(attestor, bounty);
      final svc = MoltbookService(
          creditService: cs, db: db, trustedAttestorPubkeys: {await _pubHex(attestor)});
      svc.ingestBountyAnnouncement(bounty, escrowAttestation: att);

      // A fresh claim row with NO payout — a live claim in flight.
      await db.insertClaimedBounty(bounty.id, bounty.cid);

      expect(await svc.claimBounty(bounty.id), isFalse);
      // Not poisoned, not healed: still listed, row still stands, and
      // crucially the young row was NOT deleted.
      expect(svc.activeBounties.any((b) => b.id == bounty.id), isTrue);
      expect(await db.isBountyClaimed(bounty.id), isTrue);
      expect(cs.balance, 100.0);
    });
  });

  group('startup reconciliation sweep (REV4 item 2)', () {
    test('stale claim row with no payout is swept at construction',
        () async {
      final db = AppDatabase();
      addTearDown(db.close);
      await _insertClaimRow(db, 'bounty_sweep',
          claimedAt: _ageMillis(const Duration(hours: 1)));
      final cs = CreditService(initialBalance: 100.0);
      MoltbookService(creditService: cs, db: db);
      await _until(() async => !await db.isBountyClaimed('bounty_sweep'));
      expect(await db.isBountyClaimed('bounty_sweep'), isFalse);
    });

    test('stale claim row WITH a payout row is kept — the claim '
        'durably settled', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      await _insertClaimRow(db, 'bounty_swept_paid',
          claimedAt: _ageMillis(const Duration(hours: 1)));
      await _insertPayoutRow(db, 'bounty_swept_paid');
      final cs = CreditService(initialBalance: 100.0);
      MoltbookService(creditService: cs, db: db);
      // Give the sweep every chance to run, then verify it kept the row.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(await db.isBountyClaimed('bounty_swept_paid'), isTrue);
    });

    test('young claim row with no payout is kept — possibly a live '
        'claim', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      await db.insertClaimedBounty('bounty_sweep_young', 'bafk_y');
      final cs = CreditService(initialBalance: 100.0);
      MoltbookService(creditService: cs, db: db);
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(await db.isBountyClaimed('bounty_sweep_young'), isTrue);
    });
  });

  group('awaited payout durability (REV4 item 3)', () {
    test('a returned-true claim already has its payout row in the db — '
        'no extra settle await needed', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final bounty =
          _foreignBounty(id: 'bounty_durable', cid: 'bafk_durable');
      final attestor = await _newKey();
      final att = await _attestBounty(attestor, bounty);
      final svc = MoltbookService(
          creditService: cs, db: db, trustedAttestorPubkeys: {await _pubHex(attestor)});
      svc.ingestBountyAnnouncement(bounty, escrowAttestation: att);

      expect(await svc.claimBounty(bounty.id), isTrue);
      // The payout row provably landed BEFORE claimBounty returned.
      expect(await db.hasCreditTransaction('tx_bounty_payout_${bounty.id}'),
          isTrue);
      expect(cs.balance, 125.0);
    });
  });

  group('cancelBounty escrow release (REV4 item 4)', () {
    test('local unclaimed bounty → refund lands, balance restored',
        () async {
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_cancel', title: 'cancel me', offeredCredits: 25.0,
          force: true);
      expect(cs.balance, 75.0); // escrowed

      expect(await svc.cancelBounty(posted.id), isTrue);
      expect(cs.balance, 100.0); // refunded in full
      expect(svc.activeBounties.any((b) => b.id == posted.id), isFalse);
    });

    test('claimed bounty → refused (durable claim row wins over the '
        'in-memory flag)', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final svc = MoltbookService(creditService: cs, db: db);
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_claimed_cancel', title: 't', offeredCredits: 25.0,
          force: true);
      // A claim row stands — the escrow is spoken for even though the
      // in-memory flag was never set on this service.
      await db.insertClaimedBounty(posted.id, posted.cid);
      expect(await svc.cancelBounty(posted.id), isFalse);
      expect(cs.balance, 75.0); // hold untouched
      expect(svc.activeBounties.any((b) => b.id == posted.id), isTrue);
    });

    test('foreign bounty → refused (its escrow is on someone else\'s '
        'ledger)', () async {
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      final foreign =
          _foreignBounty(id: 'bounty_foreign', cid: 'bafk_foreign');
      svc.ingestBountyAnnouncement(foreign);
      expect(await svc.cancelBounty('bounty_foreign'), isFalse);
      expect(cs.balance, 100.0);
    });

    test('double-cancel → second call refused', () async {
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_dbl_cancel', title: 't', offeredCredits: 25.0,
          force: true);
      expect(await svc.cancelBounty(posted.id), isTrue);
      expect(await svc.cancelBounty(posted.id), isFalse);
      expect(cs.balance, 100.0); // exactly one refund
    });
  });

  group('canonical bounty-id rejection (REV4 item 4)', () {
    test('blank, padded, control-char and overlong ids are dropped at '
        'ingest — never normalized', () async {
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      final badIds = [' x', 'x ', 'x\x00y', 'x' * 200, ''];
      for (var i = 0; i < badIds.length; i++) {
        svc.ingestBountyAnnouncement(
            _foreignBounty(id: badIds[i], cid: 'bafk_bad_$i'));
      }
      final stored = svc.activeBounties.map((b) => b.id).toSet();
      for (final bad in badIds) {
        expect(stored.contains(bad), isFalse, reason: 'id "$bad"');
      }
      // The two seeded bounties are untouched.
      expect(stored.containsAll(['bounty_1001', 'bounty_1002']), isTrue);
    });

    test('claim arg " x " still fails lookup — raw == is load-bearing',
        () async {
      final cs = CreditService(initialBalance: 100.0);
      final attestor = await _newKey();
      final svc = MoltbookService(
          creditService: cs, trustedAttestorPubkeys: {await _pubHex(attestor)});
      final bounty = _foreignBounty(id: 'x', cid: 'bafk_x');
      svc.ingestBountyAnnouncement(bounty,
          escrowAttestation: await _attestBounty(attestor, bounty));
      expect(await svc.claimBounty(' x '), isFalse);
      expect(await svc.claimBounty('x'), isTrue);
    });
  });

  group('bounded _bounties registry (REV4 item 5)', () {
    test('600 unfunded announcements → registry stays ≤512; a funded '
        'announcement still displaces an unfunded record', () async {
      final cs = CreditService(initialBalance: 100.0);
      final attestor = await _newKey();
      final svc = MoltbookService(
          creditService: cs, trustedAttestorPubkeys: {await _pubHex(attestor)});
      for (var i = 0; i < 600; i++) {
        svc.ingestBountyAnnouncement(_foreignBounty(
            id: 'flood_$i', cid: 'bafk_flood_$i', funded: false));
      }
      expect(svc.activeBounties.length, lessThanOrEqualTo(512));

      // A funded + attested announcement is still admitted — it evicts
      // the oldest UNFUNDED record (the two seeds are the oldest).
      final funded = _foreignBounty(
          id: 'funded_keep', cid: 'bafk_funded_keep');
      svc.ingestBountyAnnouncement(funded,
          escrowAttestation: await _attestBounty(attestor, funded));
      expect(svc.activeBounties.length, lessThanOrEqualTo(512));
      final stored =
          svc.activeBounties.firstWhere((b) => b.id == 'funded_keep');
      expect(stored.funded, isTrue);
    });

    test('an all-funded registry drops incoming UNFUNDED announcements '
        'and evicts oldest funded only for incoming funded', () async {
      final cs = CreditService(initialBalance: 100.0);
      final attestor = await _newKey();
      final svc = MoltbookService(
          creditService: cs, trustedAttestorPubkeys: {await _pubHex(attestor)});

      // Fill the registry to capacity with funded announcements.
      // Capacity is 512 minus the 2 unfunded seeds — those get evicted
      // by the first two funded inserts anyway.
      for (var i = 0; i < 512; i++) {
        final b = _foreignBounty(id: 'fund_$i', cid: 'bafk_fund_$i');
        svc.ingestBountyAnnouncement(b,
            escrowAttestation: await _attestBounty(attestor, b));
      }
      expect(svc.activeBounties.length, 512);
      expect(svc.activeBounties.every((b) => b.funded), isTrue);

      // Unfunded spam is now dropped outright.
      svc.ingestBountyAnnouncement(_foreignBounty(
          id: 'spam_drop', cid: 'bafk_spam', funded: false));
      expect(svc.activeBounties.length, 512);
      expect(svc.activeBounties.any((b) => b.id == 'spam_drop'), isFalse);

      // A funded announcement still lands — it evicts the OLDEST funded
      // record (fund_0, ingested first).
      final late = _foreignBounty(id: 'fund_late', cid: 'bafk_late');
      svc.ingestBountyAnnouncement(late,
          escrowAttestation: await _attestBounty(attestor, late));
      expect(svc.activeBounties.length, 512);
      expect(svc.activeBounties.any((b) => b.id == 'fund_late'), isTrue);
      expect(svc.activeBounties.any((b) => b.id == 'fund_0'), isFalse);
      expect(svc.activeBounties.any((b) => b.id == 'fund_1'), isTrue);
    });
  });

  group('ingestBountyEnvelope verified seam (REV4 item 6)', () {
    Future<BeaconEnvelope> envelopeFor(
      SimpleKeyPair poster,
      PreservationBounty bounty, {
      String kind = 'preservation_bounty',
    }) =>
        BeaconEnvelope.create(
            kind: kind, keyPair: poster, payload: bounty.toJson());

    Future<PreservationBounty> signedBy(
        SimpleKeyPair poster, String id) async {
      final pub = await poster.extractPublicKey();
      return _foreignBounty(
        id: id,
        cid: 'bafk_$id',
        originAgentId: BeaconEnvelope.deriveAgentId(pub.bytes),
      );
    }

    test('valid envelope + trusted attestation → stored funded', () async {
      final poster = await _newKey();
      final attestor = await _newKey();
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(
          creditService: cs, trustedAttestorPubkeys: {await _pubHex(attestor)});
      final bounty = await signedBy(poster, 'bounty_env');
      final att = await _attestBounty(attestor, bounty);
      await svc.ingestBountyEnvelope(await envelopeFor(poster, bounty),
          escrowAttestation: att);
      final stored =
          svc.activeBounties.firstWhere((b) => b.id == 'bounty_env');
      expect(stored.funded, isTrue);
    });

    test('forged signature → dropped', () async {
      final poster = await _newKey();
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      final bounty = await signedBy(poster, 'bounty_forged');
      final env = await envelopeFor(poster, bounty);
      // Tamper the payload post-signing — the envelope no longer
      // verifies and must be dropped before parsing.
      final forged = BeaconEnvelope(
        kind: env.kind,
        agentId: env.agentId,
        ts: env.ts,
        nonce: env.nonce,
        pubkey: env.pubkey,
        sig: env.sig,
        payload: {...env.payload, 'offered_credits': 9999.0},
      );
      await svc.ingestBountyEnvelope(forged);
      expect(svc.activeBounties.any((b) => b.id == 'bounty_forged'),
          isFalse);
    });

    test('envelope.agentId != bounty.originAgentId → dropped (no '
        'relayed authorship claims)', () async {
      final poster = await _newKey();
      final imposter = await _newKey();
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      // Signed by `imposter` but claiming `poster`'s agent id.
      final pub = await poster.extractPublicKey();
      final bounty = _foreignBounty(
        id: 'bounty_relay',
        cid: 'bafk_relay',
        originAgentId: BeaconEnvelope.deriveAgentId(pub.bytes),
      );
      await svc.ingestBountyEnvelope(
          await envelopeFor(imposter, bounty));
      expect(svc.activeBounties.any((b) => b.id == 'bounty_relay'),
          isFalse);
    });

    test('malformed payload → dropped without throwing', () async {
      final poster = await _newKey();
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      final env = await BeaconEnvelope.create(
          kind: 'preservation_bounty',
          keyPair: poster,
          payload: {'not': 'a bounty'});
      await svc.ingestBountyEnvelope(env); // must not throw
      expect(svc.activeBounties.length, 2); // only the seeds
    });

    test('non-bounty envelope kind → dropped (unknown kinds fail '
        'closed)', () async {
      final poster = await _newKey();
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      final bounty = await signedBy(poster, 'bounty_kind');
      await svc.ingestBountyEnvelope(
          await envelopeFor(poster, bounty, kind: 'chat_message'));
      expect(svc.activeBounties.any((b) => b.id == 'bounty_kind'),
          isFalse);
    });
  });

  // ═══════════════════ E-REV4b regression fixes ═══════════════════
  group('E-REV4b hardening fixes', () {
    test('F2: a lost payout write cannot re-pay after restart — the '
        'durable escrow tombstone makes the id permanently un-payable',
        () async {
      final db = _PayoutWriteLostDb();
      addTearDown(db.close);
      final cs1 = CreditService(db: db, initialBalance: 100.0);
      await cs1.ready;
      final bounty = _foreignBounty(id: 'bounty_lost', cid: 'bafk_lost');
      final attestor = await _newKey();
      final hex = await _pubHex(attestor);
      final svc1 = MoltbookService(
          creditService: cs1, db: db, trustedAttestorPubkeys: {hex});
      svc1.ingestBountyAnnouncement(bounty,
          escrowAttestation: await _attestBounty(attestor, bounty));

      // The mint happened in-memory; the durable payout row did NOT.
      expect(await svc1.claimBounty(bounty.id), isTrue);
      expect(cs1.balance, 125.0);
      expect(await db.isBountyClaimed(bounty.id), isTrue);
      expect(await db.hasCreditTransaction('tx_bounty_payout_${bounty.id}'),
          isFalse);
      // The do-not-pay tombstone landed in its place.
      expect(
          await db
              .hasCreditTransaction('tx_escrow_release_${bounty.id}'),
          isTrue);

      // Restart + row aging: the healer re-wins the CAS, but the fresh
      // CreditService rebuilt _releasedEscrowIds from the tombstone —
      // awardBountyEscrow refuses, so no second mint.
      await db.deleteClaimedBounty(bounty.id);
      await _insertClaimRow(db, bounty.id,
          claimedAt: _ageMillis(const Duration(minutes: 20)));
      final cs2 = CreditService(db: db, initialBalance: 0.0);
      await cs2.ready;
      expect(cs2.balance, 100.0);
      final svc2 = MoltbookService(
          creditService: cs2, db: db, trustedAttestorPubkeys: {hex});
      svc2.ingestBountyAnnouncement(bounty,
          escrowAttestation: await _attestBounty(attestor, bounty));
      expect(await svc2.claimBounty(bounty.id), isFalse);
      expect(cs2.balance, 100.0);
      // The id is dead at the credit layer too — a direct re-pay is
      // refused by the hydrated release-dedup set.
      expect(
          cs2.awardBountyEscrow(
              amount: 25.0, bountyId: bounty.id, cid: bounty.cid),
          0.0);
    });

    test('F6: a hung payout write cannot park claimBounty forever — '
        'the settle wait is bounded', () async {
      final db = _PayoutWriteHangsDb();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final bounty = _foreignBounty(id: 'bounty_hang', cid: 'bafk_hang');
      final attestor = await _newKey();
      final svc = MoltbookService(
          creditService: cs, db: db, trustedAttestorPubkeys: {await _pubHex(attestor)});
      svc.ingestBountyAnnouncement(bounty,
          escrowAttestation: await _attestBounty(attestor, bounty));

      var done = false;
      unawaited(svc.claimBounty(bounty.id).then((_) => done = true));
      for (var i = 0; i < 40 && !done; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(done, isTrue,
          reason: 'a wedged ledger write must not park a won claim');
      expect(await db.isBountyClaimed(bounty.id), isTrue);
    });

    test('F4: the startup sweep deletes by SNAPSHOT claimedAt — a claim '
        'row re-inserted mid-sweep is not torn down', () async {
      final db = _SweepProbeGateDb();
      addTearDown(db.close);
      await _insertClaimRow(db, 'bounty_sweep_race',
          claimedAt: _ageMillis(const Duration(minutes: 20)));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final gated = container.read(_gatedIpfsProvider) as _GatedIpfs;
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final bounty =
          _foreignBounty(id: 'bounty_sweep_race', cid: 'bafk_sr');
      final attestor = await _newKey();
      final svc = MoltbookService(
          creditService: cs,
          db: db,
          ipfsService: gated,
          trustedAttestorPubkeys: {await _pubHex(attestor)});
      svc.ingestBountyAnnouncement(bounty,
          escrowAttestation: await _attestBounty(attestor, bounty));

      // Let the sweep reach its parked per-row probe (stale snapshot
      // already taken).
      while (!db.firstProbeParked) {
        await Future<void>.delayed(Duration.zero);
      }
      // The claim: CAS loses → probe (ungated call) → "stale" → delete
      // → retry CAS wins a FRESH row → parks in gated evidence.
      var done = false;
      bool? result;
      unawaited(svc.claimBounty(bounty.id).then((r) {
        result = r;
        done = true;
      }));
      for (var i = 0; i < 50 && gated.calls == 0; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(gated.calls, greaterThan(0));

      // Release the sweep probe: its conditional delete targets the
      // SNAPSHOT claimedAt — the claim's new row must survive.
      db.probeGate.complete();
      gated.gate.complete();
      for (var i = 0; i < 50 && !done; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(done, isTrue);
      expect(result, isTrue);
      expect(cs.balance, 125.0);
      expect(await db.isBountyClaimed(bounty.id), isTrue,
          reason: 'the sweep must not delete a live claim\'s fresh row');
    });

    test('F5: a losing claim\'s release cannot delete a racing claim\'s '
        're-won row — self-cleanup is claimedAt-conditional', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final gated = container.read(_gatedIpfsProvider) as _GatedIpfs;
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final bounty = _foreignBounty(id: 'bounty_race', cid: 'bafk_race');
      final attestor = await _newKey();
      final hex = await _pubHex(attestor);
      final svcA = MoltbookService(
          creditService: cs,
          db: db,
          ipfsService: gated,
          trustedAttestorPubkeys: {hex});
      final svcB = MoltbookService(
          creditService: cs, db: db, trustedAttestorPubkeys: {hex});
      svcA.ingestBountyAnnouncement(bounty,
          escrowAttestation: await _attestBounty(attestor, bounty));
      svcB.ingestBountyAnnouncement(bounty,
          escrowAttestation: await _attestBounty(attestor, bounty));

      // A wins the CAS and parks in the gated evidence phase.
      final claimA = svcA.claimBounty(bounty.id);
      while (!await db.isBountyClaimed(bounty.id)) {
        await Future<void>.delayed(Duration.zero);
      }
      // Backdate A's live row past the stale TTL — B's healer then
      // observes the row's REAL claimedAt, so its ownership-conditional
      // delete still matches (RE-REV4b G). A faked age READ could never
      // authorize the delete — see the lying-read test below.
      await (db.update(db.claimedBounties)
            ..where((t) => t.bountyId.equals(bounty.id)))
          .write(ClaimedBountiesCompanion(
              claimedAt:
                  Value(_ageMillis(const Duration(minutes: 20)))));
      // B heals the genuinely stale row, re-wins the CAS, pays.
      expect(await svcB.claimBounty(bounty.id), isTrue);
      expect(cs.balance, 125.0);

      // A's evidence completes → the payout dedup belt refuses → A's
      // conditional release targets A's own claimedAt — B's row stands.
      gated.gate.complete();
      expect(await claimA, isFalse);
      expect(await db.isBountyClaimed(bounty.id), isTrue,
          reason: 'a paid claim must never end without its durable row');
    });

    test('F1: a cancelled id is a permanent tombstone — re-ingest '
        'stores a dead unfunded record that no claim or upgrade can '
        're-arm', () async {
      final cs = CreditService(initialBalance: 100.0);
      final attestor = await _newKey();
      final svc = MoltbookService(
          creditService: cs, trustedAttestorPubkeys: {await _pubHex(attestor)});
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_dead', title: 't', offeredCredits: 25.0,
          force: true);
      expect(await svc.cancelBounty(posted.id), isTrue);
      expect(cs.balance, 100.0);

      // A relayer re-announces the id with a foreign origin and a
      // valid trusted attestation — the record is stored but dead.
      final reannounced = _foreignBounty(
          id: posted.id, cid: posted.cid, offeredCredits: 25.0);
      svc.ingestBountyAnnouncement(reannounced,
          escrowAttestation:
              await _attestBounty(attestor, reannounced));
      final stored =
          svc.activeBounties.firstWhere((b) => b.id == posted.id);
      expect(stored.funded, isFalse,
          reason: 'a cancelled id must never be re-funded');
      expect(await svc.claimBounty(posted.id), isFalse);
      expect(cs.balance, 100.0);

      // A second attested re-announcement cannot upgrade the dead
      // record either.
      svc.ingestBountyAnnouncement(reannounced,
          escrowAttestation:
              await _attestBounty(attestor, reannounced));
      expect(
          svc.activeBounties
              .firstWhere((b) => b.id == posted.id)
              .funded,
          isFalse);
    });

    test('F3: a cancel parked on the durable claim-read removes ONLY '
        'its own id — a concurrent ingest is not evicted by a stale '
        'index', () async {
      final db = _GatedClaimCheckDb();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final svc = MoltbookService(creditService: cs, db: db);
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_target', title: 't', offeredCredits: 25.0,
          force: true);

      final cancel = svc.cancelBounty(posted.id);
      while (db.calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      // Shift the list while the claim-read is parked.
      svc.ingestBountyAnnouncement(
          _foreignBounty(id: 'bounty_bystander', cid: 'bafk_by'));
      db.gate.complete();
      expect(await cancel, isTrue);
      expect(cs.balance, 100.0);
      expect(svc.activeBounties.any((b) => b.id == posted.id), isFalse);
      expect(svc.activeBounties.any((b) => b.id == 'bounty_bystander'),
          isTrue,
          reason: 'a stale positional index must not evict a bystander');
    });

    test('F3: two overlapping cancels serialize — exactly one reports '
        'success and the refund lands once', () async {
      final db = _GatedClaimCheckDb();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final svc = MoltbookService(creditService: cs, db: db);
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_pair', title: 't', offeredCredits: 25.0,
          force: true);

      final c1 = svc.cancelBounty(posted.id);
      final c2 = svc.cancelBounty(posted.id);
      while (db.calls < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      db.gate.complete();
      final results = {await c1, await c2};
      expect(results, {true, false});
      expect(cs.balance, 100.0); // exactly one refund
      // The tombstone survives key rotation — no self-claim laundering.
      await svc.setKeyPair(await _newKey());
      expect(await svc.claimBounty(posted.id), isFalse);
    });

    test('F7: a locally-posted bounty is NEVER registry-evicted — an '
        'attested funded flood drops the incoming record instead of '
        'stranding the escrow', () async {
      final cs = CreditService(initialBalance: 100.0);
      final attestor = await _newKey();
      final svc = MoltbookService(
          creditService: cs, trustedAttestorPubkeys: {await _pubHex(attestor)});
      await svc.setKeyPair(await _newKey());
      final posted = await svc.postPreservationBounty(
          cid: 'bafk_kept', title: 't', offeredCredits: 25.0,
          force: true);
      expect(cs.balance, 75.0);

      for (var i = 0; i < 520; i++) {
        final b = _foreignBounty(id: 'fl_$i', cid: 'bafk_fl_$i');
        svc.ingestBountyAnnouncement(b,
            escrowAttestation: await _attestBounty(attestor, b));
      }
      expect(svc.activeBounties.length, lessThanOrEqualTo(512));
      expect(svc.activeBounties.any((b) => b.id == posted.id), isTrue,
          reason: 'a locally escrowed record is never evictable');
      // The escrow stays reachable — cancel refunds it normally.
      expect(await svc.cancelBounty(posted.id), isTrue);
      expect(cs.balance, 100.0);
    });

    test('F8: interior whitespace, invisible format chars and C1 '
        'controls are rejected — never normalized', () async {
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      final badIds = [
        'a b', // interior space
        'a\tb', // interior tab
        'a\u00A0b', // interior NBSP
        'a\u200Bb', // zero-width space
        'a\u200Cb', // ZWNJ
        'a\u200Db', // ZWJ
        'a\u200Fb', // RLM
        'a\uFEFFb', // BOM / ZWNBSP
        'a\u009Bb', // C1 control (CSI)
        'a\u007Fb', // DEL
      ];
      for (var i = 0; i < badIds.length; i++) {
        svc.ingestBountyAnnouncement(
            _foreignBounty(id: badIds[i], cid: 'bafk_bad_$i'));
      }
      final stored = svc.activeBounties.map((b) => b.id).toSet();
      for (final bad in badIds) {
        expect(stored.contains(bad), isFalse, reason: 'id "$bad"');
      }
      // Legit ids unaffected — boundary length admitted.
      svc.ingestBountyAnnouncement(
          _foreignBounty(id: 'b' * 128, cid: 'bafk_ok'));
      expect(svc.activeBounties.any((b) => b.id == 'b' * 128), isTrue);
    });
  });

  group('RE-REV4b restart/durability regressions', () {
    test('RE-E1a: a cancelled bounty re-ingests DEAD after restart — '
        'durable release-row state rebuilds the tombstone, so a '
        'trusted re-announcement is stored unfunded and unclaimable',
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
          cid: 'bafk_z1', title: 't', offeredCredits: 25.0,
          force: true);
      expect(await svc1.cancelBounty(posted.id), isTrue);
      await cs1.settled;

      // Restart: new CreditService + new MoltbookService on the same db.
      final cs2 = CreditService(db: db, initialBalance: 0.0);
      await cs2.ready;
      final attestor = await _newKey();
      final svc2 = MoltbookService(
          creditService: cs2,
          db: db,
          trustedAttestorPubkeys: {await _pubHex(attestor)});
      // The dead-id ingest check is synchronous via isEscrowReleased —
      // no rebuild await needed for this assertion.
      final re = _foreignBounty(id: posted.id, cid: posted.cid);
      svc2.ingestBountyAnnouncement(re,
          escrowAttestation: await _attestBounty(attestor, re));

      final stored =
          svc2.activeBounties.firstWhere((b) => b.id == posted.id);
      expect(stored.funded, isFalse,
          reason: 'the durable release row must force-strip funded — '
              'a zombie must never re-ingest as claimable');
      expect(await svc2.claimBounty(posted.id), isFalse);
      expect(await svc2.cancelBounty(posted.id), isFalse);
      expect(cs2.balance, 100.0);
    });

    test('RE-E1b: a live locally-posted bounty stays cancellable after '
        'restart — the durable hold row rebuilds the locally-posted '
        'set; cancel tombstones and the hold stays releasable on '
        'demand', () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs1 = CreditService(db: db, initialBalance: 0.0);
      await cs1.ready;
      cs1.awardVerificationCredits(
          action: 'seed', targetId: 't', amount: 100.0);
      final svc1 = MoltbookService(creditService: cs1, db: db);
      await svc1.setKeyPair(await _newKey());
      final posted = await svc1.postPreservationBounty(
          cid: 'bafk_z2', title: 't', offeredCredits: 25.0,
          force: true);
      expect(cs1.balance, 75.0);
      await cs1.settled;

      final cs2 = CreditService(db: db, initialBalance: 0.0);
      await cs2.ready;
      final svc2 = MoltbookService(creditService: cs2, db: db);
      // cancelBounty awaits the hold-row rebuild internally — the
      // locally-posted set is restored before the gate runs.
      expect(await svc2.cancelBounty(posted.id), isTrue);
      // The cancel tombstones the id but leaves the durable hold for
      // the on-demand release path — nothing is stranded.
      expect(await cs2.releaseEscrow(referenceId: posted.id), 25.0);
      expect(cs2.balance, 100.0);
    });

    test('RE-E3: post-after-cancel never escrows onto a dead id — '
        'generated ids stay off the release/payout tombstones',
        () async {
      final db = AppDatabase();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 0.0);
      await cs.ready;
      cs.awardVerificationCredits(
          action: 'seed', targetId: 't', amount: 100.0);
      final svc = MoltbookService(creditService: cs, db: db);
      await svc.setKeyPair(await _newKey());

      final ids = <String>{};
      for (var i = 0; i < 12; i++) {
        final posted = await svc.postPreservationBounty(
            cid: 'bafk_cyc_$i', title: 't', offeredCredits: 10.0,
            force: true);
        expect(ids.add(posted.id), isTrue,
            reason: 'every generated id must be unique');
        expect(cs.isEscrowReleased(posted.id), isFalse,
            reason: 'a fresh escrow must never land on a dead id');
        expect(await svc.cancelBounty(posted.id), isTrue);
      }
      expect(cs.balance, 100.0);
    });

    test('RE-F: a lost payout row AND a lost tombstone stay pending — '
        'the next service sharing the db retries the tombstone and '
        'the claim refuses dead', () async {
      final db = _CorrelatedWriteLossDb();
      addTearDown(db.close);
      final cs1 = CreditService(db: db, initialBalance: 100.0);
      await cs1.ready;
      final attestor = await _newKey();
      final hex = await _pubHex(attestor);
      final bounty = _foreignBounty(id: 'bounty_rf', cid: 'bafk_rf');
      final svc1 = MoltbookService(
          creditService: cs1, db: db, trustedAttestorPubkeys: {hex});
      svc1.ingestBountyAnnouncement(bounty,
          escrowAttestation: await _attestBounty(attestor, bounty));

      db.armed = true;
      expect(await svc1.claimBounty(bounty.id), isTrue,
          reason: 'the mint did happen — the claim reports won even '
              'though BOTH durable writes died');
      db.armed = false;
      expect(
          await db.hasCreditTransaction('tx_escrow_release_${bounty.id}'),
          isFalse,
          reason: 'the tombstone write also died — it must stay '
              'pending, not silently re-open the double-pay');

      // "Restart": new services on the same db handle — the pending
      // tombstone is keyed by the shared database, so the next
      // claimBounty entry flushes it.
      final cs2 = CreditService(db: db, initialBalance: 0.0);
      await cs2.ready;
      final svc2 = MoltbookService(
          creditService: cs2, db: db, trustedAttestorPubkeys: {hex});
      svc2.ingestBountyAnnouncement(bounty,
          escrowAttestation: await _attestBounty(attestor, bounty));
      expect(await svc2.claimBounty(bounty.id), isFalse);
      expect(
          await db.hasCreditTransaction('tx_escrow_release_${bounty.id}'),
          isTrue,
          reason: 'the pending tombstone must land on the next claim');
      expect(cs2.balance, 100.0,
          reason: 'no second payout may ever mint for this escrow');
    });

    test('RE-G: the stale-row healer deletes by OBSERVED claimedAt — '
        'a racing claim re-winning the CAS in the gap keeps its fresh '
        'durable row', () async {
      final db = _FirstCondDeleteGateDb();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final attestor = await _newKey();
      final hex = await _pubHex(attestor);
      final bounty = _foreignBounty(id: 'bounty_rg', cid: 'bafk_rg');
      final svcB = MoltbookService(
          creditService: cs, db: db, trustedAttestorPubkeys: {hex});
      final svcC = MoltbookService(
          creditService: cs, db: db, trustedAttestorPubkeys: {hex});
      svcB.ingestBountyAnnouncement(bounty,
          escrowAttestation: await _attestBounty(attestor, bounty));
      svcC.ingestBountyAnnouncement(bounty,
          escrowAttestation: await _attestBounty(attestor, bounty));
      await _insertClaimRow(db, bounty.id,
          claimedAt: _ageMillis(const Duration(minutes: 20)));

      // B: CAS loses → probe → stale → conditional delete parks (call
      // #1) BEFORE it can remove the stale row.
      final claimB = svcB.claimBounty(bounty.id);
      while (!db.condDeleteParked) {
        await Future<void>.delayed(Duration.zero);
      }

      // C: same path, but its conditional delete is ungated (call #2)
      // → removes the stale row → CAS retry wins → pays.
      expect(await svcC.claimBounty(bounty.id), isTrue);

      // B's parked delete resumes — it must match only the OBSERVED
      // stale claimedAt, so C's fresh row survives.
      db.condDeleteGate.complete();
      expect(await claimB, isFalse);
      expect(await db.isBountyClaimed(bounty.id), isTrue,
          reason: "the paid claim's durable row must survive — the "
              'reconciler + restart dedup rely on it');
      expect(cs.balance, 125.0,
          reason: 'exactly one payout — the stale-read delete must '
              'not tear down a fresh claim row');
    });

    test('RE-Gb: a lying/corrupted age READ cannot authorize deleting a '
        'live row — the conditional delete matches only the stored '
        'claimedAt, so the claim fails closed and the row stands',
        () async {
      final db = _StaleAgeDb();
      addTearDown(db.close);
      final cs = CreditService(db: db, initialBalance: 100.0);
      await cs.ready;
      final attestor = await _newKey();
      final bounty = _foreignBounty(id: 'bounty_lie', cid: 'bafk_lie');
      final svc = MoltbookService(
          creditService: cs,
          db: db,
          trustedAttestorPubkeys: {await _pubHex(attestor)});
      svc.ingestBountyAnnouncement(bounty,
          escrowAttestation: await _attestBounty(attestor, bounty));
      // A FRESH row (a live claim in flight) that the age READ will
      // misreport as 20 minutes old.
      await _insertClaimRow(db, bounty.id,
          claimedAt: DateTime.now().millisecondsSinceEpoch);

      expect(await svc.claimBounty(bounty.id), isFalse);
      expect(await db.isBountyClaimed(bounty.id), isTrue,
          reason: 'the healer may only delete the row it actually '
              'observed — a mismatched timestamp means the row is '
              'someone else\'s and must stand');
      expect(cs.balance, 100.0);
    });

    test('RE-H: bidi controls, invisible operators, tag/shorthand '
        'characters, fillers and lone surrogates are rejected', () async {
      final cs = CreditService(initialBalance: 100.0);
      final svc = MoltbookService(creditService: cs);
      final badIds = [
        'a\u2028b', 'a\u2029b', 'a\u0085b',
        'a\u2060b', 'a\u2061b', 'a\u2064b',
        'a\u202Ab', 'a\u202Eb',
        'a\u2066b', 'a\u2069b',
        'a\u061Cb', 'a\u180Eb', 'a\u00ADb', 'a\u034Fb',
        'a\u115Fb', 'a\u1160b', 'a\u3164b', 'a\uFFA0b',
        'a\uFFF0b', 'a\uFFF8b',
        'a\u{1BCA0}b', 'a\u{1BCA3}b',
        'a\u{E0000}b', 'a\u{E0001}b', 'a\u{E0FFF}b',
        'a\uD800b', 'a\uDFFFb',
        '\u2060', '\u202E', '\u{E0001}',
      ];
      for (var i = 0; i < badIds.length; i++) {
        svc.ingestBountyAnnouncement(
            _foreignBounty(id: badIds[i], cid: 'bafk_hb_$i'));
      }
      final stored = svc.activeBounties.map((b) => b.id).toSet();
      for (final bad in badIds) {
        expect(stored.contains(bad), isFalse, reason: 'id "$bad"');
      }
      // Previously-covered classes stay rejected.
      for (final stillBad in [
        'a b', 'a\tb', 'a\u00A0b', 'a\u200Bb', 'a\uFEFFb',
        'a\u009Bb', 'a\u007Fb', ' lead', 'trail ',
      ]) {
        svc.ingestBountyAnnouncement(
            _foreignBounty(id: stillBad, cid: 'bafk_hc'));
        expect(stored.contains(stillBad), isFalse,
            reason: 'id "$stillBad"');
      }
      // Legit ids unaffected.
      svc.ingestBountyAnnouncement(
          _foreignBounty(id: 'bounty_legit', cid: 'bafk_hl'));
      expect(
          svc.activeBounties.any((b) => b.id == 'bounty_legit'), isTrue);
    });
  });
}

// ─────────────── RE-REV4b fakes ───────────────

/// Parks the FIRST ownership-conditional stale-row delete so a racing
/// claim can re-win the CAS in the gap (RE-REV4b G): the resumed delete
/// must match only the observed claimedAt, so the racer's fresh row
/// survives.
class _FirstCondDeleteGateDb extends AppDatabase {
  final Completer<void> condDeleteGate = Completer<void>();
  int condDeleteCalls = 0;
  bool condDeleteParked = false;

  @override
  Future<int> deleteClaimedBountyIfClaimedAt(
      String bountyId, int claimedAt) async {
    condDeleteCalls++;
    if (condDeleteCalls == 1) {
      condDeleteParked = true;
      await condDeleteGate.future;
    }
    return super.deleteClaimedBountyIfClaimedAt(bountyId, claimedAt);
  }
}

/// Correlated write loss (RE-REV4b F): while [armed], BOTH the payout
/// row and the release/tombstone row die in the same fault window —
/// the payout write is swallowed inside CreditService while the
/// tombstone write reaches the caller, so claimBounty must keep the
/// tombstone pending and retry it.
class _CorrelatedWriteLossDb extends AppDatabase {
  bool armed = false;

  @override
  Future<void> insertCreditTransaction(Map<String, dynamic> data) async {
    final id = data['id'] as String?;
    if (armed &&
        id != null &&
        (id.startsWith('tx_bounty_payout_') ||
            id.startsWith('tx_escrow_release_'))) {
      throw StateError('simulated correlated write loss');
    }
    return super.insertCreditTransaction(data);
  }
}

/// AppDatabase whose getClaimedBountyClaimedAt deletes the row first —
/// models the orphaned-row window: the CAS lost against a row that is
/// GONE by the time the age is read (the winner's release-delete landed
/// in between).
class _DeleteBeforeReadDb extends AppDatabase {
  @override
  Future<int?> getClaimedBountyClaimedAt(String bountyId) async {
    await deleteClaimedBounty(bountyId);
    return super.getClaimedBountyClaimedAt(bountyId);
  }
}

// ─────────────── E-REV4b fakes ───────────────

/// The durable payout-row write is LOST (throws → swallowed by
/// CreditService's best-effort persist). Every other write lands —
/// including the `tx_escrow_release_` tombstone.
class _PayoutWriteLostDb extends AppDatabase {
  @override
  Future<void> insertCreditTransaction(Map<String, dynamic> data) async {
    final id = data['id'] as String?;
    if (id != null && id.startsWith('tx_bounty_payout_')) {
      throw StateError('simulated payout-row write loss');
    }
    return super.insertCreditTransaction(data);
  }
}

/// The payout-row write never completes → CreditService.settled never
/// resolves → an unbounded wait would park claimBounty forever.
class _PayoutWriteHangsDb extends AppDatabase {
  @override
  Future<void> insertCreditTransaction(Map<String, dynamic> data) {
    final id = data['id'] as String?;
    if (id != null && id.startsWith('tx_bounty_payout_')) {
      return Completer<void>().future; // never completes
    }
    return super.insertCreditTransaction(data);
  }
}

/// Reports every extant claim row as 20 minutes old — models an age
/// READ that disagrees with the stored row (a stale/corrupted read).
/// Under the ownership-conditional healer (RE-REV4b G) the observed
/// timestamp can never match the live row, so the delete correctly
/// refuses and the row stands — a lying read fails CLOSED.
class _StaleAgeDb extends AppDatabase {
  @override
  Future<int?> getClaimedBountyClaimedAt(String bountyId) async {
    final real = await super.getClaimedBountyClaimedAt(bountyId);
    if (real == null) return null;
    return DateTime.now()
        .subtract(const Duration(minutes: 20))
        .millisecondsSinceEpoch;
  }
}

/// Gates isBountyClaimed so cancelBounty calls can be frozen across the
/// durable claim-state read — the window the stale-index and
/// double-cancel races lived in.
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

/// IpfsService whose blockstore read parks until [gate] completes,
/// then yields a non-empty payload. Lets a test freeze a claim inside
/// the evidence phase — between the durable CAS win and the payout.
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
