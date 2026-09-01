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

class HonorSystem {
  final List<ValidationVote> _votes = [];

  void recordVote({
    required String validatorId,
    required String targetCid,
    required int score,
    int reputation = 10,
  }) {
    if (score != -1 && score != 1) throw ArgumentError('Score must be -1 or 1');
    _votes.add(ValidationVote(
      validatorId: validatorId,
      targetCid: targetCid,
      score: score,
      reputation: reputation,
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
