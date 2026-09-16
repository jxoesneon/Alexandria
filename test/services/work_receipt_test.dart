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

    test('wire format v3: integer milli-units, no floats in canonical body',
        () {
      final r = buildReceipt(amount: 5.0);
      final body = r.unsignedBody();

      // Scheme version pins the canonicalization contract — and it is the
      // receipt's OWN v, not just the build constant (ALX-012).
      expect(body['v'], equals(WorkReceipt.wireVersion));
      expect(body['v'], equals(3));
      expect(r.v, equals(3));

      // Monetary fields travel as INTEGER milli-units so a JS verifier
      // recomputing the receipt id via RFC 8785 JCS never diverges on
      // '1.0' vs '1' number formatting.
      expect(body.containsKey('amount'), isFalse);
      expect(body.containsKey('workUnits'), isFalse);
      expect(body['amountMilli'], isA<int>());
      expect(body['workUnitsMilli'], isA<int>());
      expect(body['amountMilli'], equals(5000));
      expect(body['workUnitsMilli'], equals(4096000));

      // The canonical JSON itself must carry no fractional component.
      final json = r.canonicalJson();
      expect(json, contains('"v":3'));
      expect(json, contains('"amountMilli":5000'));
      expect(json, isNot(contains('.')));

      // Display accessors stay doubles.
      expect(r.amount, equals(5.0));
      expect(r.workUnits, equals(4096.0));

      // Rounding: fractional milli-units snap to the nearest integer.
      final odd = buildReceipt(amount: 1.9999);
      expect(odd.amountMilli, equals(2000)); // 1999.9 rounds up
    });

    test('toJson exposes the wire fields for foreign verifiers', () {
      final json = buildReceipt(amount: 5.0).toJson();
      expect(json['v'], equals(3));
      expect(json['amount_milli'], equals(5000));
      expect(json['work_units_milli'], equals(4096000));
      // Display doubles remain alongside.
      expect(json['amount'], equals(5.0));
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

    test('v3 signing payload is domain-separated (ALX-012)', () {
      final r = buildReceipt();
      // v>=2 preimage: 'alexandria:receipt:vN:' + canonical JSON.
      final expected =
          utf8.encode('alexandria:receipt:v3:${r.canonicalJson()}');
      expect(r.signingPayload, equals(expected));
      // And it is provably NOT the bare canonical body.
      expect(r.signingPayload, isNot(equals(utf8.encode(r.canonicalJson()))));
    });

    test('legacy v1 payload is the bare canonical body (grace domain)', () {
      final legacy = WorkReceipt.issue(
        v: 1,
        workType: 'storage',
        proverPubkey: 'aa11bb22',
        verifierPubkey: 'cc33dd44',
        challengeNonce: 'deadbeef',
        responseTag: 'cafe'.padLeft(64, '0'),
        workUnits: 4096,
        amount: 5.0,
        epoch: '2026-02-24',
        expiresAt: 1800000000000,
      );
      expect(legacy.v, equals(1));
      // The receipt's declared v travels inside the canonical body.
      expect(legacy.canonicalJson(), contains('"v":1'));
      // Legacy domain: the preimage is the bare canonical JSON, exactly
      // what pre-domain builds signed.
      expect(legacy.signingPayload,
          equals(utf8.encode(legacy.canonicalJson())));
      // Different v over identical work terms => different canonical body
      // => different receipt id (domain separation is structural).
      final modern = buildReceipt();
      expect(legacy.receiptId, isNot(equals(modern.receiptId)));
    });

    test('a v1 signature verifies under the legacy bare domain', () async {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPair();
      final pub = await keyPair.extractPublicKey();
      final pubHex = bytesToHex(pub.bytes);

      final legacy = WorkReceipt.issue(
        v: 1,
        workType: 'storage',
        proverPubkey: 'prover_hex',
        verifierPubkey: pubHex,
        challengeNonce: 'deadbeef',
        responseTag: 'cafe'.padLeft(64, '0'),
        workUnits: 4096,
        amount: 5.0,
        epoch: '2026-02-24',
        expiresAt: 1800000000000,
      );
      // Signed exactly as a pre-domain build would have: over the bare
      // canonical JSON bytes (== legacy signingPayload).
      final sig = await algorithm.sign(
          Uint8List.fromList(utf8.encode(legacy.canonicalJson())),
          keyPair: keyPair);
      final signed = legacy.withVerifierSig(base64Encode(sig.bytes));

      Future<bool> verifier(
          Uint8List message, Uint8List sig, String publicKey) {
        final pk =
            SimplePublicKey(hexToBytes(publicKey), type: KeyPairType.ed25519);
        return algorithm.verify(message,
            signature: Signature(sig, publicKey: pk));
      }

      expect(await signed.verifyVerifierSignature(verifier), isTrue);

      // But the same signature bytes attached to a v2 artifact (which
      // verifies under the prefixed domain) must NOT verify.
      final modern = buildReceipt(verifierPubkey: pubHex)
          .withVerifierSig(signed.verifierSig);
      expect(await modern.verifyVerifierSignature(verifier), isFalse);
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
        'v',
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
      expect(map['v'], equals(3));

      final restored = WorkReceipt.fromDbMap(map);
      expect(restored.receiptId, equals(r.receiptId));
      expect(restored.v, equals(3));
      expect(restored.chunkIndices, equals(r.chunkIndices));
      expect(restored.amount, equals(r.amount));
      expect(restored.verifierSig, equals(r.verifierSig));

      // Parse tolerance: a row predating the v column hydrates as the
      // legacy scheme — representable, and still verifiable under the
      // bare-canonical domain.
      final legacyMap = Map<String, dynamic>.from(map)..remove('v');
      expect(WorkReceipt.fromDbMap(legacyMap).v, equals(1));
      // A foreign artifact with an unknown future version is likewise
      // representable: its declared v round-trips untouched.
      final foreignMap = Map<String, dynamic>.from(map)..['v'] = 7;
      expect(WorkReceipt.fromDbMap(foreignMap).v, equals(7));
    });

    test('samePubkey: two-tier canonical identity compare', () {
      // Tier 1 — exact match after trimming (never case-folded).
      expect(WorkReceipt.samePubkey('abc123', 'abc123'), isTrue);
      expect(WorkReceipt.samePubkey('  abc123  ', 'abc123'), isTrue);

      // Tier 2 — hex case variants and interior space padding decode to
      // identical key bytes (the strict decoder accepts both spellings).
      expect(WorkReceipt.samePubkey('AB12cd', 'ab12cd'), isTrue);
      expect(WorkReceipt.samePubkey('ab12 cd34', 'ab12cd34'), isTrue);

      // The tier-1 false-positive class: distinct NON-hex identities
      // that differ only by case must NOT collapse ('AbC' is odd-length
      // anyway; use even-length non-hex to isolate the case-fold).
      expect(WorkReceipt.samePubkey('zzZZ', 'ZZzz'), isFalse);
      expect(WorkReceipt.samePubkey('peer_AB', 'peer_ab'), isFalse);

      // Non-hex respellings the old int.parse decoder accepted — '+',
      // tab, NBSP, trailing newline — satisfy NEITHER tier.
      expect(WorkReceipt.samePubkey('+5ab', '05ab'), isFalse);
      expect(WorkReceipt.samePubkey('\t5ab', '05ab'), isFalse);
      expect(WorkReceipt.samePubkey('\u{A0}5ab', '05ab'), isFalse);
      expect(WorkReceipt.samePubkey('5\nab', '05ab'), isFalse);

      // Different hex bytes are not the same key; absent keys never bind.
      expect(WorkReceipt.samePubkey('ab12', 'ab13'), isFalse);
      expect(WorkReceipt.samePubkey('ab12', 'ab12cd'), isFalse);
      expect(WorkReceipt.samePubkey('', ''), isFalse);
      expect(WorkReceipt.samePubkey('   ', 'ab12'), isFalse);
      expect(WorkReceipt.samePubkey('ab12', ''), isFalse);
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
