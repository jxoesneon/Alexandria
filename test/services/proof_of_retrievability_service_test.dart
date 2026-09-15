import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart' show AppDatabase, databaseProvider;
import 'package:alexandria/logic/honor_system.dart';
import 'package:alexandria/services/agent/beacon_models.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/proof_of_retrievability_service.dart';

/// Identity stub whose Ed25519 keypair the test controls, so verifier-signed
/// receipts can be exercised without secure storage.
class _FakeIdentityService implements IdentityService {
  _FakeIdentityService(this.keyPair, this.publicKeyBytes);

  final SimpleKeyPair keyPair;
  final Uint8List publicKeyBytes;

  String get pubkeyHex => bytesToHex(publicKeyBytes);

  @override
  Future<AlexandriaIdentity?> getIdentity() async => AlexandriaIdentity(
        publicKey: publicKeyBytes,
        privateKey: Uint8List.fromList(await keyPair.extractPrivateKeyBytes()),
        createdAt: DateTime(2026, 1, 1),
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
      expect(challenge.challengerPubkey, isNull); // legacy challenge
    });

    test('issueChallenge stamps the verifier pubkey', () {
      final challenge = service.issueChallenge(
        cid: 'bafy_cid',
        totalChunks: 4,
        challengerPubkey: 'verifier_hex_key',
      );
      expect(challenge.challengerPubkey, equals('verifier_hex_key'));
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

    test('pending challenges are bounded: expired purged first, then '
        'oldest evicted (REV4 Safety 5)', () {
      var now = DateTime(2026, 1, 1);
      final c = ProviderContainer(overrides: [
        proofOfRetrievabilityServiceProvider.overrideWith(
            (ref) => ProofOfRetrievabilityService(ref, now: () => now)),
      ]);
      addTearDown(c.dispose);
      final svc = c.read(proofOfRetrievabilityServiceProvider);

      // Flood well past the 256 cap — the map stays bounded.
      final first = svc.issueChallenge(cid: 'c_first', totalChunks: 1);
      for (var i = 0; i < 300; i++) {
        svc.issueChallenge(cid: 'c_$i', totalChunks: 1);
      }
      expect(svc.pendingChallengeCount, 256);
      // Oldest evicted (insertion order); the newest is still live.
      expect(svc.pendingChallenge(first.challengeId), isNull);

      // Expired entries are purged BEFORE eviction: advance the clock
      // past the 5-minute TTL — the next insert purges all 256 stale
      // entries rather than evicting a live challenge.
      now = now.add(const Duration(minutes: 6));
      final fresh = svc.issueChallenge(cid: 'c_fresh', totalChunks: 1);
      expect(svc.pendingChallengeCount, 1);
      expect(svc.pendingChallenge(fresh.challengeId), isNotNull);
    });

    test('toJson serializes challenge and proof', () {
      final challenge =
          service.createChallenge(cid: 'bafy_json', totalChunks: 5);
      final challengeJson = challenge.toJson();
      expect(challengeJson['cid'], equals('bafy_json'));
      expect(challengeJson['nonce'], isA<List<int>>());
      expect(challengeJson.containsKey('challengerPubkey'), isTrue);

      final proof = service.generateProof(
        challenge: challenge,
        chunkData: Uint8List.fromList('data'.codeUnits),
      );
      final proofJson = proof.toJson();
      expect(proofJson['challengeId'], equals(challenge.challengeId));
      expect(proofJson['tag'], isNotEmpty);
    });
  });

  group('PoR verifier-side work receipts (ALX-010/P1)', () {
    late ProviderContainer container;
    late ProofOfRetrievabilityService service;
    late AppDatabase db;
    late _FakeIdentityService identity;
    late CreditService creditService;

    setUp(() async {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPair();
      final pub = await keyPair.extractPublicKey();
      identity = _FakeIdentityService(keyPair, Uint8List.fromList(pub.bytes));

      db = AppDatabase();
      creditService = CreditService(initialBalance: 100.0);
      container = ProviderContainer(overrides: [
        identityServiceProvider.overrideWithValue(identity),
        databaseProvider.overrideWithValue(db),
        creditServiceProvider.overrideWith((_) => creditService),
      ]);
      service = container.read(proofOfRetrievabilityServiceProvider);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Uint8List chunkOf(String s) => Uint8List.fromList(utf8.encode(s));

    test(
        'valid proof for a foreign prover issues a signed claim instrument '
        '— persisted UNSPENT, no local mint', () async {
      final chunk = chunkOf('cross-verified retrievable payload');
      final challenge = service.issueChallenge(
        cid: 'bafy_receipt',
        totalChunks: 4,
        challengerPubkey: identity.pubkeyHex, // local verifier key
      );
      final proof =
          service.generateProof(challenge: challenge, chunkData: chunk);
      final before = creditService.balance;

      final result = await service.verifyAndIssueReceipt(
        proof: proof,
        expectedChunkData: chunk,
        proverPeerId: 'peer_remote_prover',
        proverPubkey: 'foreign_prover_pubkey_hex',
      );

      expect(result.valid, isTrue);
      final receipt = result.receipt!;
      expect(receipt.workType, 'storage');
      expect(receipt.cid, 'bafy_receipt');
      expect(receipt.verifierPubkey, identity.pubkeyHex);
      expect(receipt.proverPubkey, 'foreign_prover_pubkey_hex');
      expect(receipt.responseTag, proof.tag);
      expect(receipt.challengeNonce, bytesToHex(challenge.nonce));
      expect(receipt.verifierSig, isNotEmpty);
      expect(receipt.isSelfIssued, isFalse);
      // Artifact-level: a valid attested claim FOR THE PROVER — but this
      // node must neither mint it nor burn it.
      expect(receipt.isAttestedClaim, isTrue);
      expect(receipt.spent, isFalse);
      // workUnits records exactly the proven chunk bytes — never an
      // extrapolation over sibling chunks.
      expect(receipt.workUnits, chunk.length.toDouble());
      expect(receipt.amount, greaterThan(0));

      // Signature really verifies under the verifier key.
      final ok = await receipt.verifyVerifierSignature(
          (message, sig, publicKey) async {
        final pk =
            SimplePublicKey(hexToBytes(publicKey), type: KeyPairType.ed25519);
        return Ed25519()
            .verify(message, signature: Signature(sig, publicKey: pk));
      });
      expect(ok, isTrue);

      // Persisted UNSPENT — the claim instrument stays live for the prover.
      final row = await db.getWorkReceipt(receipt.receiptId);
      expect(row, isNotNull);
      expect(row!['spent'], isFalse);
      expect(row['verifierSig'], receipt.verifierSig);

      // No local mint: the verifier does not pay itself for the prover's
      // work. The value belongs to whoever holds the prover key.
      expect(creditService.balance, equals(before));
    });

    test(
        'legacy challenge verified for a foreign prover is locally signed '
        'yet still mints nothing locally', () async {
      // createChallenge leaves challengerPubkey null → the verifier key
      // falls back to the LOCAL identity key, so the receipt is signed by
      // us. Naming a foreign prover must not pay this node (the old
      // exploit minted 3x locally and burned the receipt).
      final chunk = chunkOf('legacy verified payload');
      final challenge =
          service.createChallenge(cid: 'bafy_legacy_foreign', totalChunks: 1);
      final proof =
          service.generateProof(challenge: challenge, chunkData: chunk);
      final before = creditService.balance;

      final result = await service.verifyAndIssueReceipt(
        proof: proof,
        expectedChunkData: chunk,
        proverPeerId: 'peer_remote',
        proverPubkey: 'foreign_prover_hex',
      );

      expect(result.valid, isTrue);
      final receipt = result.receipt!;
      expect(receipt.verifierPubkey, identity.pubkeyHex); // fell back local
      expect(receipt.verifierSig, isNotEmpty); // locally signed
      // A locally-signed receipt can never carry attestation weight for a
      // local mint: verifier must be FOREIGN to the claiming node. Here
      // nothing is minted at all — the receipt is the prover's instrument.
      expect(receipt.spent, isFalse);
      expect(creditService.balance, equals(before));
      final row = await db.getWorkReceipt(receipt.receiptId);
      expect(row!['spent'], isFalse);
    });

    test(
        'verifyProof mints synchronously at 1.0x even when proverPeerId '
        'names a foreign node', () async {
      final chunk = chunkOf('self-check bytes held locally');
      // Even when the challenge carries the local verifier key — so the
      // async receipt is locally SIGNED naming 'anything_but_self' — the
      // caller-controlled peer id can never unlock attestation weight.
      final challenge = service.issueChallenge(
        cid: 'bafy_sync_mint',
        totalChunks: 1,
        challengerPubkey: identity.pubkeyHex,
      );
      final proof =
          service.generateProof(challenge: challenge, chunkData: chunk);
      final before = creditService.balance;

      final ok = service.verifyProof(
        proof: proof,
        expectedChunkData: chunk,
        proverPeerId: 'anything_but_self',
      );

      expect(ok, isTrue);
      // The award lands before verifyProof returns (no stale balance) and
      // at unattested weight: the tiny chunk clamps to the 0.1 floor —
      // NOT 0.3, which a 3x attested rarity weight would have paid.
      expect(creditService.balance, closeTo(before + 0.1, 1e-9));
    });

    test('verifyProof unsigned legacy path also mints only 1.0x', () {
      final chunk = chunkOf('legacy self-check bytes');
      final challenge =
          service.createChallenge(cid: 'bafy_sync_legacy', totalChunks: 1);
      final proof =
          service.generateProof(challenge: challenge, chunkData: chunk);
      final before = creditService.balance;

      final ok = service.verifyProof(
        proof: proof,
        expectedChunkData: chunk,
        proverPeerId: 'foreign_but_unsigned',
      );

      expect(ok, isTrue);
      expect(creditService.balance, closeTo(before + 0.1, 1e-9));
    });

    test('forged tag yields no receipt and no mint', () async {
      final chunk = chunkOf('real bytes');
      final forged = chunkOf('forged bytes');
      final challenge = service.issueChallenge(
        cid: 'bafy_forged_receipt',
        totalChunks: 2,
        challengerPubkey: identity.pubkeyHex,
      );
      final forgedProof =
          service.generateProof(challenge: challenge, chunkData: forged);
      final before = creditService.balance;

      final result = await service.verifyAndIssueReceipt(
        proof: forgedProof,
        expectedChunkData: chunk,
        proverPeerId: 'peer_bad',
        proverPubkey: 'foreign_prover',
      );

      expect(result.valid, isFalse);
      expect(result.receipt, isNull);
      expect(creditService.balance, equals(before));
    });

    test('self-issued challenge produces a receipt marked unattested',
        () async {
      final chunk = chunkOf('self-proved payload');
      final challenge = service.issueChallenge(
        cid: 'bafy_self',
        totalChunks: 1,
        challengerPubkey: identity.pubkeyHex,
      );
      final proof =
          service.generateProof(challenge: challenge, chunkData: chunk);

      // challenger == prover == local identity → self-PoR loop.
      final before = creditService.balance;
      final result = await service.verifyAndIssueReceipt(
        proof: proof,
        expectedChunkData: chunk,
        proverPeerId: 'self',
        proverPubkey: identity.pubkeyHex,
      );

      expect(result.valid, isTrue); // integrity check is honest
      final receipt = result.receipt!;
      expect(receipt.isSelfIssued, isTrue);
      expect(receipt.isAttestedClaim, isFalse);
      expect(receipt.verifierSig, isNotEmpty);

      // The local node IS the prover: minted locally at 1.0x and the
      // receipt is consumed — spent in memory and in the database row.
      expect(receipt.spent, isTrue);
      expect(creditService.balance, greaterThan(before));
      final row = await db.getWorkReceipt(receipt.receiptId);
      expect(row!['spent'], isTrue);
    });

    test('case-variant prover_pubkey spelling the local key still mints '
        'the local reward (canonical compare, not stranded)', () async {
      // The MCP tool surface can deliver prover_pubkey in any hex case —
      // a syntactic `==` against the node identity would strand the
      // storage reward as an unclaimable foreign-prover instrument.
      final chunk = chunkOf('local bytes proven via MCP-issued proof');
      final challenge = service.issueChallenge(
        cid: 'bafy_case_prover',
        totalChunks: 1,
        challengerPubkey: identity.pubkeyHex,
      );
      final proof =
          service.generateProof(challenge: challenge, chunkData: chunk);
      final before = creditService.balance;

      final result = await service.verifyAndIssueReceipt(
        proof: proof,
        expectedChunkData: chunk,
        proverPeerId: 'mcp_agent',
        proverPubkey: identity.pubkeyHex.toUpperCase(),
      );

      expect(result.valid, isTrue);
      final receipt = result.receipt!;
      expect(receipt.proverPubkey, identity.pubkeyHex.toUpperCase());
      // Recognized as the local prover: minted at 1.0x and spent —
      // NOT persisted unspent as someone else's claim instrument.
      expect(receipt.spent, isTrue);
      expect(creditService.balance, greaterThan(before));
      final row = await db.getWorkReceipt(receipt.receiptId);
      expect(row!['spent'], isTrue);
    });

    test('unsigned receipt when no identity can sign for the verifier key',
        () async {
      // Challenger is a FOREIGN key the local identity cannot sign as.
      final chunk = chunkOf('payload');
      final challenge = service.issueChallenge(
        cid: 'bafy_foreign_verifier',
        totalChunks: 1,
        challengerPubkey: 'some_other_verifier_key_hex',
      );
      final proof =
          service.generateProof(challenge: challenge, chunkData: chunk);

      final before = creditService.balance;
      final result = await service.verifyAndIssueReceipt(
        proof: proof,
        expectedChunkData: chunk,
        proverPeerId: 'peer_remote',
        proverPubkey: 'foreign_prover_key',
      );

      expect(result.valid, isTrue);
      final receipt = result.receipt!;
      expect(receipt.verifierSig, isEmpty);
      expect(receipt.isAttestedClaim, isFalse);
      // Foreign prover → no local mint, claim instrument stays unspent.
      expect(receipt.spent, isFalse);
      expect(creditService.balance, equals(before));
    });

    test('unknown and consumed challenges are rejected by issuance path',
        () async {
      final unknown = await service.verifyAndIssueReceipt(
        proof: PoRProof(
            challengeId: 'nope', tag: 'x', timestamp: DateTime.now()),
        expectedChunkData: chunkOf('x'),
        proverPeerId: 'peer',
      );
      expect(unknown.valid, isFalse);

      // Consume a challenge once — replay is rejected (expired/or consumed
      // challenges share the same _validateProof rejection path).
      final chunk = chunkOf('replay payload');
      final challenge = service.issueChallenge(
          cid: 'bafy_replay', totalChunks: 1, challengerPubkey: 'v');
      final proof =
          service.generateProof(challenge: challenge, chunkData: chunk);
      final first = await service.verifyAndIssueReceipt(
        proof: proof,
        expectedChunkData: chunk,
        proverPeerId: 'peer',
      );
      expect(first.valid, isTrue);
      final replay = await service.verifyAndIssueReceipt(
        proof: proof,
        expectedChunkData: chunk,
        proverPeerId: 'peer',
      );
      expect(replay.valid, isFalse);
      expect(replay.receipt, isNull);
    });
  });
}
