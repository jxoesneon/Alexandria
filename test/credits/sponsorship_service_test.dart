import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/sponsorship_service.dart';

void main() {
  group('SponsorshipService Privacy & Attention Verification Tests (ALX-005 §5)', () {
    late CreditService creditService;
    late SponsorshipService sponsorshipService;

    setUp(() {
      creditService = CreditService(initialBalance: 50.0);
      sponsorshipService = SponsorshipService(creditService: creditService);
    });

    test('is disabled by default to preserve user privacy', () {
      expect(sponsorshipService.isOptInEnabled, isFalse);
      expect(sponsorshipService.catalog.isNotEmpty, isTrue);

      // With opt-in disabled, matching returns null
      final slot = sponsorshipService.findMatchingSlot(
        category: 'technology',
        tags: ['privacy'],
      );
      expect(slot, isNull);
    });

    test('enables contextual matching upon explicit opt-in', () {
      sponsorshipService.toggleOptIn(true);
      expect(sponsorshipService.isOptInEnabled, isTrue);

      final slot = sponsorshipService.findMatchingSlot(
        category: 'technology',
        tags: ['cryptography'],
      );

      expect(slot, isNotNull);
      expect(slot!.sponsorName, 'Electronic Frontier Foundation');
    });

    test('rejects impressions with dwell time < 5.0 seconds', () {
      sponsorshipService.toggleOptIn(true);
      final slot = sponsorshipService.catalog.first;

      // 3.0 seconds is below the 5.0s attention requirement
      final receipt = sponsorshipService.recordDwellImpression(
        slot: slot,
        dwellTimeSeconds: 3.0,
      );

      expect(receipt, isNull);
      expect(sponsorshipService.impressionHistory.isEmpty, isTrue);
      expect(creditService.balance, 50.0); // No kickback awarded
    });

    test('verifies impressions with dwell time >= 5.0s and credits 85% kickback', () {
      sponsorshipService.toggleOptIn(true);
      final slot = sponsorshipService.catalog.first;
      final expectedKickback = slot.rewardCredits * 0.85;

      final receipt = sponsorshipService.recordDwellImpression(
        slot: slot,
        dwellTimeSeconds: 5.5,
      );

      expect(receipt, isNotNull);
      expect(receipt!.clientKickback, expectedKickback);
      expect(sponsorshipService.impressionHistory.length, 1);
      expect(creditService.balance, 50.0 + expectedKickback);
    });
  });
}
