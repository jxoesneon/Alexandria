import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/governance_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/ledger_service.dart';

class _FakeIdentityService implements IdentityService {
  _FakeIdentityService(this.keyPair, this.publicKeyBytes, {DateTime? createdAt})
      : createdAt = createdAt ?? DateTime(2025, 1, 1);

  final SimpleKeyPair keyPair;
  final Uint8List publicKeyBytes;
  final DateTime createdAt;

  @override
  Future<AlexandriaIdentity?> getIdentity() async => AlexandriaIdentity(
        publicKey: publicKeyBytes,
        privateKey: Uint8List.fromList(await keyPair.extractPrivateKeyBytes()),
        createdAt: createdAt,
      );

  @override
  Future<Uint8List> sign(Uint8List data) async {
    final sig = await Ed25519().sign(data, keyPair: keyPair);
    return Uint8List.fromList(sig.bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GovernanceService Tests', () {
    late _FakeIdentityService identity;
    late LedgerService ledger;
    late GovernanceService governance;

    setUp(() async {
      final algo = Ed25519();
      final kp = await algo.newKeyPair();
      final pub = await kp.extractPublicKey();
      // Account created 60 days ago
      identity = _FakeIdentityService(
        kp,
        Uint8List.fromList(pub.bytes),
        createdAt: DateTime.now().subtract(const Duration(days: 60)),
      );
      ledger = LedgerService(identity);
      governance = GovernanceService(identity, ledger);
    });

    test('governanceServiceProvider exposes GovernanceService', () {
      final container = ProviderContainer(overrides: [
        identityServiceProvider.overrideWithValue(identity),
        ledgerServiceProvider.overrideWithValue(ledger),
      ]);
      addTearDown(container.dispose);

      final service = container.read(governanceServiceProvider);
      expect(service, isA<GovernanceService>());
    });

    test('canVote and canCreateProposal require min reputation and account age', () async {
      // 0 reputation -> cannot vote
      expect(await governance.canVote(), isFalse);
      expect(await governance.canCreateProposal(), isFalse);

      // Add reputation up to 10 points
      for (int i = 0; i < 5; i++) {
        await ledger.recordAction(
          action: LedgerActionType.validateHash, // 2.0 each -> 10.0 total
          contentCid: 'bafy_rep_$i',
        );
      }

      expect(ledger.totalReputation, greaterThanOrEqualTo(10.0));
      expect(await governance.canVote(), isTrue);
      expect(await governance.canCreateProposal(), isTrue);
    });

    test('creates and lists proposals', () async {
      for (int i = 0; i < 5; i++) {
        await ledger.recordAction(
          action: LedgerActionType.validateHash,
          contentCid: 'bafy_setup_$i',
        );
      }

      final proposal = await governance.createProposal(
        type: ProposalType.gatewayAddition,
        title: 'Add New IPFS Gateway',
        description: 'Proposal to add regional gateway node',
        payload: {'gatewayUrl': 'https://gateway.alexandria.io'},
      );

      expect(proposal, isNotNull);
      expect(proposal!.title, equals('Add New IPFS Gateway'));
      expect(proposal.status, equals(ProposalStatus.active));
      expect(proposal.signature, isNotEmpty);
      expect(governance.proposals.length, equals(1));
      expect(governance.activeProposals.length, equals(1));

      // Immediate second proposal is rate limited
      final secondProposal = await governance.createProposal(
        type: ProposalType.schemaChange,
        title: 'Rate limited proposal',
        description: 'Should fail rate limit',
        payload: {},
      );
      expect(secondProposal, isNull);
    });

    test('votes on an active proposal', () async {
      for (int i = 0; i < 5; i++) {
        await ledger.recordAction(
          action: LedgerActionType.validateHash,
          contentCid: 'bafy_rep_$i',
        );
      }

      final proposal = await governance.createProposal(
        type: ProposalType.priorityChange,
        title: 'Adjust Endangerment Threshold',
        description: 'Raise minimum replicas',
        payload: {'threshold': 5},
      );

      expect(proposal, isNotNull);

      // Vote approve
      final voted = await governance.vote(
        proposalId: proposal!.id,
        approve: true,
      );
      expect(voted, isTrue);
      expect(proposal.votes.length, equals(1));
      expect(proposal.approvalWeight, greaterThan(0));

      // Duplicate vote from same identity fails
      final duplicateVote = await governance.vote(
        proposalId: proposal.id,
        approve: false,
      );
      expect(duplicateVote, isFalse);
    });

    test('resolves and executes expired proposal when quorum and threshold met', () async {
      for (int i = 0; i < 500; i++) {
        await ledger.recordAction(
          action: LedgerActionType.validateHash,
          contentCid: 'bafy_weight_$i',
        );
      }

      final expiredProposal = Proposal(
        id: 'expired_prop_1',
        type: ProposalType.gatewayAddition,
        title: 'Add Gateway',
        description: 'Desc',
        payload: {},
        proposerId: 'proposer_pubkey',
        created: DateTime.now().subtract(const Duration(days: 10)),
        deadline: DateTime.now().subtract(const Duration(days: 1)),
        status: ProposalStatus.active,
        signature: 'sig',
      );

      governance.addProposal(expiredProposal);

      // Vote on expired proposal returns false
      final canVoteExpired = await governance.vote(
        proposalId: expiredProposal.id,
        approve: true,
      );
      expect(canVoteExpired, isFalse);
    });

    test('Proposal.status is read-only — transitions only through '
        'activate()/resolve() (campaign-2)', () {
      final proposal = Proposal(
        id: 'lifecycle_prop',
        type: ProposalType.gatewayAddition,
        title: 'Lifecycle',
        description: 'status transitions',
        payload: {},
        proposerId: 'proposer',
        created: DateTime.now(),
        deadline: DateTime.now().add(const Duration(days: 7)),
        signature: 'sig',
      );

      expect(proposal.status, equals(ProposalStatus.draft));

      // Illegal transitions are no-ops, not rewrites.
      proposal.resolve(ProposalStatus.approved);
      expect(proposal.status, equals(ProposalStatus.draft));
      proposal.resolve(ProposalStatus.executed);
      expect(proposal.status, equals(ProposalStatus.draft));

      proposal.activate();
      expect(proposal.status, equals(ProposalStatus.active));
      // activate is idempotent beyond draft.
      proposal.activate();
      expect(proposal.status, equals(ProposalStatus.active));

      proposal.resolve(ProposalStatus.approved);
      expect(proposal.status, equals(ProposalStatus.approved));
      // approved → rejected is a backward/illegal move: no-op.
      proposal.resolve(ProposalStatus.rejected);
      expect(proposal.status, equals(ProposalStatus.approved));
      // approved → executed is the only terminal path.
      proposal.resolve(ProposalStatus.executed);
      expect(proposal.status, equals(ProposalStatus.executed));
      // Terminal → anything: no-op.
      proposal.resolve(ProposalStatus.active);
      proposal.activate();
      expect(proposal.status, equals(ProposalStatus.executed));
    });

    test('addProposal dedupes by id and strips unverifiable votes/status',
        () {
      final forged = Proposal(
        id: 'remote_prop_1',
        type: ProposalType.gatewayAddition,
        title: 'Forged remote proposal',
        description: 'Claims votes and active status on the wire',
        payload: {},
        proposerId: 'attacker_pubkey',
        created: DateTime.now(),
        deadline: DateTime.now().add(const Duration(days: 7)),
        votes: [
          GovernanceVote(
            voterId: 'attacker_pubkey',
            weight: 9999.0,
            approve: true,
            timestamp: DateTime.now(),
            signature: 'forged_vote_sig',
          ),
        ],
        status: ProposalStatus.active,
        signature: 'forged_prop_sig',
      );

      governance.addProposal(forged);
      expect(governance.proposals.length, equals(1));

      // Unverifiable claims are stripped on ingest: no votes, draft status
      final stored = governance.proposals.first;
      expect(stored.votes, isEmpty);
      expect(stored.status, equals(ProposalStatus.draft));
      expect(stored.approvalWeight, equals(0.0));
      expect(governance.activeProposals, isEmpty);

      // Mesh redelivery / echo with the same id is ignored
      governance.addProposal(forged);
      governance.addProposal(Proposal(
        id: 'remote_prop_1',
        type: ProposalType.schemaChange,
        title: 'Duplicate id, different content',
        description: 'must be dropped',
        payload: {},
        proposerId: 'other',
        created: DateTime.now(),
        deadline: DateTime.now().add(const Duration(days: 7)),
        status: ProposalStatus.approved,
        signature: 'sig2',
      ));
      expect(governance.proposals.length, equals(1));
      expect(governance.proposals.first.title, equals('Forged remote proposal'));
    });

    test('addProposal preserves claimed status only when signatureVerified',
        () {
      governance.addProposal(
        Proposal(
          id: 'verified_prop_1',
          type: ProposalType.priorityChange,
          title: 'Verified remote proposal',
          description: 'transport verified the proposer signature',
          payload: {},
          proposerId: 'proposer_pubkey',
          created: DateTime.now(),
          deadline: DateTime.now().add(const Duration(days: 7)),
          votes: [
            GovernanceVote(
              voterId: 'voter',
              weight: 5.0,
              approve: true,
              timestamp: DateTime.now(),
              signature: 'sig',
            ),
          ],
          status: ProposalStatus.active,
          signature: 'verified_sig',
        ),
        signatureVerified: true,
      );

      final stored = governance.proposals.first;
      expect(stored.status, equals(ProposalStatus.active));
      // Votes are still stripped: each carries a separately unverified sig
      expect(stored.votes, isEmpty);
      expect(governance.activeProposals.length, equals(1));
    });

    test('Proposal and GovernanceVote serialization and calculations', () {
      final vote = GovernanceVote(
        voterId: 'voter_1',
        weight: 15.0,
        approve: true,
        timestamp: DateTime.now(),
        signature: 'sig',
      );
      final voteJson = vote.toJson();
      final roundVote = GovernanceVote.fromJson(voteJson);
      expect(roundVote.voterId, equals('voter_1'));
      expect(roundVote.weight, equals(15.0));

      final proposal = Proposal(
        id: 'p1',
        type: ProposalType.schemaChange,
        title: 'Schema Update',
        description: 'New fields',
        payload: {'version': 2},
        proposerId: 'proposer_1',
        created: DateTime.now(),
        deadline: DateTime.now().add(const Duration(days: 14)),
        votes: [vote],
        signature: 'prop_sig',
      );

      expect(proposal.approvalWeight, equals(15.0));
      expect(proposal.rejectionWeight, equals(0.0));
      expect(proposal.totalVoteWeight, equals(15.0));
      expect(proposal.approvalPercentage, equals(1.0));
      expect(proposal.passes(), isTrue);

      final propJson = proposal.toJson();
      final roundProp = Proposal.fromJson(propJson);
      expect(roundProp.id, equals(proposal.id));
      expect(roundProp.type, equals(ProposalType.schemaChange));
    });
  });
}
