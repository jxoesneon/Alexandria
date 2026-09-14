import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/agent/beacon_models.dart';
import 'package:alexandria/services/agent/escrow_attestation.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/poch_service.dart';
import 'package:alexandria/services/ipfs_service.dart';

/// IpfsService whose blockstore reads always fail — proves claimBounty
/// contains stream errors instead of propagating them (E-T5 #6).
class _ThrowingIpfsService extends IpfsService {
  _ThrowingIpfsService(super.ref);

  @override
  Stream<Uint8List> getFile(String cid) async* {
    throw StateError('blockstore read exploded');
  }
}

final _throwingIpfsProvider =
    Provider<IpfsService>((ref) => _ThrowingIpfsService(ref));

/// A fresh Ed25519 attestor identity — FOREIGN to every test poster.
Future<SimpleKeyPair> _newAttestor() => Ed25519().newKeyPair();

/// Builds a REAL, construction-verified [EscrowAttestation] — the
/// successor to the old caller-asserted `escrowAttested: true` bool.
/// The signature genuinely verifies over the canonical domain preimage,
/// so ingest sees cryptographic evidence, not a caller claim.
///
/// [signer] defaults to [attestor]; pass a different key to forge an
/// attestation that names [attestor] but is signed by someone else.
/// [verifyNow] overrides the construction-time clock so tests can mint
/// an attestation that is expired at real ingest time.
/// [attestorPubkeyOverride] rewrites the hex spelling the attestation
/// carries (e.g. UPPERCASE / space-padded) while [signer] still signs
/// with [attestor]'s real key — every decodable spelling verifies.
Future<EscrowAttestation?> _attestEscrow(
  SimpleKeyPair attestor, {
  required String bountyId,
  required String cid,
  required int amountMilli,
  int? expiresAt,
  SimpleKeyPair? signer,
  DateTime? verifyNow,
  String? attestorPubkeyOverride,
}) async {
  final exp = expiresAt ??
      DateTime.now()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch;
  final preimage = EscrowAttestation.signingPreimage(
    bountyId: bountyId,
    cid: cid,
    amountMilli: amountMilli,
    expiresAt: exp,
  );
  final sig = await Ed25519().sign(preimage, keyPair: signer ?? attestor);
  final pub = await attestor.extractPublicKey();
  return EscrowAttestation.verify(
    attestorPubkey: attestorPubkeyOverride ?? bytesToHex(pub.bytes),
    bountyId: bountyId,
    cid: cid,
    amountMilli: amountMilli,
    expiresAt: exp,
    signature: base64Encode(sig.bytes),
    verifyFn: EscrowAttestation.verifyEd25519,
    now: verifyNow,
  );
}

/// Convenience wrapper: attests [bounty]'s exact id/cid/amount.
Future<EscrowAttestation?> _attestBounty(
  SimpleKeyPair attestor,
  PreservationBounty bounty, {
  int? expiresAt,
  SimpleKeyPair? signer,
  DateTime? verifyNow,
  String? attestorPubkeyOverride,
}) =>
    _attestEscrow(
      attestor,
      bountyId: bounty.id,
      cid: bounty.cid,
      amountMilli: (bounty.offeredCredits * 1000).round(),
      expiresAt: expiresAt,
      signer: signer,
      verifyNow: verifyNow,
      attestorPubkeyOverride: attestorPubkeyOverride,
    );

/// Hex pubkey of [kp] — the value a `trustedAttestors` set must contain
/// for ingest to honor this attestor's attestation.
Future<String> _pubHex(SimpleKeyPair kp) async =>
    bytesToHex((await kp.extractPublicKey()).bytes);

/// Mints a fresh foreign attestor, attests [bounty], and returns the
/// construction-verified attestation plus the attestor's pubkey hex —
/// everything an `ingestBountyAnnouncement(..., trustedAttestors: {hex})`
/// call needs to admit a legitimately funded announcement.
Future<(EscrowAttestation?, String)> _freshTrustedAttestation(
  PreservationBounty bounty,
) async {
  final attestor = await _newAttestor();
  return (await _attestBounty(attestor, bounty), await _pubHex(attestor));
}

/// Builds a foreign (remotely-originated) funded bounty for ingestion.
PreservationBounty _foreignBounty({
  required String id,
  required String cid,
  double offeredCredits = 25.0,
  String urgency = 'normal',
  bool funded = true,
}) {
  return PreservationBounty(
    id: id,
    cid: cid,
    title: 'Foreign bounty $id',
    offeredCredits: offeredCredits,
    urgency: urgency,
    originAgentId: 'bcn_remote_poster',
    createdAt: DateTime.now(),
    funded: funded,
  );
}

