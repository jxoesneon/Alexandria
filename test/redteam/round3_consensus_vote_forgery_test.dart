// RED TEAM PoC - ConsensusService.castVote computes vote weight from
// CALLER-SUPPLIED parameters (reputation, daysActive, isHuman):
//
//   lib/services/consensus_service.dart:353-400
//     Future<Vote?> castVote({required double reputation,
//                            required int daysActive, bool isHuman ...})
//     final weight = VoteWeightCalculator.calculateWeight(
//         reputationScore: reputation, ...);   // ← caller's own claim
//
// The service NEVER consults _ledgerService (injected but unused for
// the voter) - a vote can carry arbitrary self-declared weight and the
// signature binds the FORGED weight, so later verification (if it
// ever lands) cannot detect the inflation either: the lie is signed.
// A single forged vote (reputation=1e15 → log2 ≈ 49.8 × T=1 × A=1)
// clears ConsensusConstants.defaultThreshold (10) and resolves ANY
// pending change request to `approved` on the spot - metadata
// consensus capture with zero real reputation.
//
// Second surface: proposeChange accepts a caller-supplied
// `uploaderKey` (line ~303) - the "uploader" of the target content is
// whoever the PROPOSER says. A proposer names THEMSELF uploader, casts
// one vote, and fastTrackChange (line ~446) immediately approves their
// own change AND banks a `mergeAccepted` ledger action (3.0 rep).
// Self-dealing: veto/fast-track authority is self-minted.
//
// Asserts the SECURE expectation: caller-claimed weight/uploader must
// never resolve a change request - weight must come from the ledger
// (server-side reputation), uploaderKey from the content record.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/consensus_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/ledger_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

class _FakeIdentityService extends IdentityService {
  final AlexandriaIdentity _identity;
  _FakeIdentityService(this._identity) : super(SecureStorageService());
  @override
  Future<AlexandriaIdentity?> getIdentity() async => _identity;
  @override
  Future<Uint8List> sign(Uint8List data) async => Uint8List(64);
}

AlexandriaIdentity _identity() => AlexandriaIdentity(
      publicKey: Uint8List.fromList(List.filled(32, 0xAB)),
      privateKey: Uint8List.fromList(List.filled(32, 0xCD)),
      createdAt: DateTime(2020),
    );

void main() {
  late ConsensusService svc;
  late AlexandriaIdentity identity;
  late LedgerService ledger;

  setUp(() {
    identity = _identity();
    ledger = LedgerService(_FakeIdentityService(identity));
    svc = ConsensusService(_FakeIdentityService(identity), ledger);
  });

  test('a vote with caller-forged reputation must not approve a change',
      () async {
    final req = await svc.proposeChange(
      targetCid: 'bafyVictimContent',
      field: 'title',
      currentValue: 'Original Title',
      proposedValue: 'Attacker Title',
    );

    // The caller declares reputation 1e15 - there is no ledger check.
    final vote = await svc.castVote(
      requestId: req.id,
      approve: true,
      reputation: 1e15, // forged - service takes it verbatim
      daysActive: 365,
    );

    expect(vote, isNotNull);
    expect(req.status, isNot(ChangeRequestStatus.approved),
        reason: 'a single self-weighted vote approved the change request '
            '(weight=${req.approvalWeight}) — castVote trusts the '
            'caller\'s reputation parameter instead of deriving weight '
            'from the ledger. Metadata consensus is capturable by any '
            'caller.');
  });

  test(
      'uploader fast-track must not be self-minted via a claimed '
      'uploaderKey', () async {
    // The proposer claims THEY are the uploader of the target content -
    // uploaderKey is a free caller parameter, never checked against the
    // content's actual uploader record.
    final req = await svc.proposeChange(
      targetCid: 'bafySomeoneElsesContent',
      field: 'license',
      currentValue: 'CC-BY',
      proposedValue: 'public domain (attacker-modified)',
      uploaderKey: identity.publicKey, // self-claimed uploader authority
    );

    await svc.castVote(
      requestId: req.id,
      approve: true,
      reputation: 1.0, // tiny honest weight - just needs >0
      daysActive: 365,
    );

    final fastTracked = await svc.fastTrackChange(req.id);
    expect(fastTracked, isFalse,
        reason: 'the proposer named THEMSELF the uploader and fast-tracked '
            'their own change on somebody else\'s content — uploaderKey '
            'is caller-supplied, so veto/fast-track authority is '
            'self-minted (and a mergeAccepted ledger credit was banked).');
    expect(req.status, isNot(ChangeRequestStatus.approved));
  });
}
