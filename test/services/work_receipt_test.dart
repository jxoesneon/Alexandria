import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/agent/beacon_models.dart';
import 'package:alexandria/services/credits/work_receipt.dart';

void main() {
  group('WorkReceipt (ALX-010 verifier-signed work receipt)', () {
    WorkReceipt buildReceipt({
      String proverPubkey = 'aa11bb22',
      String verifierPubkey = 'cc33dd44',
      String verifierSig = '',
      double amount = 5.0,
    }) {
      return WorkReceipt.issue(
        workType: 'storage',
        proverPubkey: proverPubkey,
        verifierPubkey: verifierPubkey,
        cid: 'bafy_test_cid',
        chunkIndices: const [3, 7],
        challengeNonce: 'deadbeef',
        responseTag: 'cafe'.padLeft(64, '0'),
        workUnits: 4096,
        amount: amount,
        epoch: '2026-02-24',
        expiresAt: 1800000000000,
        evidenceHash: 'ff'.padLeft(64, '0'),
        verifierSig: verifierSig,
      );
    }

    test('canonicalJson is deterministic and sorted by key', () {
      final r1 = buildReceipt();
      final r2 = buildReceipt();
      expect(r1.canonicalJson(), equals(r2.canonicalJson()));

      final decoded = jsonDecode(r1.canonicalJson()) as Map<String, dynamic>;
      final keys = decoded.keys.toList();
      final sorted = List<String>.from(keys)..sort();
      expect(keys, equals(sorted));

      // Optional fields absent -> omitted from the canonical body.
      final bare = WorkReceipt.issue(
        workType: 'verification',
        proverPubkey: 'p',
        verifierPubkey: 'v',
        challengeNonce: 'n',
        responseTag: 't',
        workUnits: 1,
        amount: 1,
        epoch: '2026-01-01',
        expiresAt: 1,
      );
      final bareMap = jsonDecode(bare.canonicalJson()) as Map<String, dynamic>;
      expect(bareMap.containsKey('cid'), isFalse);
      expect(bareMap.containsKey('evidenceHash'), isFalse);
    });

    test('receiptId is a stable sha256 of the canonical body', () {
      final r = buildReceipt();
      expect(r.receiptId, equals(r.computeReceiptId()));
      expect(r.receiptId, matches(RegExp(r'^[0-9a-f]{64}$')));

      // Different body -> different id.
      final other = buildReceipt(amount: 6.0);
      expect(other.receiptId, isNot(equals(r.receiptId)));

      // Signing does not change the id (sig lives outside the body).
      final signed = r.withVerifierSig(base64Encode(List.filled(64, 1)));
      expect(signed.receiptId, equals(r.receiptId));
      expect(signed.verifierSig, isNotEmpty);
    });

    test('verifier signature verifies with a real Ed25519 keypair', () async {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPair();
      final pub = await keyPair.extractPublicKey();
      final pubHex = bytesToHex(pub.bytes);

      final unsigned = buildReceipt(verifierPubkey: pubHex);
      final signature =
          await algorithm.sign(unsigned.signingPayload, keyPair: keyPair);
      final signed = unsigned.withVerifierSig(base64Encode(signature.bytes));

      Future<bool> verifier(
          Uint8List message, Uint8List sig, String publicKey) {
        final pk =
            SimplePublicKey(hexToBytes(publicKey), type: KeyPairType.ed25519);
        return algorithm.verify(message,
            signature: Signature(sig, publicKey: pk));
      }

      expect(await signed.verifyVerifierSignature(verifier), isTrue);
      expect(signed.isVerifierSigned, isTrue);
      expect(signed.isAttestedClaim, isTrue);

      // A signature over a different body must not verify.
      final tampered = buildReceipt(verifierPubkey: pubHex, amount: 999)
          .withVerifierSig(signed.verifierSig);
      expect(await tampered.verifyVerifierSignature(verifier), isFalse);

      // Wrong key -> fails.
      final otherKeyPair = await algorithm.newKeyPair();
      final otherPub = await otherKeyPair.extractPublicKey();
      final misattributed = buildReceipt(
              verifierPubkey: bytesToHex(otherPub.bytes))
          .withVerifierSig(signed.verifierSig);
      expect(await misattributed.verifyVerifierSignature(verifier), isFalse);
    });

    test('unsigned receipt cannot verify and is not an attested claim', () {
      final r = buildReceipt();
      expect(
        r.verifyVerifierSignature((m, s, pk) async => true),
        completion(isFalse),
      );
      expect(r.isAttestedClaim, isFalse);
    });

    test('self-issued receipt is never an attested claim', () {
      final selfSigned = buildReceipt(
        proverPubkey: 'samekey',
        verifierPubkey: 'samekey',
        verifierSig: base64Encode(List.filled(64, 9)),
      );
      expect(selfSigned.isSelfIssued, isTrue);
      expect(selfSigned.isVerifierSigned, isTrue);
      expect(selfSigned.isAttestedClaim, isFalse);
    });

    test('markSpent flags the claim without touching the canonical id', () {
      final r = buildReceipt(verifierSig: base64Encode(List.filled(64, 3)));
      expect(r.spent, isFalse);
      final spent = r.markSpent();
      expect(spent.spent, isTrue);
      // spent is bookkeeping outside the canonical body — the id and the
      // signed payload are unchanged.
      expect(spent.receiptId, equals(r.receiptId));
      expect(spent.canonicalJson(), equals(r.canonicalJson()));
    });

    test('toDbMap/fromDbMap round-trips the work_receipts row shape', () {
      final r = buildReceipt(verifierSig: base64Encode(List.filled(64, 2)));
      final map = r.toDbMap();

      // Keys match AppDatabase.insertWorkReceipt's expected columns.
      for (final key in [
        'receiptId',
        'workType',
        'proverPubkey',
        'verifierPubkey',
        'cid',
        'chunkIndices',
        'challengeNonce',
        'responseTag',
        'workUnits',
        'amount',
        'epoch',
        'expiresAt',
        'evidenceHash',
        'verifierSig',
        'proverSig',
        'spent',
        'createdAt',
      ]) {
        expect(map.containsKey(key), isTrue, reason: 'missing key $key');
      }
      expect(map['chunkIndices'], isA<String>());

      final restored = WorkReceipt.fromDbMap(map);
      expect(restored.receiptId, equals(r.receiptId));
      expect(restored.chunkIndices, equals(r.chunkIndices));
      expect(restored.amount, equals(r.amount));
      expect(restored.verifierSig, equals(r.verifierSig));
    });

    test('expiry and epoch helpers', () {
      final expired = WorkReceipt.issue(
        workType: 'storage',
        proverPubkey: 'p',
        verifierPubkey: 'v',
        challengeNonce: 'n',
        responseTag: 't',
        workUnits: 1,
        amount: 1,
        epoch: '2026-01-01',
        expiresAt: 1000, // long past
      );
      expect(expired.isExpired(), isTrue);

      expect(WorkReceipt.epochFor(DateTime.utc(2026, 2, 4, 23, 59)),
          equals('2026-02-04'));
    });
  });
}
