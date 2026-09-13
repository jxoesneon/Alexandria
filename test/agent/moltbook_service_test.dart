import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/poch_service.dart';

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
      expect(creditService.balance, initialBalance - 25.0); // Escrowed!

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

    test('claims and fulfills bounty, awarding storage credits', () async {
      final bounty = moltbookService.activeBounties.first;
      final initialBalance = creditService.balance;

      final success = moltbookService.claimBounty(bounty.id);
      expect(success, isTrue);
      expect(bounty.isClaimed, isTrue);

      // Solver awarded storage credits
      expect(creditService.balance, greaterThan(initialBalance));

      // Attempting to claim already claimed bounty fails
      final retrySuccess = moltbookService.claimBounty(bounty.id);
      expect(retrySuccess, isFalse);
    });
  });
}
