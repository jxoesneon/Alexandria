import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/consensus_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/ledger_service.dart';

class _FakeIdentityService implements IdentityService {
  _FakeIdentityService(this.keyPair, this.publicKeyBytes);

  final SimpleKeyPair keyPair;
  final Uint8List publicKeyBytes;

  @override
  Future<AlexandriaIdentity?> getIdentity() async => AlexandriaIdentity(
        publicKey: publicKeyBytes,
        privateKey: Uint8List.fromList(await keyPair.extractPrivateKeyBytes()),
        createdAt: DateTime(2025, 1, 1),
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

  group('ConsensusService Tests', () {
    late _FakeIdentityService identity;
    late LedgerService ledger;
    late ConsensusService consensus;

    setUp(() async {
      final algo = Ed25519();
      final kp = await algo.newKeyPair();
      final pub = await kp.extractPublicKey();
      identity = _FakeIdentityService(kp, Uint8List.fromList(pub.bytes));
      ledger = LedgerService(identity);
      consensus = ConsensusService(identity, ledger);
    });

    test('consensusServiceProvider provides a ConsensusService', () {
      final container = ProviderContainer(overrides: [
        identityServiceProvider.overrideWithValue(identity),
        ledgerServiceProvider.overrideWithValue(ledger),
      ]);
      addTearDown(container.dispose);

      final service = container.read(consensusServiceProvider);
      expect(service, isA<ConsensusService>());
    });

    test('proposeChange creates request and logs audit entry', () async {
      final req = await consensus.proposeChange(
        targetCid: 'bafy_target_cid',
        field: 'title',
        currentValue: 'Old Title',
        proposedValue: 'Corrected Title',
      );

      expect(req.id, isNotEmpty);
      expect(req.targetCid, equals('bafy_target_cid'));
      expect(req.field, equals('title'));
      expect(req.currentValue, equals('Old Title'));
      expect(req.proposedValue, equals('Corrected Title'));
      expect(req.status, equals(ChangeRequestStatus.pending));
      expect(consensus.pendingRequests.length, equals(1));

      final audit = consensus.getAuditLog('bafy_target_cid');
      expect(audit.length, equals(1));
      expect(audit.first.eventType, equals('proposed'));
    });

    test('castVote registers vote and resolves when threshold met', () async {
      final req = await consensus.proposeChange(
        targetCid: 'bafy_vote_cid',
        field: 'author',
        currentValue: 'Unknown',
        proposedValue: 'Aristotle',
      );

      final vote = await consensus.castVote(
        requestId: req.id,
        approve: true,
        reputation: 2000.0,
        daysActive: 365,
        isHuman: true,
      );

      expect(vote, isNotNull);
      expect(vote!.approve, isTrue);
      expect(vote.weight, greaterThan(0));
      expect(req.votes.length, equals(1));

      // Duplicate vote fails
      final dupe = await consensus.castVote(
        requestId: req.id,
        approve: false,
        reputation: 2000.0,
        daysActive: 365,
      );
      expect(dupe, isNull);
    });

    test('vetoChange allows uploader to immediately veto pending request', () async {
      // Uploader authority is no longer caller-claimed (round-3 fix):
      // it is attested by a local `createContent` ledger entry for the
      // target CID under this node's identity.
      await ledger.recordAction(
        action: LedgerActionType.createContent,
        contentCid: 'bafy_veto_cid',
      );
      final req = await consensus.proposeChange(
        targetCid: 'bafy_veto_cid',
        field: 'description',
        currentValue: 'Old Desc',
        proposedValue: 'New Desc',
      );

      final vetoed = await consensus.vetoChange(req.id);
      expect(vetoed, isTrue);
      expect(req.status, equals(ChangeRequestStatus.vetoed));

      // Cannot vote on vetoed request
      final vote = await consensus.castVote(
        requestId: req.id,
        approve: true,
        reputation: 100.0,
        daysActive: 100,
      );
      expect(vote, isNull);
    });

    test('fastTrackChange allows uploader to immediately approve if has support', () async {
      // Attest local uploader authority via the ledger (round-3 fix).
      await ledger.recordAction(
        action: LedgerActionType.createContent,
        contentCid: 'bafy_fast_cid',
      );
      final req = await consensus.proposeChange(
        targetCid: 'bafy_fast_cid',
        field: 'year',
        currentValue: 1900,
        proposedValue: 1905,
      );

      // Fast-track with no approvals fails
      expect(await consensus.fastTrackChange(req.id), isFalse);

      // Add one approval
      await consensus.castVote(
        requestId: req.id,
        approve: true,
        reputation: 10.0,
        daysActive: 50,
      );

      // Now fast-track succeeds
      expect(await consensus.fastTrackChange(req.id), isTrue);
      expect(req.status, equals(ChangeRequestStatus.approved));
    });

    test('VoteWeightCalculator correctly calculates weights', () {
      final w1 = VoteWeightCalculator.calculateWeight(
        reputationScore: 100.0,
        daysActive: 365,
        isHuman: true,
      );
      final w2 = VoteWeightCalculator.calculateWeight(
        reputationScore: 100.0,
        daysActive: 365,
        isHuman: false,
      );

      expect(w1, greaterThan(0));
      expect(w1, equals(w2 * 2)); // Human is 1.0, AI is 0.5

      final wZeroRep = VoteWeightCalculator.calculateWeight(
        reputationScore: 0.0,
        daysActive: 365,
        isHuman: true,
      );
      expect(wZeroRep, equals(0.0));
    });

    group('human attestation (biometric-bound isHuman)', () {
      Future<ChangeRequest> propose(ConsensusService svc) => svc.proposeChange(
            targetCid: 'bafy_human_cid_${DateTime.now().microsecondsSinceEpoch}',
            field: 'title',
            currentValue: 'A',
            proposedValue: 'B',
            isAiProposal: true,
          );

      test('isHuman claim fails closed with no attestation clock', () async {
        // No humanAttestationClock wired — a caller-claimed isHuman
        // must mint an unattested (isHuman == false) ballot.
        final req = await propose(consensus);
        final vote = await consensus.castVote(
          requestId: req.id,
          approve: true,
          reputation: 0,
          daysActive: 0,
          isHuman: true,
        );
        expect(vote, isNotNull);
        expect(vote!.isHuman, isFalse);
        expect(req.humanApprovalCount, 0);
      });

      test('recent biometric attestation mints a human ballot', () async {
        final svc = ConsensusService(
          identity,
          ledger,
          humanAttestationClock: () =>
              DateTime.now().subtract(const Duration(seconds: 30)),
        );
        final req = await propose(svc);
        final vote = await svc.castVote(
          requestId: req.id,
          approve: true,
          reputation: 0,
          daysActive: 0,
          isHuman: true,
        );
        expect(vote!.isHuman, isTrue);
        expect(req.humanApprovalCount, 1);
      });

      test('stale attestation (outside window) is not counted', () async {
        final svc = ConsensusService(
          identity,
          ledger,
          humanAttestationClock: () =>
              DateTime.now().subtract(const Duration(hours: 1)),
        );
        final req = await propose(svc);
        final vote = await svc.castVote(
          requestId: req.id,
          approve: true,
          reputation: 0,
          daysActive: 0,
          isHuman: true,
        );
        expect(vote!.isHuman, isFalse);
        expect(req.humanApprovalCount, 0);
      });

      test('a clock reading in the future attests nothing', () async {
        final svc = ConsensusService(
          identity,
          ledger,
          humanAttestationClock: () =>
              DateTime.now().add(const Duration(minutes: 1)),
        );
        final req = await propose(svc);
        final vote = await svc.castVote(
          requestId: req.id,
          approve: true,
          reputation: 0,
          daysActive: 0,
          isHuman: true,
        );
        expect(vote!.isHuman, isFalse);
      });

      test('a throwing clock fails closed', () async {
        final svc = ConsensusService(
          identity,
          ledger,
          humanAttestationClock: () =>
              throw StateError('biometric backend exploded'),
        );
        final req = await propose(svc);
        final vote = await svc.castVote(
          requestId: req.id,
          approve: true,
          reputation: 0,
          daysActive: 0,
          isHuman: true,
        );
        expect(vote!.isHuman, isFalse);
      });

      test('unattested human claims price weight at the AI factor',
          () async {
        // Same ledger/identity, two services differing only in the
        // attestation clock — the attested human ballot must weigh
        // exactly twice the unattested one (A = 1.0 vs 0.5).
        final humanSvc = ConsensusService(
          identity,
          ledger,
          humanAttestationClock: () => DateTime.now(),
        );
        final anonSvc = ConsensusService(identity, ledger);

        final reqHuman = await humanSvc.proposeChange(
          targetCid: 'bafy_hw',
          field: 'title',
          currentValue: 'A',
          proposedValue: 'B',
        );
        final reqAnon = await anonSvc.proposeChange(
          targetCid: 'bafy_aw',
          field: 'title',
          currentValue: 'A',
          proposedValue: 'B',
        );

        final humanVote = await humanSvc.castVote(
          requestId: reqHuman.id,
          approve: true,
          reputation: 0,
          daysActive: 0,
          isHuman: true,
        );
        final anonVote = await anonSvc.castVote(
          requestId: reqAnon.id,
          approve: true,
          reputation: 0,
          daysActive: 0,
          isHuman: true, // claimed, not attested
        );

        expect(humanVote!.isHuman, isTrue);
        expect(anonVote!.isHuman, isFalse);
        expect(humanVote.weight, closeTo(anonVote.weight * 2, 1e-9));
      });
    });

    test('Vote, ChangeRequest, AuditEntry JSON serialization', () {
      final vote = Vote(
        voterKey: Uint8List.fromList([1, 2, 3]),
        weight: 5.5,
        approve: true,
        signature: Uint8List.fromList([4, 5, 6]),
        timestamp: DateTime.now(),
        isHuman: true,
      );
      final voteJson = vote.toJson();
      final roundVote = Vote.fromJson(voteJson);
      expect(roundVote.weight, equals(5.5));
      expect(roundVote.approve, isTrue);

      final changeReq = ChangeRequest(
        id: 'cr_1',
        targetCid: 'bafy_cid',
        field: 'title',
        currentValue: 'A',
        proposedValue: 'B',
        proposerKey: Uint8List.fromList([7, 8]),
        proposerSignature: Uint8List.fromList([9, 10]),
        timestamp: DateTime.now(),
        votes: [vote],
      );
      final reqJson = changeReq.toJson();
      final roundReq = ChangeRequest.fromJson(reqJson);
      expect(roundReq.id, equals('cr_1'));
      expect(roundReq.field, equals('title'));

      final audit = AuditEntry(
        id: 'ae_1',
        changeRequestId: 'cr_1',
        eventType: 'proposed',
        actorKey: Uint8List.fromList([1]),
        timestamp: DateTime.now(),
        signature: Uint8List.fromList([2]),
      );
      final auditJson = audit.toJson();
      final roundAudit = AuditEntry.fromJson(auditJson);
      expect(roundAudit.id, equals('ae_1'));
      expect(roundAudit.eventType, equals('proposed'));
    });
  });
}
