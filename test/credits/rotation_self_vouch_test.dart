// Safety item 3 - rotation self-vouch guard. importIdentity rotation
// replaces the node's key, so a receipt verifier-signed by the RETIRED
// key looked foreign post-rotation and minted attested value. The
// knownLocalPubkeys history resolver extends the self-dealing check
// from "verifier == current key" to "verifier == any key ever held".
// Scaffolding mirrors possession_bound_claim_test.dart.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart'
    hide CreditTransaction, WorkReceipt;
import 'package:alexandria/services/agent/beacon_models.dart'
    show bytesToHex, hexToBytes;
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/work_receipt.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

class _FakeSecureStorage implements SecureStorageService {
  @override
  String get keyPrefix => '';
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> deleteAll() async => _data.clear();

  @override
  Future<bool> containsKey(String key) async => _data.containsKey(key);
}

void main() {
  final algorithm = Ed25519();
  // Key A - the node's RETIRED identity (verifier of the receipt).
  late SimpleKeyPair keyA;
  late String pubA;
  // Key B - the node's CURRENT identity post-rotation (the prover).
  late SimpleKeyPair keyB;
  late String pubB;
  // Key C - a genuinely foreign verifier.
  late SimpleKeyPair keyC;
  late String pubC;

  late AppDatabase db;

  /// Production-equivalent Ed25519 oracle (mirrors the provider wiring).
  Future<bool> receiptVerifier(
      Uint8List message, Uint8List sig, String publicKeyHex) async {
    try {
      final pk =
          SimplePublicKey(hexToBytes(publicKeyHex), type: KeyPairType.ed25519);
      return await algorithm.verify(message,
          signature: Signature(sig, publicKey: pk));
    } catch (_) {
      return false;
    }
  }

  /// Claim preimage signed under the prover key (B).
  Future<String> claimSig(WorkReceipt r) async {
    final preimage = Uint8List.fromList(
        utf8.encode('alexandria:receipt-claim:v${r.v}:${r.receiptId}'));
    final sig = await algorithm.sign(preimage, keyPair: keyB);
    return base64Encode(sig.bytes);
  }

  /// Receipt: prover = B (the current local key), verifier = [verifier]
  /// keypair/pubkey (default A - the retired local key).
  Future<WorkReceipt> signedReceipt({
    String? verifierPubkey,
    SimpleKeyPair? verifierKeyPair,
    double amount = 25.0,
  }) async {
    final unsigned = WorkReceipt.issue(
      workType: 'storage',
      proverPubkey: pubB,
      verifierPubkey: verifierPubkey ?? pubA,
      cid: 'bafy_rotation',
      chunkIndices: const [0],
      challengeNonce: 'ab' * 16,
      responseTag: 'cd' * 32,
      workUnits: 2048,
      amount: amount,
      epoch: WorkReceipt.epochFor(DateTime.now()),
      expiresAt:
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    );
    final sig = await algorithm.sign(unsigned.signingPayload,
        keyPair: verifierKeyPair ?? keyA);
    var signed = unsigned.withVerifierSig(base64Encode(sig.bytes));
    // v3 issuance acknowledgment (ALX-012 §5.8) - counter-signed by
    // the prover of record (B, the current identity).
    if (signed.v >= WorkReceipt.minAckWireVersion) {
      final ack = await algorithm.sign(signed.ackPayload, keyPair: keyB);
      signed = signed.withProverSig(base64Encode(ack.bytes));
    }
    return signed;
  }

  CreditService svcWith({KnownLocalPubkeysResolver? knownLocal}) {
    return CreditService(
      db: db,
      initialBalance: 0.0,
      receiptVerifier: receiptVerifier,
      localProverPubkeyHex: () async => pubB, // the CURRENT identity
      knownLocalPubkeys: knownLocal,
    );
  }

  Future<WorkReceipt> persist(WorkReceipt r) async {
    await db.insertWorkReceipt(r.toDbMap());
    return r;
  }

  setUp(() async {
    keyA = await algorithm.newKeyPair();
    pubA = bytesToHex((await keyA.extractPublicKey()).bytes);
    keyB = await algorithm.newKeyPair();
    pubB = bytesToHex((await keyB.extractPublicKey()).bytes);
    keyC = await algorithm.newKeyPair();
    pubC = bytesToHex((await keyC.extractPublicKey()).bytes);
    db = AppDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  group('rotation self-vouch guard (Safety item 3)', () {
    test(
        'receipt signed by the RETIRED local key is refused when the '
        'history contains it ({A,B})', () async {
      final r = await persist(await signedReceipt());
      final svc = svcWith(knownLocal: () async => {pubA, pubB});
      await svc.ready;
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          0.0,
          reason: 'verifier A is a retired local key — self-issued '
              'value can never mint attested credit post-rotation');
      expect(svc.attestedBalance, 0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse,
          reason: 'a refused claim leaves the row unspent');
    });

    test(
        'the SAME receipt mints when history knows only {B} — this is '
        'exactly why history matters', () async {
      final r = await persist(await signedReceipt());
      final svc = svcWith(knownLocal: () async => {pubB});
      await svc.ready;
      // Without A in the history the retired-key signature passes the
      // current-key check - the pre-fix mint path this guard closes.
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          25.0);
      expect(svc.attestedBalance, 25.0);
    });

    test(
        'null resolver → current-key-only fallback (pre-feature '
        'behavior, claims still work)', () async {
      final r = await persist(await signedReceipt());
      final svc = svcWith(); // knownLocalPubkeys omitted entirely
      await svc.ready;
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          25.0,
          reason: 'absent history degrades to the REV3 current-key check '
              'rather than failing closed');
    });

    test('empty / null-returning resolver → same fallback', () async {
      for (final resolution in <Set<String>?>[null, <String>{}]) {
        final r = await persist(await signedReceipt());
        final svc = svcWith(knownLocal: () async => resolution);
        await svc.ready;
        expect(
            await svc.claimVerifiedReceipt(r,
                claimSignatureB64: await claimSig(r)),
            25.0,
            reason: 'history resolution $resolution must not break the '
                'honest claim');
      }
    });

    test(
        'a THROWING history resolver degrades fail-open — claims are '
        'not broken by broken history', () async {
      final r = await persist(await signedReceipt());
      final svc = svcWith(knownLocal: () => Future<Set<String>?>.error('boom'));
      await svc.ready;
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          25.0);
    });

    test(
        'a foreign verifier (C) with full history still mints — the '
        'guard refuses only KNOWN-local keys', () async {
      final r = await persist(
          await signedReceipt(verifierPubkey: pubC, verifierKeyPair: keyC));
      final svc = svcWith(knownLocal: () async => {pubA, pubB});
      await svc.ready;
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          25.0);
    });

    test(
        'canonical matching: an UPPERCASE respelling of the retired '
        'key in the receipt still refuses', () async {
      final r = await persist(
          await signedReceipt(verifierPubkey: pubA.toUpperCase()));
      final svc = svcWith(knownLocal: () async => {pubA, pubB});
      await svc.ready;
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          0.0,
          reason: 'samePubkey canonicalizes case variants of the '
              'retired key');
    });

    test(
        'end-to-end: real IdentityService rotated A→B wires the '
        'history resolver exactly like the provider', () async {
      final storage = _FakeSecureStorage();
      final identity = IdentityService(storage);
      addTearDown(identity.dispose);

      // Install A, sign the receipt under A, then rotate to B - the
      // production rotation path is importIdentity.
      await identity.importIdentity(
          Uint8List.fromList(await keyA.extractPrivateKeyBytes()));
      final r = await persist(await signedReceipt());
      await identity.importIdentity(
          Uint8List.fromList(await keyB.extractPrivateKeyBytes()));

      expect(await identity.knownLocalPubkeyHexes(), containsAll({pubA, pubB}));

      final svc = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        localProverPubkeyHex: () async {
          final id = await identity.getIdentity();
          return id == null ? null : bytesToHex(id.publicKey);
        },
        knownLocalPubkeys: identity.knownLocalPubkeyHexes,
      );
      await svc.ready;
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          0.0,
          reason: 'post-rotation, the receipt signed by retired key A '
              'must be refused as self-issued');
      expect(svc.attestedBalance, 0.0);
    });
  });
}