void main() {
  group('MoltbookService Agent Social & Bounty Tests (ALX-006 §4)', () {
    late PoCHService pochService;
    late CreditService creditService;
    late MoltbookService moltbookService;

    setUp(() {
      pochService = PoCHService();
      creditService = CreditService(
        pochService: pochService,
        initialBalance: 100.0,
      );
      moltbookService = MoltbookService(creditService: creditService);
    });

    test('seeds initial posts and bounties in submolts', () {
      final bountiesPosts = moltbookService.getPostsForSubmolt('alexandria-bounties');
      final sciencePosts = moltbookService.getPostsForSubmolt('open-science');
      final alertPosts = moltbookService.getPostsForSubmolt('preservation-alerts');

      expect(bountiesPosts.isNotEmpty, isTrue);
      expect(sciencePosts.isNotEmpty, isTrue);
      expect(alertPosts.isNotEmpty, isTrue);

      expect(moltbookService.activeBounties.length, greaterThanOrEqualTo(2));
      expect(moltbookService.activeBounties.first.urgency, 'critical');
    });

    test('upvotes post and increments counter', () {
      final post = moltbookService.getPostsForSubmolt('open-science').first;
      final initialVotes = post.upvotes;

      final success = moltbookService.upvotePost(post.id);
      expect(success, isTrue);
      expect(post.upvotes, initialVotes + 1);
    });

    test('enforces local 30-minute posting guard against runaway loops', () async {
      // 1. First post succeeds
      final post1 = await moltbookService.createPost(
        submolt: 'open-science',
        title: 'First Discovery Post',
        content: 'Preserved dataset bundle',
      );
      expect(post1, isNotNull);

      // 2. Second immediate post without force throws StateError
      expect(
        () => moltbookService.createPost(
          submolt: 'open-science',
          title: 'Immediate Second Post',
          content: 'Should be rate-limited by local guard',
        ),
        throwsA(isA<StateError>()),
      );

      // 3. Post with force: true succeeds (emergency bypass)
      final post3 = await moltbookService.createPost(
        submolt: 'open-science',
        title: 'Emergency Critical Post',
        content: 'Bypassing local cooldown with force flag',
        force: true,
      );
      expect(post3, isNotNull);
    });

    test('posts preservation bounty, escrows credits, and records to submolt', () async {
      final initialBalance = creditService.balance; // 100.0
      final initialTreasury = creditService.protocolTreasury;

      final bounty = await moltbookService.postPreservationBounty(
        cid: 'bafk_rare_manuscript_42',
        doi: '10.1000/182',
        title: 'Rare 16th Century Astronomy Treatise',
        offeredCredits: 25.0,
        urgency: 'critical',
        force: true,
      );

      expect(bounty, isNotNull);
      expect(bounty.offeredCredits, 25.0);
      expect(bounty.funded, isTrue);
      expect(creditService.balance, initialBalance - 25.0); // Escrowed!
      // E-T5 #5: escrow is a fee-exempt hold — no treasury skim on posting.
      expect(creditService.protocolTreasury, initialTreasury);

      // Verify bounty listed in active bounties
      expect(moltbookService.activeBounties.any((b) => b.id == bounty.id), isTrue);

      // Verify post added to alexandria-bounties
      final posts = moltbookService.getPostsForSubmolt('alexandria-bounties');
      expect(posts.any((p) => p.title.contains('Rare 16th Century')), isTrue);
    });

    test('rejects bounty when credit balance is insufficient', () async {
      expect(
        () => moltbookService.postPreservationBounty(
          cid: 'bafk_expensive_dataset',
          title: 'Excessive Bounty',
          offeredCredits: 500.0, // Exceeds balance
          force: true,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects zero, negative, and non-finite bounty offers (E-T5 #4)', () async {
      for (final badOffer in <double>[0.0, -50.0, double.nan, double.infinity]) {
        await expectLater(
          () => moltbookService.postPreservationBounty(
            cid: 'bafk_bad_offer_$badOffer',
            title: 'Bad Bounty',
            offeredCredits: badOffer,
            force: true,
          ),
          throwsA(isA<ArgumentError>()),
        );
      }

      // Nothing was escrowed or recorded as funded.
      expect(creditService.balance, 100.0);
      expect(moltbookService.activeBounties.every((b) => !b.funded), isTrue);
    });

    test('rejects claims on unfunded seeded demo bounties (no escrow behind them)', () async {
      final seeded = moltbookService.activeBounties;
      expect(seeded.length, greaterThanOrEqualTo(2));
      expect(seeded.every((b) => !b.funded), isTrue);

      final initialBalance = creditService.balance;
      for (final bounty in seeded) {
        // Unfunded announcements stay listed but can never pay out.
        expect(await moltbookService.claimBounty(bounty.id), isFalse);
        expect(bounty.isClaimed, isFalse);
      }
      expect(creditService.balance, initialBalance);
    });

    test('claim of unknown bounty id fails', () async {
      expect(await moltbookService.claimBounty('bounty_does_not_exist'), isFalse);
    });

    test('locally posted funded bounty cannot be self-claimed', () async {
      final bounty = await moltbookService.postPreservationBounty(
        cid: 'bafk_own_bounty',
        title: 'Self Bounty',
        offeredCredits: 10.0,
        force: true,
      );
      expect(bounty.funded, isTrue);

      // Same identity as origin -> rejected.
      expect(await moltbookService.claimBounty(bounty.id), isFalse);
      expect(bounty.isClaimed, isFalse);
      expect(creditService.balance, 90.0); // Escrow stays held
    });

    test('key rotation cannot self-claim a locally posted bounty (E-T5 #2)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ipfsService = container.read(ipfsServiceProvider);
      final ipfsMoltbook = MoltbookService(
        creditService: creditService,
        ipfsService: ipfsService,
      );

      // Store the payload so even the work-evidence check would pass —
      // the ONLY thing stopping the claim must be the self-dealing guard.
      final cid = await ipfsService.addFile(Uint8List.fromList([1, 2, 3, 4]));
      final bounty = await ipfsMoltbook.postPreservationBounty(
        cid: cid,
        title: 'Own Escrowed Bounty',
        offeredCredits: 20.0,
        force: true,
      );
      expect(creditService.balance, 80.0);

      // The proven exploit: rotate identity so originAgentId != _agentId.
      await ipfsMoltbook.setKeyPair(await Ed25519().newKeyPair());
      expect(ipfsMoltbook.agentId, isNot(bounty.originAgentId));

      // Locally-posted ids are permanently barred regardless of identity.
      expect(await ipfsMoltbook.claimBounty(bounty.id), isFalse);
      expect(bounty.isClaimed, isFalse);
      expect(creditService.balance, 80.0); // No escrow payout, no mint
      expect(
        creditService.transactions
            .any((t) => t.description.contains('Bounty Escrow Payout')),
        isFalse,
      );
    });

    test('rejects funded foreign bounty claim when CID bytes are absent from blockstore', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ipfsService = container.read(ipfsServiceProvider);
      final ipfsMoltbook = MoltbookService(
        creditService: creditService,
        ipfsService: ipfsService,
      );

      final bounty = _foreignBounty(
        id: 'bounty_remote_unreplicated',
        cid: 'bafk_never_replicated',
        offeredCredits: 20.0,
      );
      // A real TRUSTED foreign attestation so the funded guard admits
      // the bounty — without it the claim would reject before the
      // blockstore check this test targets.
      final (att, attestorHex) = await _freshTrustedAttestation(bounty);
      ipfsMoltbook.ingestBountyAnnouncement(
        bounty,
        escrowAttestation: att,
        trustedAttestors: {attestorHex},
      );

      // No work evidence: CID bytes were never stored locally.
      expect(await ipfsMoltbook.claimBounty(bounty.id), isFalse);
      // The STORED copy (ingest never keeps the caller's object) is
      // still listed and unclaimed.
      expect(
        ipfsMoltbook.activeBounties
            .firstWhere((b) => b.id == bounty.id)
            .isClaimed,
        isFalse,
      );
      expect(creditService.balance, 100.0); // No payout
    });

    test('contains blockstore stream errors — claim returns false (E-T5 #6)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final throwingIpfs = container.read(_throwingIpfsProvider);
      final ipfsMoltbook = MoltbookService(
        creditService: creditService,
        ipfsService: throwingIpfs,
      );

      final bounty = _foreignBounty(
        id: 'bounty_remote_throwing',
        cid: 'bafk_throwing_store',
        offeredCredits: 20.0,
      );
      // Attested by a trusted foreign key so the claim reaches the
      // throwing getFile stream.
      final (att, attestorHex) = await _freshTrustedAttestation(bounty);
      ipfsMoltbook.ingestBountyAnnouncement(
        bounty,
        escrowAttestation: att,
        trustedAttestors: {attestorHex},
      );

      // getFile throws synchronously inside the stream — claim must
      // swallow it, release the claim mark, and report failure.
      expect(await ipfsMoltbook.claimBounty(bounty.id), isFalse);
      expect(
        ipfsMoltbook.activeBounties
            .firstWhere((b) => b.id == bounty.id)
            .isClaimed,
        isFalse,
      );
      expect(creditService.balance, 100.0);
    });

    test('funded claim after debitEscrow is net-zero: poster -X, claimant +X, treasury +0 (E-T5 #5)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ipfsService = container.read(ipfsServiceProvider);

      // Poster and claimant share the same ledger in this test so the
      // conservation invariant is directly observable on one balance.
      final poster = MoltbookService(creditService: creditService);
      final claimant = MoltbookService(
        creditService: creditService,
        ipfsService: ipfsService,
      );
      // Deterministic identities so the bounty is foreign to the claimant.
      await poster.setKeyPair(await Ed25519().newKeyPair());
      await claimant.setKeyPair(await Ed25519().newKeyPair());

      // Work evidence already replicated by the claimant.
      final cid = await ipfsService.addFile(Uint8List.fromList([1, 2, 3, 4]));
      final treasuryBefore = creditService.protocolTreasury;

      final bounty = await poster.postPreservationBounty(
        cid: cid,
        title: 'Net-Zero Conservation Bounty',
        offeredCredits: 25.0,
        urgency: 'critical',
        force: true,
      );
      expect(creditService.balance, 75.0); // Poster -25 (escrow hold)
      expect(creditService.protocolTreasury, treasuryBefore); // +0 fee

      // The announcement propagates over the transport to the claimant,
      // whose transport layer verified a TRUSTED foreign attestor's
      // signed escrow attestation.
      final (att, attestorHex) = await _freshTrustedAttestation(bounty);
      claimant.ingestBountyAnnouncement(
        bounty,
        escrowAttestation: att,
        trustedAttestors: {attestorHex},
      );
      expect(await claimant.claimBounty(bounty.id), isTrue);
      // Ingest stores a copy, so the claim flag lives on the stored
      // record — a claimed bounty drops out of activeBounties.
      expect(
        claimant.activeBounties.any((b) => b.id == bounty.id),
        isFalse,
      );

      // Claimant +25: escrow paid out in full, treasury untouched —
      // the whole post+claim cycle minted nothing.
      expect(creditService.balance, 100.0);
      expect(creditService.protocolTreasury, treasuryBefore);
      expect(
        creditService.transactions
            .any((t) => t.description.contains('treasury fee')),
        isFalse,
      );
    });

    test('concurrent double-claim yields exactly one success (E-T5 #1)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ipfsService = container.read(ipfsServiceProvider);
      final ipfsMoltbook = MoltbookService(
        creditService: creditService,
        ipfsService: ipfsService,
      );

      final cid = await ipfsService.addFile(Uint8List.fromList([5, 6, 7, 8]));
      final bounty = _foreignBounty(
        id: 'bounty_remote_race',
        cid: cid,
        offeredCredits: 25.0,
      );
      final (att, attestorHex) = await _freshTrustedAttestation(bounty);
      ipfsMoltbook.ingestBountyAnnouncement(
        bounty,
        escrowAttestation: att,
        trustedAttestors: {attestorHex},
      );

      // Two overlapping claims: the synchronous claim mark must make the
      // second call observe isClaimed before its first await.
      final results = await Future.wait([
        ipfsMoltbook.claimBounty(bounty.id),
        ipfsMoltbook.claimBounty(bounty.id),
      ]);

      expect(results.where((r) => r).length, 1);
      // The stored copy is claimed (dropped from activeBounties).
      expect(
        ipfsMoltbook.activeBounties.any((b) => b.id == bounty.id),
        isFalse,
      );
      expect(creditService.balance, 125.0); // Exactly one +25 payout
      expect(
        creditService.transactions
            .where((t) => t.description.contains('Bounty Escrow Payout'))
            .length,
        1,
      );
    });

    test('claims funded foreign bounty and pays escrow when CID bytes exist locally', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ipfsService = container.read(ipfsServiceProvider);
      final ipfsMoltbook = MoltbookService(
        creditService: creditService,
        ipfsService: ipfsService,
      );

      // Work evidence: the endangered document was replicated into the
      // local blockstore before claiming.
      final cid = await ipfsService.addFile(Uint8List.fromList([1, 2, 3, 4]));

      final bounty = _foreignBounty(
        id: 'bounty_remote_replicated',
        cid: cid,
        offeredCredits: 25.0,
      );
      final (att, attestorHex) = await _freshTrustedAttestation(bounty);
      ipfsMoltbook.ingestBountyAnnouncement(
        bounty,
        escrowAttestation: att,
        trustedAttestors: {attestorHex},
      );

      final success = await ipfsMoltbook.claimBounty(bounty.id);
      expect(success, isTrue);
      // The stored copy carries the claim flag — the caller's object
      // is never aliased into the registry (H3).
      expect(bounty.isClaimed, isFalse);
      expect(
        ipfsMoltbook.activeBounties.any((b) => b.id == bounty.id),
        isFalse,
      );
      expect(creditService.balance, 125.0); // +25 escrow payout

      // Attempting to claim already claimed bounty fails
      expect(await ipfsMoltbook.claimBounty(bounty.id), isFalse);
      expect(creditService.balance, 125.0);
    });

    test('forged remote funded flag mints nothing — unattested announcements are display-only (E-T5r #1)', () async {
      // Attacker announces funded:true with an arbitrary origin id and a
      // huge offer. There is NO escrow behind this — the flag is a bare
      // claim on the wire and must be stripped on ingest.
      final forged = _foreignBounty(
        id: 'bounty_forged_funded',
        cid: 'bafk_forged_escrow',
        offeredCredits: 9999.0,
        funded: true,
      );
      moltbookService.ingestBountyAnnouncement(forged); // no attestation

      // Ingested, but stored display-only.
      final stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == forged.id);
      expect(stored.funded, isFalse);

      // Claim must fail and mint nothing — no IpfsService needed for the
      // funded guard to reject it.
      expect(await moltbookService.claimBounty(forged.id), isFalse);
      expect(creditService.balance, 100.0);
      expect(
        creditService.transactions
            .any((t) => t.description.contains('Bounty Escrow Payout')),
        isFalse,
      );
    });

    test('forged funded announcement + replicated CID still mints nothing without attestation (E-T5r #1)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ipfsService = container.read(ipfsServiceProvider);
      final ipfsMoltbook = MoltbookService(
        creditService: creditService,
        ipfsService: ipfsService,
      );

      // Attacker pre-stages the bytes so even the work-evidence check
      // would pass — the ONLY thing stopping the mint must be the
      // missing escrow attestation.
      final cid = await ipfsService.addFile(Uint8List.fromList([1, 2, 3, 4]));
      ipfsMoltbook.ingestBountyAnnouncement(_foreignBounty(
        id: 'bounty_forged_ipfs',
        cid: cid,
        offeredCredits: 500.0,
      ));

      expect(await ipfsMoltbook.claimBounty('bounty_forged_ipfs'), isFalse);
      expect(creditService.balance, 100.0);
      expect(
        creditService.transactions
            .any((t) => t.description.contains('Bounty Escrow Payout')),
        isFalse,
      );
    });

    test('forged attestation signature verifies to null — funded stripped (ALX-011 A3)', () async {
      final bounty = _foreignBounty(
        id: 'bounty_forged_sig',
        cid: 'bafk_forged_sig',
        offeredCredits: 500.0,
      );
      // Attacker claims a foreign attestor's pubkey but signs with its
      // OWN key — the signature cannot verify against the claimed
      // attestor, so verify() must refuse to construct the attestation.
      final claimedAttestor = await _newAttestor();
      final attackerKey = await _newAttestor();
      final forged = await _attestBounty(
        claimedAttestor,
        bounty,
        signer: attackerKey,
      );
      expect(forged, isNull);

      moltbookService.ingestBountyAnnouncement(
        bounty,
        escrowAttestation: forged,
      );
      final stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == bounty.id);
      expect(stored.funded, isFalse);
      expect(await moltbookService.claimBounty(bounty.id), isFalse);
      expect(creditService.balance, 100.0);
    });

    test('malformed attestation inputs verify to null (ALX-011 A3)', () async {
      final attestor = await _newAttestor();
      final pub = await attestor.extractPublicKey();
      final pubHex = bytesToHex(pub.bytes);
      final exp = DateTime.now()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch;

      // Garbage base64, wrong-length signature, and a signature over a
      // DIFFERENT preimage all fail closed.
      for (final badSig in <String>[
        'not-base64!!!',
        base64Encode(Uint8List(32)), // 32 bytes, not 64
        base64Encode(Uint8List(64)), // well-formed but never signed
      ]) {
        expect(
          await EscrowAttestation.verify(
            attestorPubkey: pubHex,
            bountyId: 'bounty_x',
            cid: 'bafk_x',
            amountMilli: 25000,
            expiresAt: exp,
            signature: badSig,
            verifyFn: EscrowAttestation.verifyEd25519,
          ),
          isNull,
        );
      }
    });

    test('valid attestation bound to a DIFFERENT bounty strips funded (ALX-011 A3)', () async {
      final attestor = await _newAttestor();
      // Attestation minted for bounty A...
      final attestation = await _attestEscrow(
        attestor,
        bountyId: 'bounty_A',
        cid: 'bafk_A',
        amountMilli: 25000,
      );
      expect(attestation, isNotNull);

      // ...cannot vouch for bounty B (different id → no binding) — even
      // though the attestor IS in the trusted set, so the binding check
      // is the only thing rejecting it.
      final bountyB = _foreignBounty(
        id: 'bounty_B',
        cid: 'bafk_A',
        offeredCredits: 25.0,
      );
      moltbookService.ingestBountyAnnouncement(
        bountyB,
        escrowAttestation: attestation,
        trustedAttestors: {await _pubHex(attestor)},
      );
      final stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == 'bounty_B');
      expect(stored.funded, isFalse);
      expect(await moltbookService.claimBounty('bounty_B'), isFalse);
      expect(creditService.balance, 100.0);
    });

    test('expired attestation strips funded — dead on arrival and at ingest (ALX-011 A3)', () async {
      final attestor = await _newAttestor();
      final bounty = _foreignBounty(
        id: 'bounty_expired',
        cid: 'bafk_expired',
        offeredCredits: 25.0,
      );

      // 1. An attestation whose expiry is already past cannot even be
      //    constructed (verify fails closed).
      final pastExp =
          DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
      expect(
        await _attestBounty(attestor, bounty, expiresAt: pastExp),
        isNull,
      );

      // 2. An attestation honestly minted while valid but ingested
      //    AFTER expiry is still stripped: mint it with a verify-time
      //    clock before expiry, then let real "now" be past it.
      final expired = await _attestBounty(
        attestor,
        bounty,
        expiresAt: pastExp,
        verifyNow: DateTime.fromMillisecondsSinceEpoch(pastExp - 1000),
      );
      expect(expired, isNotNull);
      expect(expired!.isExpired(), isTrue);

      // Trusted attestor — only expiry strips funded.
      moltbookService.ingestBountyAnnouncement(
        bounty,
        escrowAttestation: expired,
        trustedAttestors: {await _pubHex(attestor)},
      );
      final stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == bounty.id);
      expect(stored.funded, isFalse);
      expect(await moltbookService.claimBounty(bounty.id), isFalse);
      expect(creditService.balance, 100.0);
    });

    test('valid foreign attestation preserves funded on ingest ONLY when the attestor is trusted (ALX-011 A3)', () async {
      final bounty = _foreignBounty(
        id: 'bounty_attested',
        cid: 'bafk_attested',
        offeredCredits: 25.0,
      );
      final attestor = await _newAttestor();
      final attestation = await _attestBounty(attestor, bounty);
      expect(attestation, isNotNull);
      expect(attestation!.bindsBounty(bounty), isTrue);
      expect(attestation.isExpired(), isFalse);
      expect(attestation.isSelfIssuedFor(bounty), isFalse);

      moltbookService.ingestBountyAnnouncement(
        bounty,
        escrowAttestation: attestation,
        trustedAttestors: {await _pubHex(attestor)},
      );
      final stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == bounty.id);
      expect(stored.funded, isTrue);
    });

    test('self-issued attestation from the POSTER key strips funded (ALX-011 A3)', () async {
      // Attestation means a FOREIGN party vouched — a poster signing its
      // own escrow claim is the same self-declaration as the `funded`
      // flag. Mirror of WorkReceipt.isSelfIssued.
      final posterKp = await Ed25519().newKeyPair();
      final posterPub = await posterKp.extractPublicKey();
      final bounty = PreservationBounty(
        id: 'bounty_self_vouched',
        cid: 'bafk_self_attested',
        title: 'Self-Vouched Bounty',
        offeredCredits: 20.0,
        originAgentId: BeaconEnvelope.deriveAgentId(posterPub.bytes),
        createdAt: DateTime.now(),
        funded: true,
      );

      // The poster's OWN key attests — cryptographically valid, bound to
      // the bounty, trusted by the set, but self-issued, so it carries
      // zero weight.
      final selfVouch = await _attestBounty(posterKp, bounty);
      expect(selfVouch, isNotNull);
      expect(selfVouch!.isSelfIssuedFor(bounty), isTrue);
      expect(selfVouch.bindsBounty(bounty), isTrue);

      moltbookService.ingestBountyAnnouncement(
        bounty,
        escrowAttestation: selfVouch,
        trustedAttestors: {await _pubHex(posterKp)},
      );
      final stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == bounty.id);
      expect(stored.funded, isFalse);
      expect(await moltbookService.claimBounty(bounty.id), isFalse);
      expect(creditService.balance, 100.0);
    });

    test('Sybil attestor: cryptographically VALID attestation from an untrusted key strips funded (F1)', () async {
      // The proven exploit: attacker mints its own keypair, signs a
      // perfectly valid attestation, and claims escrow that does not
      // exist. Signature validity is proof of key possession, not
      // trust — the trustedAttestors set is the only trust root.
      final bounty = _foreignBounty(
        id: 'bounty_sybil_attestor',
        cid: 'bafk_sybil_escrow',
        offeredCredits: 500.0,
      );
      final sybil = await _newAttestor();
      final forgedButValid = await _attestBounty(sybil, bounty);
      expect(forgedButValid, isNotNull); // really did verify

      // 1. Default empty trust set: fail-closed.
      moltbookService.ingestBountyAnnouncement(
        bounty,
        escrowAttestation: forgedButValid,
      );
      var stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == bounty.id);
      expect(stored.funded, isFalse);

      // 2. A trust set containing a DIFFERENT (honest) key still
      //    rejects the sybil attestor.
      final fresh = MoltbookService(creditService: creditService);
      fresh.ingestBountyAnnouncement(
        bounty,
        escrowAttestation: forgedButValid,
        trustedAttestors: {await _pubHex(await _newAttestor())},
      );
      stored =
          fresh.activeBounties.firstWhere((b) => b.id == bounty.id);
      expect(stored.funded, isFalse);

      expect(await moltbookService.claimBounty(bounty.id), isFalse);
      expect(creditService.balance, 100.0);
    });

    test('LOCAL node key can never attest — rejected even when in the trusted set (F1)', () async {
      // Second proven exploit: self-attestation via the node's OWN
      // key. isSelfIssuedFor only compares the attestor against the
      // bounty's CLAIMED originAgentId — it cannot catch the local
      // key vouching for a foreign-origin bounty. The local-key bar
      // keys off the real keypair (_pubkeyHex), not the claimed id.
      final localKp = await Ed25519().newKeyPair();
      await moltbookService.setKeyPair(localKp);
      final localHex = await _pubHex(localKp);
      expect(moltbookService.pubkeyHex, localHex);

      final bounty = _foreignBounty(
        id: 'bounty_local_attested',
        cid: 'bafk_local_escrow',
        offeredCredits: 1000.0,
      );
      final selfAttested = await _attestBounty(localKp, bounty);
      expect(selfAttested, isNotNull);
      expect(selfAttested!.bindsBounty(bounty), isTrue);
      // Not self-issued w.r.t. the poster — the foreign originAgentId
      // differs from the local agent id, so ONLY the local-key check
      // can catch this.
      expect(selfAttested.isSelfIssuedFor(bounty), isFalse);

      moltbookService.ingestBountyAnnouncement(
        bounty,
        escrowAttestation: selfAttested,
        trustedAttestors: {localHex}, // trusted, but it is OUR key
      );
      final stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == bounty.id);
      expect(stored.funded, isFalse);
      expect(await moltbookService.claimBounty(bounty.id), isFalse);
      expect(creditService.balance, 100.0);
    });

    test('v2 preimage is injective: colon-splicing cannot move a signature across field boundaries (F2)', () async {
      // The v1 exploit: 'x:y' + ':' + 'z' == 'x' + ':' + 'y:z', so one
      // signature covered two different (bountyId, cid) tuples.
      final p1 = EscrowAttestation.signingPreimage(
        bountyId: 'x:y',
        cid: 'z',
        amountMilli: 25000,
        expiresAt: 999,
      );
      final p2 = EscrowAttestation.signingPreimage(
        bountyId: 'x',
        cid: 'y:z',
        amountMilli: 25000,
        expiresAt: 999,
      );
      expect(p1, isNot(equals(p2)));

      // And at the crypto layer: a signature minted for the spliced
      // tuple can never re-verify against the shifted tuple.
      final attestor = await _newAttestor();
      final attestorHex = await _pubHex(attestor);
      final exp = DateTime.now()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch;
      final sig = await Ed25519().sign(
        EscrowAttestation.signingPreimage(
          bountyId: 'bounty_x:y',
          cid: 'bafk_z',
          amountMilli: 25000,
          expiresAt: exp,
        ),
        keyPair: attestor,
      );
      expect(
        await EscrowAttestation.verify(
          attestorPubkey: attestorHex,
          bountyId: 'bounty_x',
          cid: 'y:bafk_z',
          amountMilli: 25000,
          expiresAt: exp,
          signature: base64Encode(sig.bytes),
          verifyFn: EscrowAttestation.verifyEd25519,
        ),
        isNull,
      );
    });

    test('verify() rejects amountMilli outside 1..2^53 (F3)', () async {
      final attestor = await _newAttestor();
      final attestorHex = await _pubHex(attestor);
      final exp = DateTime.now()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch;
      for (final bad in <int>[0, -1, 9007199254740993]) {
        final sig = await Ed25519().sign(
          EscrowAttestation.signingPreimage(
            bountyId: 'bounty_bound',
            cid: 'bafk_bound',
            amountMilli: bad,
            expiresAt: exp,
          ),
          keyPair: attestor,
        );
        expect(
          await EscrowAttestation.verify(
            attestorPubkey: attestorHex,
            bountyId: 'bounty_bound',
            cid: 'bafk_bound',
            amountMilli: bad,
            expiresAt: exp,
            signature: base64Encode(sig.bytes),
            verifyFn: EscrowAttestation.verifyEd25519,
          ),
          isNull,
        );
      }
    });

    test('non-finite offeredCredits never throws and never funds (F3)', () async {
      // (NaN * 1000).round() throws — bindsBounty must guard isFinite
      // BEFORE the conversion so a malformed announcement fails closed
      // instead of crashing ingest.
      for (final bad in <double>[double.nan, double.infinity]) {
        final bounty = _foreignBounty(
          id: 'bounty_nonfinite_$bad',
          cid: 'bafk_nonfinite',
          offeredCredits: bad,
        );
        // A trusted, well-formed attestation (minted for a finite
        // amount — a NaN amount cannot even be expressed in
        // amountMilli): binding must evaluate to false, not throw.
        final attestor = await _newAttestor();
        final att = await _attestEscrow(
          attestor,
          bountyId: bounty.id,
          cid: bounty.cid,
          amountMilli: 25000,
        );
        final attestorHex = await _pubHex(attestor);
        expect(
          () => moltbookService.ingestBountyAnnouncement(
            bounty,
            escrowAttestation: att,
            trustedAttestors: {attestorHex},
          ),
          returnsNormally,
        );
        final stored = moltbookService.activeBounties
            .firstWhere((b) => b.id == bounty.id);
        expect(stored.funded, isFalse);
      }
      expect(creditService.balance, 100.0);
    });

    test('dedup upgrade: poisoned id is revived by a later TRUSTED attestation binding the stored record (F4)', () async {
      // 1. Attacker poisons the id first: funded:true, no attestation.
      moltbookService.ingestBountyAnnouncement(_foreignBounty(
        id: 'bounty_poisoned',
        cid: 'bafk_real_doc',
        offeredCredits: 25.0,
      ));
      var stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == 'bounty_poisoned');
      expect(stored.funded, isFalse);

      // 2. The legit re-announcement arrives carrying a trusted
      //    attestation binding the STORED record's id/cid/amount —
      //    plus decoy fields that must NOT be adopted.
      final (att, attestorHex) = await _freshTrustedAttestation(stored);
      moltbookService.ingestBountyAnnouncement(
        PreservationBounty(
          id: 'bounty_poisoned',
          cid: 'bafk_real_doc',
          title: 'DECOY TITLE — must not be adopted',
          offeredCredits: 25.0,
          urgency: 'critical',
          originAgentId: 'bcn_remote_poster',
          createdAt: DateTime.now(),
          funded: true,
        ),
        escrowAttestation: att,
        trustedAttestors: {attestorHex},
      );

      stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == 'bounty_poisoned');
      expect(stored.funded, isTrue);
      // Stored record fields are untouched — only funded flipped.
      expect(stored.title, 'Foreign bounty bounty_poisoned');
      expect(stored.urgency, 'normal');
      expect(stored.offeredCredits, 25.0);
    });

    test('dedup upgrade: forged/untrusted attestation cannot revive a poisoned id (F4)', () async {
      moltbookService.ingestBountyAnnouncement(_foreignBounty(
        id: 'bounty_poisoned2',
        cid: 'bafk_real_doc2',
        offeredCredits: 25.0,
      ));

      // Valid signature, valid binding — but the attestor is NOT in
      // the trusted set (the Sybil case again, via the upgrade path).
      final sybil = await _newAttestor();
      final stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == 'bounty_poisoned2');
      final forgedButValid = await _attestBounty(sybil, stored);
      expect(forgedButValid, isNotNull);

      moltbookService.ingestBountyAnnouncement(
        _foreignBounty(
          id: 'bounty_poisoned2',
          cid: 'bafk_real_doc2',
          offeredCredits: 25.0,
        ),
        escrowAttestation: forgedButValid,
        // Attestor absent from the trust root → no upgrade.
      );
      final after = moltbookService.activeBounties
          .firstWhere((b) => b.id == 'bounty_poisoned2');
      expect(after.funded, isFalse);
      expect(await moltbookService.claimBounty('bounty_poisoned2'), isFalse);
      expect(creditService.balance, 100.0);
    });

    test('dedup upgrade: an already-FUNDED record is immutable (F4)', () async {
      final bounty = _foreignBounty(
        id: 'bounty_funded_first',
        cid: 'bafk_funded_first',
        offeredCredits: 25.0,
      );
      final (att, attestorHex) = await _freshTrustedAttestation(bounty);
      moltbookService.ingestBountyAnnouncement(
        bounty,
        escrowAttestation: att,
        trustedAttestors: {attestorHex},
      );
      final stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == bounty.id);
      expect(stored.funded, isTrue);

      // A later announcement — even one carrying another valid trusted
      // attestation — changes nothing about the funded record.
      final (att2, hex2) = await _freshTrustedAttestation(bounty);
      moltbookService.ingestBountyAnnouncement(
        PreservationBounty(
          id: bounty.id,
          cid: 'bafk_DIFFERENT_cid',
          title: 'MUTATION ATTEMPT',
          offeredCredits: 9999.0,
          originAgentId: 'bcn_remote_poster',
          createdAt: DateTime.now(),
          funded: false,
        ),
        escrowAttestation: att2,
        trustedAttestors: {hex2},
      );
      final after = moltbookService.activeBounties
          .firstWhere((b) => b.id == bounty.id);
      expect(after.funded, isTrue);
      expect(after.cid, 'bafk_funded_first');
      expect(after.title, 'Foreign bounty bounty_funded_first');
      expect(after.offeredCredits, 25.0);
      expect(identical(after, stored), isTrue);
    });

    test('broadcast failure leaves escrow untouched and records no bounty (E-T5r #2)', () async {
      // Arm the posting cooldown so createPost throws inside the bounty
      // flow (no force flag).
      await moltbookService.createPost(
        submolt: 'open-science',
        title: 'Cooldown-Arming Post',
        content: 'Sets lastPostTime',
      );

      await expectLater(
        moltbookService.postPreservationBounty(
          cid: 'bafk_cooldown_leak',
          title: 'Cooldown Leak Bounty',
          offeredCredits: 30.0,
        ),
        throwsA(isA<StateError>()),
      );

      // Broadcast-first ordering: the throw happened BEFORE any ledger
      // touch — no escrow was debited and no unclaimable funded bounty
      // lingers in the registry.
      expect(creditService.balance, 100.0);
      expect(
        moltbookService.activeBounties
            .any((b) => b.cid == 'bafk_cooldown_leak'),
        isFalse,
      );
      expect(moltbookService.activeBounties.every((b) => !b.funded), isTrue);
    });

    test('local-key bar is canonical: non-canonical spellings of OUR pubkey still cannot attest (H1)', () async {
      // The exploit: the node attests with its OWN key, but the
      // attestation carries a non-canonical spelling of the local pubkey
      // (UPPERCASE / space-padded — all decode to identical bytes). A
      // raw `attestorPubkey != _pubkeyHex` compare would see "different"
      // keys and admit the local self-attestation.
      final localKp = await Ed25519().newKeyPair();
      await moltbookService.setKeyPair(localKp);
      final localHex = await _pubHex(localKp);
      expect(moltbookService.pubkeyHex, localHex);

      final bounty = _foreignBounty(
        id: 'bounty_local_alias',
        cid: 'bafk_local_alias',
        offeredCredits: 1000.0,
      );
      for (final spelling in <String>[
        localHex.toUpperCase(),
        '  $localHex  ', // surrounding whitespace
        localHex.replaceRange(10, 10, ' '), // interior space, same bytes
      ]) {
        // Fresh service per spelling so each ingest is first-seen.
        final fresh = MoltbookService(creditService: creditService);
        await fresh.setKeyPair(localKp);
        // verify() accepts every decodable spelling — the signature is
        // genuinely valid, so ONLY the canonical local-key bar can
        // reject this attestation.
        final att = await _attestBounty(
          localKp,
          bounty,
          attestorPubkeyOverride: spelling,
        );
        expect(att, isNotNull);
        expect(att!.bindsBounty(bounty), isTrue);
        expect(att.isSelfIssuedFor(bounty), isFalse);

        fresh.ingestBountyAnnouncement(
          bounty,
          escrowAttestation: att,
          trustedAttestors: {spelling}, // "trusted" under the same alias
        );
        final stored = fresh.activeBounties
            .firstWhere((b) => b.id == bounty.id);
        expect(stored.funded, isFalse);
        expect(await fresh.claimBounty(bounty.id), isFalse);
      }
      expect(creditService.balance, 100.0);
    });

    test('trusted-set membership is canonical: non-canonical spelling of a TRUSTED foreign key still admits (H1)', () async {
      // The other half of the encoding bug: a configured trust root may
      // spell keys uppercase or padded — membership must compare decoded
      // key bytes, not strings, or legit attestations are dropped.
      final attestor = await _newAttestor();
      final attestorHex = await _pubHex(attestor);
      var n = 0;
      for (final spelling in <String>[
        attestorHex.toUpperCase(),
        ' $attestorHex ',
      ]) {
        n++;
        final bounty = _foreignBounty(
          id: 'bounty_trusted_alias_$n',
          cid: 'bafk_trusted_alias_$n',
          offeredCredits: 25.0,
        );
        // Attestation carries the canonical lowercase spelling; only
        // the trusted set's entry is non-canonical.
        final att = await _attestBounty(attestor, bounty);
        expect(att, isNotNull);

        final fresh = MoltbookService(creditService: creditService);
        fresh.ingestBountyAnnouncement(
          bounty,
          escrowAttestation: att,
          trustedAttestors: {spelling},
        );
        final stored = fresh.activeBounties
            .firstWhere((b) => b.id == bounty.id);
        expect(stored.funded, isTrue);
      }
    });

    test('overflow offeredCredits (milli product → Infinity) never throws and never funds — both ingest paths (H2)', () async {
      // 1e306 is finite, but 1e306 * 1000 overflows to Infinity and
      // Infinity.round() throws — the old guard only checked
      // offeredCredits.isFinite, so bindsBounty crashed ingest.
      const overflow = 1e306;

      // Path 1 — first-seen ingest with a trusted, well-formed
      // attestation: binding must evaluate to false, not throw.
      final bounty = _foreignBounty(
        id: 'bounty_overflow',
        cid: 'bafk_overflow',
        offeredCredits: overflow,
      );
      final attestor = await _newAttestor();
      final att = await _attestEscrow(
        attestor,
        bountyId: bounty.id,
        cid: bounty.cid,
        amountMilli: 25000,
      );
      final attestorHex = await _pubHex(attestor);
      expect(att, isNotNull);
      expect(
        () => moltbookService.ingestBountyAnnouncement(
          bounty,
          escrowAttestation: att,
          trustedAttestors: {attestorHex},
        ),
        returnsNormally,
      );
      var stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == bounty.id);
      expect(stored.funded, isFalse);

      // Path 2 — dedup upgrade on the same poisoned id. The old code
      // threw INSIDE the upgrade check too, so an attested
      // re-announcement of a poisoned overflow id was a persistent
      // crash primitive.
      expect(
        () => moltbookService.ingestBountyAnnouncement(
          _foreignBounty(
            id: 'bounty_overflow',
            cid: 'bafk_overflow',
            offeredCredits: overflow,
          ),
          escrowAttestation: att,
          trustedAttestors: {attestorHex},
        ),
        returnsNormally,
      );
      stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == bounty.id);
      expect(stored.funded, isFalse);
      expect(creditService.balance, 100.0);
    });

    test('wire is_claimed is sanitized on ingest — funded + claimed:true stays claimable (H3)', () async {
      // Attack: an attested funded announcement that ALSO carries
      // is_claimed:true. If the wire flag were stored, the escrow would
      // be funded-but-permanently-unclaimable (and invisible to
      // activeBounties). Built through fromJson — the real wire path.
      final wireJson = _foreignBounty(
        id: 'bounty_wire_claimed',
        cid: 'bafk_wire_claimed',
        offeredCredits: 25.0,
      ).toJson()
        ..['is_claimed'] = true;
      final bounty = PreservationBounty.fromJson(wireJson);
      expect(bounty.isClaimed, isTrue); // the injected wire flag

      final (att, attestorHex) = await _freshTrustedAttestation(bounty);
      moltbookService.ingestBountyAnnouncement(
        bounty,
        escrowAttestation: att,
        trustedAttestors: {attestorHex},
      );

      // Sanitized: the stored record is funded AND unclaimed.
      final stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == bounty.id);
      expect(stored.funded, isTrue);
      expect(stored.isClaimed, isFalse);

      // Genuinely claimable — the escrow is not dead-locked (no
      // IpfsService → work-evidence check skipped).
      expect(await moltbookService.claimBounty(bounty.id), isTrue);
      expect(creditService.balance, 125.0);
    });

    test('post-ingest mutation of the caller object cannot touch the stored record (H3)', () async {
      // The funded fast-path used to store the caller's object verbatim
      // when funded == bounty.funded — mutating the caller's object
      // afterwards flipped the stored record's claim state.
      final bounty = _foreignBounty(
        id: 'bounty_aliased',
        cid: 'bafk_aliased',
        offeredCredits: 25.0,
      );
      final (att, attestorHex) = await _freshTrustedAttestation(bounty);
      moltbookService.ingestBountyAnnouncement(
        bounty,
        escrowAttestation: att,
        trustedAttestors: {attestorHex},
      );

      // Caller retains and mutates the same object post-ingest.
      bounty.isClaimed = true;

      final stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == bounty.id);
      expect(identical(stored, bounty), isFalse);
      expect(stored.funded, isTrue);
      expect(stored.isClaimed, isFalse);
      expect(await moltbookService.claimBounty(bounty.id), isTrue);
    });

    test('dedup upgrade sanitizes a wire-claimed stored record (H3)', () async {
      // The stored record must never carry a wire-claimed isClaimed,
      // including through the upgrade path.
      final poison = PreservationBounty.fromJson(_foreignBounty(
        id: 'bounty_upgrade_claimed',
        cid: 'bafk_upgrade_claimed',
        offeredCredits: 25.0,
        funded: false,
      ).toJson()
        ..['is_claimed'] = true);
      moltbookService.ingestBountyAnnouncement(poison);
      var stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == 'bounty_upgrade_claimed');
      expect(stored.funded, isFalse);
      expect(stored.isClaimed, isFalse); // sanitized at first ingest

      // Same-origin trusted upgrade still lands on the sanitized copy.
      final (att, attestorHex) = await _freshTrustedAttestation(stored);
      moltbookService.ingestBountyAnnouncement(
        _foreignBounty(
          id: 'bounty_upgrade_claimed',
          cid: 'bafk_upgrade_claimed',
          offeredCredits: 25.0,
        ),
        escrowAttestation: att,
        trustedAttestors: {attestorHex},
      );
      stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == 'bounty_upgrade_claimed');
      expect(stored.funded, isTrue);
      expect(stored.isClaimed, isFalse);
      expect(await moltbookService.claimBounty(stored.id), isTrue);
    });

    test('dedup upgrade: origin-poisoned record cannot brand a foreign attestation self-issued (H4)', () async {
      // Front-runner poisons the id with originAgentId = the trusted
      // attestor's derived id, hoping the later legit re-announcement
      // is rejected as "self-issued". With the origin-match gate the
      // legit re-announcement (claiming the REAL poster) no longer
      // mislabels the attestation — it is a CONFLICT: different claimed
      // poster for the same bounty id → no upgrade, stored record
      // untouched (fail-closed, same denial a wrong-cid poison gives).
      final attestor = await _newAttestor();
      final attestorHex = await _pubHex(attestor);
      final attestorAgentId =
          BeaconEnvelope.deriveAgentId(hexToBytes(attestorHex));

      moltbookService.ingestBountyAnnouncement(PreservationBounty(
        id: 'bounty_origin_poison',
        cid: 'bafk_origin_poison',
        title: 'Front-run poison with attestor origin',
        offeredCredits: 25.0,
        originAgentId: attestorAgentId, // attacker-chosen poison
        createdAt: DateTime.now(),
        funded: true, // stripped — no attestation
      ));
      var stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == 'bounty_origin_poison');
      expect(stored.funded, isFalse);

      // Legit re-announcement claims the real poster and carries a
      // valid trusted attestation binding the stored id/cid/amount.
      final att = await _attestEscrow(
        attestor,
        bountyId: stored.id,
        cid: stored.cid,
        amountMilli: (stored.offeredCredits * 1000).round(),
      );
      moltbookService.ingestBountyAnnouncement(
        _foreignBounty(
          id: 'bounty_origin_poison',
          cid: 'bafk_origin_poison',
          offeredCredits: 25.0,
        ), // originAgentId 'bcn_remote_poster' ≠ stored's poisoned claim
        escrowAttestation: att,
        trustedAttestors: {attestorHex},
      );
      stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == 'bounty_origin_poison');
      expect(stored.funded, isFalse);
      expect(stored.originAgentId, attestorAgentId); // never adopted
      expect(await moltbookService.claimBounty(stored.id), isFalse);
      expect(creditService.balance, 100.0);
    });

    test('dedup upgrade: re-announcement claiming the ATTESTOR as poster is a self-vouch — no upgrade (H4)', () async {
      // Mirror case: stored poison claims the real poster, and a later
      // announcement re-claims the ATTESTOR's own id as origin while
      // presenting that attestor's (valid, trusted) attestation. Under
      // the old rule the stored origin made the check pass; under the
      // origin-match gate the mismatched claim is a conflict — and even
      // evaluated on its own terms, "attestor == claimed poster" is
      // self-issued. Either way: no upgrade.
      final attestor = await _newAttestor();
      final attestorHex = await _pubHex(attestor);
      final attestorAgentId =
          BeaconEnvelope.deriveAgentId(hexToBytes(attestorHex));

      moltbookService.ingestBountyAnnouncement(_foreignBounty(
        id: 'bounty_selfvouch_upgrade',
        cid: 'bafk_selfvouch_upgrade',
        offeredCredits: 25.0,
      )); // stored origin: 'bcn_remote_poster'
      var stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == 'bounty_selfvouch_upgrade');
      expect(stored.funded, isFalse);

      final att = await _attestEscrow(
        attestor,
        bountyId: stored.id,
        cid: stored.cid,
        amountMilli: (stored.offeredCredits * 1000).round(),
      );
      moltbookService.ingestBountyAnnouncement(
        PreservationBounty(
          id: 'bounty_selfvouch_upgrade',
          cid: 'bafk_selfvouch_upgrade',
          title: 'Re-announcement claiming attestor origin',
          offeredCredits: 25.0,
          originAgentId: attestorAgentId, // ≠ stored claim
          createdAt: DateTime.now(),
          funded: true,
        ),
        escrowAttestation: att,
        trustedAttestors: {attestorHex},
      );
      stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == 'bounty_selfvouch_upgrade');
      expect(stored.funded, isFalse);
      expect(stored.originAgentId, 'bcn_remote_poster');
      expect(creditService.balance, 100.0);
    });

    test('dedup upgrade: same-origin re-announcement by a poster-foreign trusted attestor upgrades (H4)', () async {
      // The intended behavior: poison = faithful copy of the real
      // announcement minus attestation (same claimed poster); the legit
      // attested re-announcement re-claims that same poster — the
      // self-issuance check now asks "is the attestor the poster THIS
      // announcement claims", which is the stored claim too. Foreign →
      // upgrade.
      moltbookService.ingestBountyAnnouncement(_foreignBounty(
        id: 'bounty_same_origin',
        cid: 'bafk_same_origin',
        offeredCredits: 25.0,
      ));
      var stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == 'bounty_same_origin');
      expect(stored.funded, isFalse);
      expect(stored.originAgentId, 'bcn_remote_poster');

      final (att, attestorHex) = await _freshTrustedAttestation(stored);
      moltbookService.ingestBountyAnnouncement(
        _foreignBounty(
          id: 'bounty_same_origin',
          cid: 'bafk_same_origin',
          offeredCredits: 25.0,
        ), // same claimed poster as stored
        escrowAttestation: att,
        trustedAttestors: {attestorHex},
      );
      stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == 'bounty_same_origin');
      expect(stored.funded, isTrue);
      expect(stored.isClaimed, isFalse);
      expect(await moltbookService.claimBounty(stored.id), isTrue);
      expect(creditService.balance, 125.0);
    });

    test('dedup upgrade: matching origin where the attestor IS the claimed poster stays a self-vouch (H4)', () async {
      // Stored record AND re-announcement both claim the attestor's own
      // derived id as the poster — origins match, so isSelfIssuedFor is
      // evaluated and correctly reads self-issued. No upgrade.
      final posterKp = await Ed25519().newKeyPair();
      final posterHex = await _pubHex(posterKp);
      final posterAgentId =
          BeaconEnvelope.deriveAgentId(hexToBytes(posterHex));

      PreservationBounty poison(String title) => PreservationBounty(
            id: 'bounty_selforigin',
            cid: 'bafk_selforigin',
            title: title,
            offeredCredits: 25.0,
            originAgentId: posterAgentId,
            createdAt: DateTime.now(),
            funded: true,
          );

      // First announcement claims the poster id but carries NO
      // attestation → stored unfunded.
      moltbookService.ingestBountyAnnouncement(poison('poison'));
      var stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == 'bounty_selforigin');
      expect(stored.funded, isFalse);

      // The poster's own key attests, trusted, binding the stored
      // record — a self-vouch must never fund, on either ingest path.
      final selfVouch = await _attestEscrow(
        posterKp,
        bountyId: stored.id,
        cid: stored.cid,
        amountMilli: 25000,
      );
      expect(selfVouch, isNotNull);
      moltbookService.ingestBountyAnnouncement(
        poison('re-announcement'),
        escrowAttestation: selfVouch,
        trustedAttestors: {posterHex},
      );
      stored = moltbookService.activeBounties
          .firstWhere((b) => b.id == 'bounty_selforigin');
      expect(stored.funded, isFalse);
      expect(creditService.balance, 100.0);
    });
  });
}
