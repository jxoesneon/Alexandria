import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/credits/credit_models.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/sponsorship_service.dart';
import 'package:alexandria/ui/credits/sponsorship_card.dart';

class _FakeCreditService extends CreditService {
  @override
  double get balance => 10.0;

  void rewardProofVerification(int count) {}
}

class _EmptySponsorshipService extends SponsorshipService {
  _EmptySponsorshipService({required super.creditService})
      : super(initialOptIn: true);

  @override
  SponsorshipSlot? findMatchingSlot({
    required String category,
    List<String> tags = const [],
  }) {
    return null;
  }
}

void main() {
  group('SponsorshipCard Tests', () {
    late _FakeCreditService fakeCreditService;
    late SponsorshipService sponsorshipService;

    setUp(() {
      fakeCreditService = _FakeCreditService();
    });

    testWidgets('renders SizedBox.shrink when opt-in is disabled',
        (tester) async {
      sponsorshipService = SponsorshipService(
        creditService: fakeCreditService,
        initialOptIn: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            creditServiceProvider.overrideWith((ref) => fakeCreditService),
            sponsorshipServiceProvider
                .overrideWith((ref) => sponsorshipService),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SponsorshipCard(category: 'academic'),
            ),
          ),
        ),
      );

      expect(find.byType(SponsorshipCard), findsOneWidget);
      expect(find.text('ETHICAL SPONSOR'), findsNothing);
    });

    testWidgets('renders SizedBox.shrink when no matching slot is found',
        (tester) async {
      sponsorshipService = _EmptySponsorshipService(
        creditService: fakeCreditService,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            creditServiceProvider.overrideWith((ref) => fakeCreditService),
            sponsorshipServiceProvider
                .overrideWith((ref) => sponsorshipService),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SponsorshipCard(category: 'nonexistent'),
            ),
          ),
        ),
      );

      expect(find.text('ETHICAL SPONSOR'), findsNothing);
    });

    testWidgets('renders sponsorship card when opt-in is enabled and slot matches',
        (tester) async {
      sponsorshipService = SponsorshipService(
        creditService: fakeCreditService,
        initialOptIn: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            creditServiceProvider.overrideWith((ref) => fakeCreditService),
            sponsorshipServiceProvider
                .overrideWith((ref) => sponsorshipService),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SponsorshipCard(
                category: 'academic',
                tags: ['science', 'biology'],
              ),
            ),
          ),
        ),
      );

      expect(find.text('ETHICAL SPONSOR'), findsOneWidget);
      expect(find.textContaining('Kickback'), findsOneWidget);

      // Fast forward dwell timer (5 seconds) to trigger impression receipt
      await tester.pump(const Duration(seconds: 6));

      // After dwell, kickback should be claimed
      expect(find.textContaining('Claimed'), findsOneWidget);
      expect(sponsorshipService.impressionHistory.length, equals(1));
    });
  });
}
