import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/agent/beacon_models.dart';
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
      // escrowAttested simulates the transport having verified the
      // poster's escrow attestation — without it the funded guard would
      // reject before the blockstore check this test targets.
      ipfsMoltbook.ingestBountyAnnouncement(bounty, escrowAttested: true);

      // No work evidence: CID bytes were never stored locally.
      expect(await ipfsMoltbook.claimBounty(bounty.id), isFalse);
      expect(bounty.isClaimed, isFalse);
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
      // Attested so the claim reaches the throwing getFile stream.
      ipfsMoltbook.ingestBountyAnnouncement(bounty, escrowAttested: true);

      // getFile throws synchronously inside the stream — claim must
      // swallow it, release the claim mark, and report failure.
      expect(await ipfsMoltbook.claimBounty(bounty.id), isFalse);
      expect(bounty.isClaimed, isFalse);
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
      // whose transport layer verified the poster's escrow attestation.
      claimant.ingestBountyAnnouncement(bounty, escrowAttested: true);
      expect(await claimant.claimBounty(bounty.id), isTrue);
      expect(bounty.isClaimed, isTrue);

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
      ipfsMoltbook.ingestBountyAnnouncement(bounty, escrowAttested: true);

      // Two overlapping claims: the synchronous claim mark must make the
      // second call observe isClaimed before its first await.
      final results = await Future.wait([
        ipfsMoltbook.claimBounty(bounty.id),
        ipfsMoltbook.claimBounty(bounty.id),
      ]);

      expect(results.where((r) => r).length, 1);
      expect(bounty.isClaimed, isTrue);
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
      ipfsMoltbook.ingestBountyAnnouncement(bounty, escrowAttested: true);

      final success = await ipfsMoltbook.claimBounty(bounty.id);
      expect(success, isTrue);
      expect(bounty.isClaimed, isTrue);
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
  });
}
