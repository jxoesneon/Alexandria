import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final honorSystemProvider = Provider((ref) => HonorSystem());

class ValidationVote {
  final String validatorId;
  final String targetCid;
  final int score;
  final int reputation;

  ValidationVote({
    required this.validatorId,
    required this.targetCid,
    required this.score,
    required this.reputation,
  });
}

/// Resolves a validator's reputation from a trusted source (e.g. the
/// honor ledger). Wired by the embedder; when absent, caller-supplied
/// reputation claims are clamped to [HonorSystem.maxClaimedReputation]
/// so a forged INT_MAX claim cannot dominate a tally (round-3 hardening
/// - same class as the HonorBandwidthService credential forgery).
typedef HonorReputationResolver = int Function(String validatorId);

class HonorSystem {
  final List<ValidationVote> _votes = [];

  /// Attestation source for validator reputation. When wired, the
  /// caller's `reputation` argument is IGNORED and the resolved value
  /// is used - a vote can never mint its own weight.
  final HonorReputationResolver? reputationResolver;

  /// Hard bound on self-declared reputation when no resolver is wired.
  /// log10(10010) ≈ 4.0 keeps a bare claim from outweighing an attested
  /// electorate; wire [reputationResolver] for real weighting.
  static const int maxClaimedReputation = 10000;

  HonorSystem({this.reputationResolver});

  void recordVote({
    required String validatorId,
    required String targetCid,
    required int score,
    int reputation = 10,
  }) {
    if (score != -1 && score != 1) throw ArgumentError('Score must be -1 or 1');
    // One ballot per (validatorId, targetCid): without dedup a single
    // validator could stack N identical votes and multiply its weight
    // N-fold - the tally is meant to weight VALIDATORS, not call
    // counts. A re-vote replaces the earlier ballot (validators may
    // change their mind), so the newest score/reputation stands.
    _votes.removeWhere(
      (v) => v.validatorId == validatorId && v.targetCid == targetCid,
    );
    // (round-4 red finding) the ATTESTED value is clamped to the same
    // bound as a bare claim - a compromised/buggy resolver returning
    // -100 would make log(-90) NaN and crash .round(), and a huge
    // return mints unbounded weight. HonorBandwidthService already
    // clamps attested values (maxAttestedHonor); do the same here so a
    // broken attestation source degrades to bounded weight, never
    // NaN/unbounded.
    final resolved = (reputationResolver?.call(validatorId) ?? reputation)
        .clamp(0, maxClaimedReputation);
    _votes.add(ValidationVote(
      validatorId: validatorId,
      targetCid: targetCid,
      score: score,
      reputation: resolved,
    ));
  }

  int computeTrustScore(String targetCid) {
    final cidVotes = _votes.where((v) => v.targetCid == targetCid);
    double total = 0.0;
    for (final v in cidVotes) {
      final weight = log(v.reputation + 10) / ln10;
      total += v.score * weight;
    }
    return total.round();
  }

  int getTrustScore(String cid) => computeTrustScore(cid);

  void validateContent({
    required String targetCid,
    required int score,
    required String validatorId,
    int reputation = 10,
  }) {
    recordVote(
      validatorId: validatorId,
      targetCid: targetCid,
      score: score,
      reputation: reputation,
    );
  }
}
