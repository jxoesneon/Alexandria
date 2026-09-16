// RED TEAM PoC — Round-4: the round-3 fix made tally getters count only
// votes with `weightAttested = true`. But the attestation marker is a
// PUBLIC constructor parameter and the votes list itself is publicly
// mutable:
//
//   lib/services/consensus_service.dart
//     Vote({..., this.weightAttested = false});   // anyone can set true
//     class ChangeRequest { final List<Vote> votes; }  // mutable field
//
// so `req.votes.add(Vote(weight: 999, weightAttested: true))` mints a
// "ledger-attested" vote with no ledger — approvalWeight jumps over the
// 10.0 threshold and isApproved flips with zero reputation.
//
// Second hole in the same fix: `humanApprovalCount` (the human-review
// quorum for AI proposals) counts `v.isHuman` on ANY vote — including
// weightAttested=false wire votes. Two forged isHuman votes satisfy the
// humanThreshold=2 gate; they need not even carry distinct keys because
// the getter does not dedup. The entire purpose of the AI-proposal human
// quorum is defeated by inert wire ballots.
//
// Third: ChangeRequest.fromJson restores `status` verbatim from wire
// data — a serialized 'approved'/'vetoed' request deserializes with a
// terminal status and `isApproved` honours it without a single vote.
//
// Asserts the SECURE expectations: attestation must be unforgeable by
// construction, unattested ballots must not count as human approvals,
// and deserialized requests must not import a terminal status.
import 'dart:convert';
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

Vote _wireVote({int keyByte = 1, bool isHuman = true}) => Vote(
      voterKey: Uint8List.fromList(List.filled(32, keyByte)),
      weight: 0,
      approve: true,
      signature: Uint8List(64),
      timestamp: DateTime.now(),
      isHuman: isHuman,
      // weightAttested defaults false — as every deserialized vote does.
    );

void main() {
  test('weightAttested is forgeable by construction — tally gate is '
      'self-asserted', () async {
    final svc = ConsensusService(
        _FakeIdentityService(_identity()),
        LedgerService(_FakeIdentityService(_identity())));
    final req = await svc.proposeChange(
      targetCid: 'bafyVictim',
      field: 'title',
      currentValue: 'Real',
      proposedValue: 'Attacker',
    );

    // Attacker holds the request object (proposeChange returns it, and
    // any future sync/ingest path materializes the same mutable list).
    // A single fabricated vote — weightAttested set by the PUBLIC
    // constructor — clears the 10.0 approval threshold with no ledger.
    req.votes.add(Vote(
      voterKey: Uint8List.fromList(List.filled(32, 0xEE)),
      weight: 1000.0,
      approve: true,
      signature: Uint8List(64),
      timestamp: DateTime.now(),
      weightAttested: true, // ← claimed, never derived
    ));

    expect(req.approvalWeight, 0.0,
        reason:
            'a fabricated vote claiming weightAttested counted '
            '${req.approvalWeight} toward the tally — the "attested" '
            'marker is a public constructor bool, so the round-3 weight '
            'fix is forgeable without touching the ledger.');
    expect(req.isApproved, isFalse,
        reason:
            'isApproved returned true on a self-attested vote — metadata '
            'consensus captured by object construction.');
  });

  test('wire votes must not satisfy the AI-proposal human quorum',
      () async {
    final svc = ConsensusService(
        _FakeIdentityService(_identity()),
        LedgerService(_FakeIdentityService(_identity())));
    final req = await svc.proposeChange(
      targetCid: 'bafyAiTarget',
      field: 'license',
      currentValue: 'CC-BY',
      proposedValue: 'proprietary',
      isAiProposal: true,
    );

    // Two forged ballots — same voterKey, isHuman self-asserted — as a
    // wire-deserialized payload would produce. Zero attested weight,
    // but they count toward the human-review quorum.
    req.votes.add(_wireVote(keyByte: 0x11));
    req.votes.add(_wireVote(keyByte: 0x11)); // same key — no dedup

    expect(req.humanApprovalCount, 0,
        reason:
            'two self-asserted isHuman wire ballots (same key!) counted '
            'as ${req.humanApprovalCount} human approvals — the '
            'humanThreshold=${ConsensusConstants.humanThreshold} quorum '
            'for AI proposals counts votes the weight-attestation fix '
            'already classified as untrusted, and does not even dedup '
            'voter keys.');
  });

  test('ChangeRequest.fromJson must not import a terminal status',
      () async {
    // A wire payload claiming the request already resolved 'approved'.
    final forged = {
      'id': 'req-forged',
      'targetCid': 'bafyVictim',
      'field': 'title',
      'currentValue': 'Real',
      'proposedValue': 'Attacker',
      'proposerKey': base64Encode(Uint8List(32)),
      'proposerSignature': base64Encode(Uint8List(64)),
      'timestamp': DateTime.now().toIso8601String(),
      'votes': <dynamic>[],
      'status': 'approved', // ← terminal state asserted off the wire
      'uploaderKey': null,
      'isAiProposal': false,
    };
    final req = ChangeRequest.fromJson(forged);

    expect(req.isApproved, isFalse,
        reason:
            'a deserialized request imported status=approved verbatim — '
            'any ingest path that materializes wire ChangeRequests '
            'accepts a pre-resolved outcome with zero votes. Wire status '
            'must reset to pending like addProposal does for governance.');
  });
}
