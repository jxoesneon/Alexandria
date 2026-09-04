import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/logic/honor_system.dart';
import 'package:alexandria/services/proof_of_retrievability_service.dart';

void main() {
  group('ProofOfRetrievabilityService', () {
    late ProviderContainer container;
    late ProofOfRetrievabilityService service;

    setUp(() {
      container = ProviderContainer();
      service = container.read(proofOfRetrievabilityServiceProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('createChallenge rejects non-positive totalChunks', () {
      expect(
        () => service.createChallenge(cid: 'cid', totalChunks: 0),
        throwsArgumentError,
      );
      expect(
        () => service.createChallenge(cid: 'cid', totalChunks: -1),
        throwsArgumentError,
      );
    });

    test('createChallenge generates a valid challenge', () {
      final challenge =
          service.createChallenge(cid: 'bafy_cid', totalChunks: 50);
      expect(challenge.cid, equals('bafy_cid'));
      expect(challenge.challengeId, isNotEmpty);
      expect(challenge.nonce.length, equals(32));
      expect(challenge.chunkIndex, greaterThanOrEqualTo(0));
      expect(challenge.chunkIndex, lessThan(50));
    });

    test('verifyProof accepts an authentic generated proof and records honor', () {
      final chunk =
          Uint8List.fromList('Authentic retrievable chunk'.codeUnits);
      final challenge =
          service.createChallenge(cid: 'bafy_auth', totalChunks: 10);

      final proof =
          service.generateProof(challenge: challenge, chunkData: chunk);
      expect(proof.challengeId, equals(challenge.challengeId));
      expect(proof.tag, isNotEmpty);

      final valid = service.verifyProof(
        proof: proof,
        expectedChunkData: chunk,
        proverPeerId: 'peer_good',
      );
      expect(valid, isTrue);

      final honor = container.read(honorSystemProvider);
      final trust = honor.computeTrustScore('bafy_auth');
      expect(trust, greaterThan(0));
    });

    test('verifyProof rejects a forged proof with tampered chunk data', () {
      final realChunk =
          Uint8List.fromList('Real chunk bytes'.codeUnits);
      final forgedChunk =
          Uint8List.fromList('Forged chunk bytes'.codeUnits);

      final challenge =
          service.createChallenge(cid: 'bafy_forged', totalChunks: 20);
      final forgedProof = service.generateProof(
        challenge: challenge,
        chunkData: forgedChunk,
      );

      final valid = service.verifyProof(
        proof: forgedProof,
        expectedChunkData: realChunk,
        proverPeerId: 'peer_bad',
      );
      expect(valid, isFalse);
    });

    test('verifyProof rejects an unknown challenge', () {
      final unknownProof = PoRProof(
        challengeId: 'unknown_id',
        tag: 'tag',
        timestamp: DateTime.now(),
      );
      final valid = service.verifyProof(
        proof: unknownProof,
        expectedChunkData: Uint8List(0),
        proverPeerId: 'peer_unknown',
      );
      expect(valid, isFalse);
    });

    test('toJson serializes challenge and proof', () {
      final challenge =
          service.createChallenge(cid: 'bafy_json', totalChunks: 5);
      final challengeJson = challenge.toJson();
      expect(challengeJson['cid'], equals('bafy_json'));
      expect(challengeJson['nonce'], isA<List<int>>());

      final proof = service.generateProof(
        challenge: challenge,
        chunkData: Uint8List.fromList('data'.codeUnits),
      );
      final proofJson = proof.toJson();
      expect(proofJson['challengeId'], equals(challenge.challengeId));
      expect(proofJson['tag'], isNotEmpty);
    });
  });
}
