import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/proof_of_retrievability_service.dart';

void main() {
  group('ProofOfRetrievabilityService Tests', () {
    late ProviderContainer container;
    late ProofOfRetrievabilityService porService;

    setUp(() {
      container = ProviderContainer();
      porService = container.read(proofOfRetrievabilityServiceProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('generates challenge and verifies authentic proof tag', () {
      final chunkData = Uint8List.fromList('Preserved Block Data Chunk 42'.codeUnits);
      final challenge = porService.createChallenge(cid: 'bafy_por_target', totalChunks: 100);

      expect(challenge.challengeId.isNotEmpty, isTrue);
      expect(challenge.nonce.length, equals(32));

      final proof = porService.generateProof(challenge: challenge, chunkData: chunkData);
      expect(proof.tag.isNotEmpty, isTrue);

      final verified = porService.verifyProof(
        proof: proof,
        expectedChunkData: chunkData,
        proverPeerId: 'peer_honest_librarian',
      );

      expect(verified, isTrue);
    });

    test('rejects forged proof tag with tampered chunk data', () {
      final realChunk = Uint8List.fromList('Original Block Bytes'.codeUnits);
      final tamperedChunk = Uint8List.fromList('Forged Corrupted Bytes'.codeUnits);

      final challenge = porService.createChallenge(cid: 'bafy_por_target_2', totalChunks: 50);
      final forgedProof = porService.generateProof(challenge: challenge, chunkData: tamperedChunk);

      final verified = porService.verifyProof(
        proof: forgedProof,
        expectedChunkData: realChunk,
        proverPeerId: 'peer_byzantine',
      );

      expect(verified, isFalse);
    });
  });
}
