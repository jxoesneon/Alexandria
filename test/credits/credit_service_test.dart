import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/credits/credit_models.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/poch_service.dart';

void main() {
  group('CreditService Economic & Multi-Resource Accounting Tests (ALX-005)', () {
    late PoCHService pochService;
    late CreditService creditService;

    setUp(() {
      pochService = PoCHService();
      creditService = CreditService(
        pochService: pochService,
        initialBalance: 100.0,
      );
    });

    test('initializes with welcome balance and logs genesis transaction', () {
      expect(creditService.balance, 100.0);
      expect(creditService.protocolTreasury, 50.0);
      expect(creditService.archivalCommonsPool, 250.0);
      expect(creditService.transactions.length, 1);
      expect(creditService.transactions.first.type, CreditType.verificationReward);
    });

    test('awards storage credits with dynamic rarity weighting', () {
      // Test critically endangered work (peerCount = 1 -> 5x multiplier)
      final initialBalance = creditService.balance;
      final earnedEndangered = creditService.awardStorageCredits(
        sizeBytes: 20 * 1024 * 1024, // 20 MB
        peerCount: 1,
        porPassed: true,
        cid: 'bafk_endangered_1',
      );

      expect(earnedEndangered, greaterThan(0));
      expect(creditService.balance, initialBalance + earnedEndangered);
      expect(creditService.totalStorageEarned, earnedEndangered);

      // Test healthy work (peerCount >= 5 -> 1x multiplier)
      final earnedHealthy = creditService.awardStorageCredits(
        sizeBytes: 20 * 1024 * 1024,
        peerCount: 8,
        porPassed: true,
        cid: 'bafk_healthy_1',
      );

      // Endangered should earn significantly more than healthy
      expect(earnedEndangered, greaterThan(earnedHealthy));
    });

    test('penalizes failed PoR challenges with slashing deduction', () {
      final initialBalance = creditService.balance;
      final penalty = creditService.awardStorageCredits(
        sizeBytes: 10 * 1024 * 1024,
        peerCount: 1,
        porPassed: false,
        cid: 'bafk_failed_1',
      );

      expect(penalty, -5.0);
      expect(creditService.balance, initialBalance - 5.0);
    });

    test('awards compute credits for Cauchy RS encoding and OCR extraction', () {
      final initialBalance = creditService.balance;
      final earned = creditService.awardComputeCredits(
        cauchyMb: 10.0,  // 10 * 2.0 = 20.0
        fastCdcMb: 20.0, // 20 * 0.5 = 10.0
        ocrPages: 2,     // 2 * 5.0 = 10.0
        description: 'Parity Shard Computation',
      );

      expect(earned, 40.0);
      expect(creditService.balance, initialBalance + 40.0);
      expect(creditService.totalComputeEarned, 40.0);
    });

    test('awards verification credits and updates PoCH audits', () {
      final initialBalance = creditService.balance;
      final earned = creditService.awardVerificationCredits(
        action: 'Crossref DOI Reconciliation',
        targetId: '10.1038/nature12345',
        amount: 5.0,
      );

      expect(earned, 5.0);
      expect(creditService.balance, initialBalance + 5.0);
      expect(creditService.totalVerificationEarned, 5.0);
    });

    test('settles sponsorship kickback with 85 / 10 / 5 revenue split', () {
      final initialBalance = creditService.balance;
      final initialTreasury = creditService.protocolTreasury;
      final initialCommons = creditService.archivalCommonsPool;

      final receipt = creditService.awardSponsorshipKickback(
        campaignId: 'eff-privacy-grant',
        grossCredits: 100.0,
        dwellTimeSeconds: 6.5,
      );

      expect(receipt.clientKickback, 85.0);
      expect(receipt.archivalCommonsPool, 10.0);
      expect(receipt.protocolFee, 5.0);

      expect(creditService.balance, initialBalance + 85.0);
      expect(creditService.archivalCommonsPool, initialCommons + 10.0);
      expect(creditService.protocolTreasury, initialTreasury + 5.0);
      expect(creditService.totalSponsorshipKickbacks, 85.0);
    });

    test('spends credits and deducts 5% protocol treasury micro-fee', () {
      final initialBalance = creditService.balance;
      final initialTreasury = creditService.protocolTreasury;

      // Spend 50 credits
      final success = creditService.spendCredits(
        amount: 50.0,
        reason: 'Priority Swarm Bandwidth',
      );

      expect(success, isTrue);
      expect(creditService.balance, initialBalance - 50.0);
      expect(creditService.totalSpent, 50.0);
      // 5% treasury fee from 50 is 2.5
      expect(creditService.protocolTreasury, initialTreasury + 2.5);
      expect(creditService.totalFeesContributed, 2.5);

      // Attempt to spend more than available balance
      final overspendSuccess = creditService.spendCredits(
        amount: 1000.0,
        reason: 'Impossible Transaction',
      );
      expect(overspendSuccess, isFalse);
    });
  });
}
