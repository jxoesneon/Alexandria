import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/biometric_service.dart';
import 'package:alexandria/services/consensus_service.dart';
import 'package:alexandria/services/governance_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/ledger_service.dart';

class _FakeIdentityService implements IdentityService {
  _FakeIdentityService(this.keyPair, this.publicKeyBytes,
      {this.returnNullIdentity = false});

  final SimpleKeyPair keyPair;
  final Uint8List publicKeyBytes;
  bool returnNullIdentity;
  Duration signDelay = Duration.zero;

  @override
  Future<AlexandriaIdentity?> getIdentity() async {
    if (returnNullIdentity) return null;
    return AlexandriaIdentity(
      publicKey: publicKeyBytes,
      privateKey: Uint8List.fromList(await keyPair.extractPrivateKeyBytes()),
      createdAt: DateTime(2025, 1, 1),
    );
  }

  @override
  Future<Uint8List> sign(Uint8List data) async {
    if (signDelay > Duration.zero) await Future.delayed(signDelay);
    final sig = await Ed25519().sign(data, keyPair: keyPair);
    return Uint8List.fromList(sig.bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBiometricService implements BiometricService {
  _FakeBiometricService(this.lastAuth);
  final DateTime? lastAuth;

  @override
  DateTime? get lastAuthenticatedAt => lastAuth;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<(_FakeIdentityService, LedgerService)> _identityAndLedger() async {
  final kp = await Ed25519().newKeyPair();
  final pub = await kp.extractPublicKey();
  final identity =
      _FakeIdentityService(kp, Uint8List.fromList(pub.bytes));
  return (identity, LedgerService(identity));
}

/// Accrues some ledger reputation so governance vote eligibility and
/// attested vote weight are nonzero.
Future<void> _earnReputation(LedgerService ledger, {int pins = 12}) async {
  for (var i = 0; i < pins; i++) {
    await ledger.recordAction(
      action: LedgerActionType.pinContent,
      contentCid: 'bafy_pin_$i',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GovernanceService coverage extras', () {
    test('provider resolves', () async {
      final (identity, ledger) = await _identityAndLedger();
      final container = ProviderContainer(overrides: [
        identityServiceProvider.overrideWithValue(identity),
        ledgerServiceProvider.overrideWithValue(ledger),
      ]);
      addTearDown(container.dispose);
      expect(container.read(governanceServiceProvider),
          isA<GovernanceService>());
    });

    test('attested tally getters, quorum and pass checks', () async {
      final (identity, ledger) = await _identityAndLedger();
      await _earnReputation(ledger);
      final service = GovernanceService(identity, ledger);

      final proposal = await service.createProposal(
        type: ProposalType.gatewayAddition,
        title: 'Add gateway',
        description: 'desc',
        payload: const {},
      );
      expect(proposal, isNotNull);

      // Before any vote: attested tallies run but are zero.
      expect(proposal!.attestedApprovalWeight, 0.0);
      expect(proposal.attestedRejectionWeight, 0.0);
      expect(proposal.attestedTotalVoteWeight, 0.0);
      expect(proposal.hasAttestedQuorum(0.0), isFalse);
      expect(proposal.attestedPasses(), isFalse);

      final ok = await service.vote(proposalId: proposal.id, approve: true);
      expect(ok, isTrue);

      // Now the attested getters see the ledger-derived ballot.
      expect(proposal.attestedApprovalWeight, greaterThan(0));
      expect(proposal.attestedRejectionWeight, 0.0);
      expect(proposal.attestedTotalVoteWeight,
          proposal.attestedApprovalWeight);
      expect(proposal.hasQuorum(1.0), isA<bool>());
      expect(
          proposal.hasAttestedQuorum(proposal.attestedTotalVoteWeight),
          isTrue);
      expect(proposal.attestedPasses(), isTrue);
    });

    test('vote throws StateError on unknown proposal id', () async {
      final (identity, ledger) = await _identityAndLedger();
      await _earnReputation(ledger);
      final service = GovernanceService(identity, ledger);
      await expectLater(
        service.vote(proposalId: 'nope', approve: true),
        throwsA(isA<StateError>()),
      );
    });

    test('expired proposal resolves through _checkAndResolveProposal',
        () async {
      final (identity, ledger) = await _identityAndLedger();
      await _earnReputation(ledger);
      // Delayed signing: the proposal's deadline slides into the past
      // between the isExpired guard in vote() and the resolution pass.
      identity.signDelay = const Duration(milliseconds: 300);
      final service = GovernanceService(identity, ledger);

      final proposal = Proposal(
        id: 'prop_expired',
        type: ProposalType.priorityChange,
        title: 'Expired prop',
        description: 'desc',
        payload: const {},
        proposerId: 'someone',
        created: DateTime.now().subtract(const Duration(days: 10)),
        deadline: DateTime.now().add(const Duration(milliseconds: 60)),
        status: ProposalStatus.active,
        signature: 'sig',
      );
      service.addProposal(proposal, signatureVerified: true);
      final stored =
          service.proposals.firstWhere((p) => p.id == 'prop_expired');

      final ok = await service.vote(proposalId: 'prop_expired',
          approve: true);
      expect(ok, isTrue);
      // Quorum met (single attested vote IS the whole eligible base) and
      // it passed → executed.
      expect(stored.status, ProposalStatus.executed);
    });

    test('expired proposal rejects when quorum unattainable', () async {
      final (identity, ledger) = await _identityAndLedger();
      await _earnReputation(ledger);
      identity.signDelay = const Duration(milliseconds: 300);
      final service = GovernanceService(identity, ledger);

      // Rejection vote on an expiring proposal → attestedPasses false.
      final proposal = Proposal(
        id: 'prop_expired_rej',
        type: ProposalType.emergency,
        title: 'Expired reject',
        description: 'desc',
        payload: const {},
        proposerId: 'someone',
        created: DateTime.now().subtract(const Duration(days: 10)),
        deadline: DateTime.now().add(const Duration(milliseconds: 60)),
        status: ProposalStatus.active,
        signature: 'sig',
      );
      service.addProposal(proposal, signatureVerified: true);
      final stored =
          service.proposals.firstWhere((p) => p.id == 'prop_expired_rej');

      final ok = await service.vote(
          proposalId: 'prop_expired_rej', approve: false);
      expect(ok, isTrue);
      expect(stored.status, ProposalStatus.rejected);
    });

    test('Proposal.fromJson without votes key yields empty votes/draft',
        () {
      final json = {
        'id': 'p1',
        'type': 'schemaChange',
        'title': 't',
        'description': 'd',
        'payload': <String, dynamic>{},
        'proposerId': 'x',
        'created': DateTime(2026, 1, 1).toIso8601String(),
        'deadline': DateTime(2026, 1, 8).toIso8601String(),
        'status': 'approved',
        'signature': 's',
      };
      final p = Proposal.fromJson(json);
      expect(p.votes, isEmpty);
      expect(p.status, ProposalStatus.draft);
    });
  });

  group('ConsensusService coverage extras', () {
    test('provider wires biometric attestation clock', () async {
      final (identity, ledger) = await _identityAndLedger();
      final container = ProviderContainer(overrides: [
        identityServiceProvider.overrideWithValue(identity),
        ledgerServiceProvider.overrideWithValue(ledger),
        biometricServiceProvider.overrideWithValue(
            _FakeBiometricService(DateTime.now())),
      ]);
      addTearDown(container.dispose);
      final service = container.read(consensusServiceProvider);
      // Cast a vote through the provider-built service so the wired
      // humanAttestationClock closure (provider line 19) executes.
      final req = await service.proposeChange(
        targetCid: 'bafy_x',
        field: 'title',
        currentValue: 'a',
        proposedValue: 'b',
      );
      final vote = await service.castVote(
        requestId: req.id,
        approve: true,
        reputation: 1.0,
        daysActive: 1,
      );
      expect(vote, isNotNull);
      expect(vote!.isHuman, isTrue);
    });

    test('isApproved on resolved requests reads terminal status', () {
      final req = ChangeRequest(
        id: 'r1',
        targetCid: 'cid',
        field: 'f',
        currentValue: 'a',
        proposedValue: 'b',
        proposerKey: Uint8List(32),
        proposerSignature: Uint8List(64),
        timestamp: DateTime.now(),
      );
      req.resolve(ChangeRequestStatus.approved);
      expect(req.isApproved, isTrue);

      final req2 = ChangeRequest(
        id: 'r2',
        targetCid: 'cid',
        field: 'f',
        currentValue: 'a',
        proposedValue: 'b',
        proposerKey: Uint8List(32),
        proposerSignature: Uint8List(64),
        timestamp: DateTime.now(),
      );
      req2.resolve(ChangeRequestStatus.vetoed);
      expect(req2.isApproved, isFalse);
      expect(req2.isRejected, isFalse);
    });

    test('ChangeRequest toJson/fromJson round-trips uploaderKey', () {
      final req = ChangeRequest(
        id: 'r3',
        targetCid: 'cid3',
        field: 'f',
        currentValue: 'a',
        proposedValue: 'b',
        proposerKey: Uint8List.fromList(List.filled(32, 1)),
        proposerSignature: Uint8List.fromList(List.filled(64, 2)),
        timestamp: DateTime(2026, 3, 3),
        uploaderKey: Uint8List.fromList(List.filled(32, 9)),
        isAiProposal: true,
      );
      final restored = ChangeRequest.fromJson(req.toJson());
      expect(restored.id, 'r3');
      expect(restored.uploaderKey, isNotNull);
      expect(restored.uploaderKey!.first, 9);
      expect(restored.isAiProposal, isTrue);
      // Wire status is unverifiable — always re-enters pending.
      expect(restored.status, ChangeRequestStatus.pending);
    });

    test('proposeChange throws without identity', () async {
      final kp = await Ed25519().newKeyPair();
      final pub = await kp.extractPublicKey();
      final nullIdentity = _FakeIdentityService(
          kp, Uint8List.fromList(pub.bytes),
          returnNullIdentity: true);
      final service =
          ConsensusService(nullIdentity, LedgerService(nullIdentity));
      await expectLater(
        service.proposeChange(
          targetCid: 'c',
          field: 'f',
          currentValue: 1,
          proposedValue: 2,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('uploaderResolver injection path', () async {
      final (identity, ledger) = await _identityAndLedger();
      final resolved = Uint8List.fromList(List.filled(32, 7));
      final service = ConsensusService(identity, ledger,
          uploaderResolver: (cid) async => resolved);
      final req = await service.proposeChange(
        targetCid: 'bafy_remote',
        field: 'f',
        currentValue: 1,
        proposedValue: 2,
      );
      expect(req.uploaderKey, resolved);
    });

    test('castVote/veto/fastTrack on unknown id throw StateError',
        () async {
      final (identity, ledger) = await _identityAndLedger();
      final service = ConsensusService(identity, ledger);
      await expectLater(
        service.castVote(
            requestId: 'missing',
            approve: true,
            reputation: 1,
            daysActive: 1),
        throwsA(isA<StateError>()),
      );
      await expectLater(service.vetoChange('missing'),
          throwsA(isA<StateError>()));
      await expectLater(service.fastTrackChange('missing'),
          throwsA(isA<StateError>()));
    });

    test('castVote throws without identity', () async {
      final (identity, ledger) = await _identityAndLedger();
      final service = ConsensusService(identity, ledger);
      final req = await service.proposeChange(
        targetCid: 'bafy_ni',
        field: 'f',
        currentValue: 1,
        proposedValue: 2,
      );
      // Identity disappears between proposal and vote — the guard must
      // fail closed rather than mint an unattributed ballot.
      identity.returnNullIdentity = true;
      await expectLater(
        service.castVote(
            requestId: req.id,
            approve: true,
            reputation: 1,
            daysActive: 1),
        throwsA(isA<StateError>()),
      );
    });
  });
}
