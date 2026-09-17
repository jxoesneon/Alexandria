import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../services/identity_service.dart';

final honorSystemProvider = Provider((ref) {
  final system = HonorSystem();
  system.onVoteRecorded = (vote) async {
    try {
      String signature = '';
      try {
        final identity = await ref.read(identityServiceProvider).getIdentity();
        if (identity != null) {
          final payload = utf8.encode(
              'alexandria:vote:v1:${vote.validatorId}:${vote.targetCid}:${vote.score}');
          final sig = await ref
              .read(identityServiceProvider)
              .sign(Uint8List.fromList(payload));
          signature = base64Encode(sig);
        }
      } catch (_) {
        // An unsigned vote still counts locally - persistence failure of
        // the signature must not drop the ballot.
      }
      await ref.read(databaseProvider).insertHonorValidation(
            validatorId: vote.validatorId,
            targetCid: vote.targetCid,
            score: vote.score,
            signature: signature,
          );
    } catch (_) {
      // Persistence is best-effort: a DB hiccup must not reject the vote.
    }
  };
  return system;
});

/// Resolves once the persisted honor ledger has been replayed into the
/// in-memory tally. Consumers that render trust scores should await this
/// so a vote cast in a previous session is not reported as absent.
final honorSystemReadyProvider = FutureProvider<void>((ref) async {
  final system = ref.watch(honorSystemProvider);
  final db = ref.watch(databaseProvider);

  // Ledger migration: ballots persisted under the legacy 'self'/'me'
  // placeholder ids are not verifiable validators. 'self' rows were
  // self-attestations minted by local integrity checks - not community
  // trust - so they are dropped. 'me' rows were explicit user votes, so
  // they are preserved by remapping onto the real identity key.
  String? localValidatorId;
  try {
    final identity = await ref.read(identityServiceProvider).getIdentity();
    localValidatorId = identity?.publicKeyBase58;
  } catch (_) {
    // No secure storage (tests/headless) - placeholders stay unreplayed.
  }
  await db.deleteHonorValidationsByValidator('self');
  if (localValidatorId != null) {
    await db.remapHonorValidationValidator(
      from: 'me',
      to: localValidatorId,
    );
  }

  final rows = await db.getAllHonorValidations();
  for (final row in rows) {
    // Unattributable placeholder ballots never enter the tally.
    if (row.validatorId == 'me' || row.validatorId == 'self') continue;
    system.restoreVote(
      validatorId: row.validatorId,
      targetCid: row.targetCid,
      score: row.score,
    );
  }
});

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

  /// Write-through persistence hook, wired by [honorSystemProvider].
  /// Invoked after every recorded ballot so the vote survives restart.
  Future<void> Function(ValidationVote vote)? onVoteRecorded;

  /// Replays a persisted ballot without re-invoking the persistence
  /// hook. Same one-ballot-per-validator dedup as [recordVote].
  void restoreVote({
    required String validatorId,
    required String targetCid,
    required int score,
    int reputation = 10,
  }) {
    if (score != -1 && score != 1) return;
    _votes.removeWhere(
      (v) => v.validatorId == validatorId && v.targetCid == targetCid,
    );
    final resolved = (reputationResolver?.call(validatorId) ?? reputation)
        .clamp(0, maxClaimedReputation);
    _votes.add(ValidationVote(
      validatorId: validatorId,
      targetCid: targetCid,
      score: score,
      reputation: resolved,
    ));
  }

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
    final vote = ValidationVote(
      validatorId: validatorId,
      targetCid: targetCid,
      score: score,
      reputation: resolved,
    );
    _votes.add(vote);
    onVoteRecorded?.call(vote);
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
