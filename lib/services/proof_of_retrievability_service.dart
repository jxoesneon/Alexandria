import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../logic/honor_system.dart';

final proofOfRetrievabilityServiceProvider = Provider((ref) => ProofOfRetrievabilityService(ref));

class PoRChallenge {
  final String challengeId;
  final String cid;
  final int chunkIndex;
  final Uint8List nonce;
  final DateTime timestamp;

  PoRChallenge({
    required this.challengeId,
    required this.cid,
    required this.chunkIndex,
    required this.nonce,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'challengeId': challengeId,
    'cid': cid,
    'chunkIndex': chunkIndex,
    'nonce': nonce.toList(),
    'timestamp': timestamp.toIso8601String(),
  };
}

class PoRProof {
  final String challengeId;
  final String tag;
  final DateTime timestamp;

  PoRProof({
    required this.challengeId,
    required this.tag,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'challengeId': challengeId,
    'tag': tag,
    'timestamp': timestamp.toIso8601String(),
  };
}

class ProofOfRetrievabilityService {
  final Ref _ref;
  final Map<String, PoRChallenge> _pendingChallenges = {};

  ProofOfRetrievabilityService(this._ref);

  PoRChallenge createChallenge({
    required String cid,
    required int totalChunks,
  }) {
    if (totalChunks <= 0) throw ArgumentError('totalChunks must be positive');
    final rnd = Random.secure();
    final chunkIndex = rnd.nextInt(totalChunks);
    final nonce = Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256)));
    final challengeId = sha256.convert(nonce).toString().substring(0, 16);

    final challenge = PoRChallenge(
      challengeId: challengeId,
      cid: cid,
      chunkIndex: chunkIndex,
      nonce: nonce,
      timestamp: DateTime.now(),
    );

    _pendingChallenges[challengeId] = challenge;
    return challenge;
  }

  PoRProof generateProof({
    required PoRChallenge challenge,
    required Uint8List chunkData,
  }) {
    final hmac = Hmac(sha256, challenge.nonce);
    final digest = hmac.convert(chunkData);
    return PoRProof(
      challengeId: challenge.challengeId,
      tag: digest.toString(),
      timestamp: DateTime.now(),
    );
  }

  bool verifyProof({
    required PoRProof proof,
    required Uint8List expectedChunkData,
    required String proverPeerId,
  }) {
    final challenge = _pendingChallenges[proof.challengeId];
    if (challenge == null) return false;

    // Challenge expiry (5 minutes)
    if (DateTime.now().difference(challenge.timestamp).inMinutes > 5) {
      _pendingChallenges.remove(proof.challengeId);
      return false;
    }

    final hmac = Hmac(sha256, challenge.nonce);
    final expectedTag = hmac.convert(expectedChunkData).toString();

    final isValid = expectedTag == proof.tag;
    _pendingChallenges.remove(proof.challengeId);

    if (isValid) {
      final honorSystem = _ref.read(honorSystemProvider);
      honorSystem.recordVote(
        validatorId: proverPeerId,
        targetCid: challenge.cid,
        score: 1,
        reputation: 20,
      );
    }

    return isValid;
  }
}
