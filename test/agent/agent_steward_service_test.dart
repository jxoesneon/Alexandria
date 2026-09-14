import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/agent/agent_steward_service.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/poch_service.dart';
import 'package:alexandria/services/ipfs_service.dart';

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

    test('skips unfunded seeded bounties (announcements carry no escrow)', () async {
      expect(moltbookService.activeBounties.isNotEmpty, isTrue);
      expect(moltbookService.activeBounties.every((b) => !b.funded), isTrue);
      final initialBountiesCount = moltbookService.activeBounties.length;
      final initialBalance = creditService.balance;

      await stewardService.runStewardIteration();

      // Seeded demo bounties are unfunded — nothing may be claimed or paid.
      expect(stewardService.totalBountiesClaimed, 0);
      expect(moltbookService.activeBounties.length, initialBountiesCount);
      expect(creditService.balance, initialBalance);
      expect(stewardService.activityLog.any((l) => l.contains('Claimed & fulfilled')), isFalse);
    });

    test('autonomously fulfills funded FOREIGN bounty when CID is replicated locally', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ipfsService = container.read(ipfsServiceProvider);
      // Poster and steward share one ledger so escrow conservation is
      // directly observable (poster -25, claimant +25, treasury +0).
      final poster = MoltbookService(creditService: creditService);
      final ipfsMoltbook = MoltbookService(
        creditService: creditService,
        ipfsService: ipfsService,
      );
      final ipfsSteward = AgentStewardService(
        creditService: creditService,
        pochService: pochService,
        moltbookService: ipfsMoltbook,
      );
      addTearDown(ipfsSteward.stopSteward);
      // Deterministic identities so the bounty is genuinely foreign.
      await poster.setKeyPair(await Ed25519().newKeyPair());
      await ipfsMoltbook.setKeyPair(await Ed25519().newKeyPair());

      // Replicate the document locally; a REMOTE node escrows the bounty.
      final cid = await ipfsService.addFile(Uint8List.fromList([9, 8, 7, 6]));
      final treasuryBefore = creditService.protocolTreasury;
      final bounty = await poster.postPreservationBounty(
        cid: cid,
        title: 'Funded Preservation Bounty',
        offeredCredits: 25.0,
        urgency: 'critical',
        force: true,
      );
      expect(creditService.balance, 75.0); // 25.0 escrowed at post time

      // The announcement propagates over the transport to this node.
      // (Key rotation on the posting node must NOT be required — and must
      // never suffice — to claim; locally posted ids are barred for life.)
      // escrowAttested simulates the transport having verified the
      // poster's escrow attestation — remote `funded` flags alone are
      // stripped on ingest (E-T5r #1).
      ipfsMoltbook.ingestBountyAnnouncement(bounty, escrowAttested: true);

      await ipfsSteward.runStewardIteration();

      expect(ipfsSteward.totalBountiesClaimed, 1);
      expect(bounty.isClaimed, isTrue);
      expect(creditService.balance, 100.0); // Net-zero: escrow paid out
      expect(creditService.protocolTreasury, treasuryBefore); // +0 fee
      expect(ipfsSteward.activityLog.any((l) => l.contains('Claimed & fulfilled')), isTrue);
    });

    test('steward cannot claim a locally posted bounty even after key rotation', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ipfsService = container.read(ipfsServiceProvider);
      final ipfsMoltbook = MoltbookService(
        creditService: creditService,
        ipfsService: ipfsService,
      );
      final ipfsSteward = AgentStewardService(
        creditService: creditService,
        pochService: pochService,
        moltbookService: ipfsMoltbook,
      );
      addTearDown(ipfsSteward.stopSteward);

      // Even with work evidence present, a self-posted escrow can never be
      // claimed back by the same node (E-T5 #2).
      final cid = await ipfsService.addFile(Uint8List.fromList([9, 8, 7, 6]));
      final bounty = await ipfsMoltbook.postPreservationBounty(
        cid: cid,
        title: 'Self-Posted Bounty',
        offeredCredits: 25.0,
        urgency: 'critical',
        force: true,
      );
      expect(creditService.balance, 75.0);

      // Rotate identity — this was the exploit vector.
      await ipfsMoltbook.setKeyPair(await Ed25519().newKeyPair());

      await ipfsSteward.runStewardIteration();

      expect(ipfsSteward.totalBountiesClaimed, 0);
      expect(bounty.isClaimed, isFalse);
      expect(creditService.balance, 75.0);
      expect(ipfsSteward.activityLog.any((l) => l.contains('Claimed & fulfilled')), isFalse);
    });
  });
}
