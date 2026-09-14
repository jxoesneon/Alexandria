import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/agent/agent_steward_service.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/poch_service.dart';

void main() {
  group('AgentStewardService Autonomous Loop Tests (ALX-006 §6)', () {
    late PoCHService pochService;
    late CreditService creditService;
    late MoltbookService moltbookService;
    late AgentStewardService stewardService;

    setUp(() {
      pochService = PoCHService();
      creditService = CreditService(
        pochService: pochService,
        initialBalance: 100.0,
      );
      moltbookService = MoltbookService(creditService: creditService);
      stewardService = AgentStewardService(
        creditService: creditService,
        pochService: pochService,
        moltbookService: moltbookService,
      );
    });

    tearDown(() {
      stewardService.stopSteward();
    });

    test('initializes in stopped state with zero counters', () {
      expect(stewardService.isRunning, isFalse);
      expect(stewardService.totalBountiesClaimed, 0);
      expect(stewardService.totalComputeCyclesExecuted, 0);
      expect(stewardService.totalCreditsEarned, 0.0);
      expect(stewardService.activityLog, isEmpty);
    });

    test('starts and stops steward cleanly', () {
      stewardService.startSteward(interval: const Duration(seconds: 10));
      expect(stewardService.isRunning, isTrue);
      expect(stewardService.activityLog.isNotEmpty, isTrue);

      stewardService.stopSteward();
      expect(stewardService.isRunning, isFalse);
      expect(stewardService.activityLog.first, contains('stopped'));
    });

    test('autonomously restores PoCH compliance without self-minting credits', () async {
      // Initially node has 0 storage / 0 seeding -> PoCH < 1.0
      expect(pochService.metrics.score, lessThan(1.0));

      // Run one steward iteration
      await stewardService.runStewardIteration();

      // Verify compute executed and PoCH maintenance recorded
      expect(stewardService.totalComputeCyclesExecuted, 1);
      expect(stewardService.activityLog.any((l) => l.contains('Cauchy RS')), isTrue);

      // ALX-010: self-reported steward compute must NOT mint credits —
      // no transaction may carry the steward compute description.
      expect(
        creditService.transactions
            .any((t) => t.description.contains('Autonomous Steward')),
        isFalse,
      );
      expect(
        stewardService.activityLog.any((l) => l.contains('no credit minted')),
        isTrue,
      );
    });

    test('autonomously scans and fulfills active Moltbook bounties', () async {
      expect(moltbookService.activeBounties.isNotEmpty, isTrue);
      final initialBountiesCount = moltbookService.activeBounties.length;

      await stewardService.runStewardIteration();

      expect(stewardService.totalBountiesClaimed, greaterThanOrEqualTo(1));
      expect(moltbookService.activeBounties.length, lessThan(initialBountiesCount));
      expect(stewardService.activityLog.any((l) => l.contains('Claimed & fulfilled')), isTrue);
    });
  });
}
