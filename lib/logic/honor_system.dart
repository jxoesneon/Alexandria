// import 'package:drift/drift.dart'; // Unused
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';
import '../data/database.dart';
import '../main.dart';

final honorSystemProvider = Provider((ref) => HonorSystem(ref));

class HonorSystem {
  final Ref _ref;

  HonorSystem(this._ref);

  AppDatabase get _db => _ref.read(databaseProvider);

  // Submit a validation (vote/verification)
  Future<void> validateContent({
    required String targetCid,
    required int score, // -1 or 1
    required String validatorId, // Public Key
  }) async {
    if (score != -1 && score != 1) {
      throw ArgumentError('Score must be -1 or 1');
    }

    // Create signature (Mock)
    final signatureData = '$validatorId:$targetCid:$score';
    final signature = sha256.convert(utf8.encode(signatureData)).toString();

    // Ensure user profile exists for validator
    final profile = await _db.getProfileByPublicKey(validatorId);
    if (profile == null) {
      // Create new profile with base reputation
      await _db.insertProfile(
        UserProfilesCompanion.insert(
          publicKey: validatorId,
          reputation: 10, // Base reputation
          lastActive: DateTime.now(),
        ),
      );
    }

    await _db.insertValidation(
      HonorValidationsCompanion.insert(
        validatorId: validatorId,
        targetCid: targetCid,
        score: score,
        timestamp: DateTime.now(),
        signature: signature,
      ),
    );
  }

  // Calculate Trust Score for a CID using Weighted Voting
  Future<int> getTrustScore(String targetCid) async {
    final validations = await _db.getValidationsForCid(targetCid);

    double totalWeightedScore = 0;

    for (var v in validations) {
      // Fetch validator reputation
      final profile = await _db.getProfileByPublicKey(v.validatorId);
      final reputation = profile?.reputation ?? 0;

      // Weight Logic: log10(Reputation + 10)
      // Base rep 10 -> log(20) ~= 1.3
      // Rep 100 -> log(110) ~= 2.0
      // Rep 0 -> log(10) = 1.0 (Minimum weight)
      // Negative reputation could have 0 weight

      double weight = 0;
      if (reputation >= 0) {
        weight = log(reputation + 10) / ln10; // dart:math log is natural ln
      }

      totalWeightedScore += (v.score * weight);
    }

    return totalWeightedScore.round();
  }
}
