// claimVerifiedReceipt — the only path that mints attested (egress-grade)
// value (ALX-010). Locks down the guard chain, the atomic-claim dedup,
// workType mapping, the daily-cap safety floor — and the ALX-012 Safety
// mandate: wire-version floor, receipt-id tamper check, IN-PATH Ed25519
// verification over the domain-separated signing payload, and the
// Review-REV3 possession binding: the prover identity is resolved through
// the injected localProverPubkeyHex resolver (ambient authority — never
// caller-supplied) and proven by claimSignatureB64, an Ed25519 signature
// by the prover key over 'alexandria:receipt-claim:v{v}:{receiptId}'.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart'
    hide CreditTransaction, WorkReceipt;
import 'package:alexandria/services/agent/beacon_models.dart'
    show bytesToHex, hexToBytes;
import 'package:alexandria/services/credits/credit_models.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/work_receipt.dart';

void main() {
  final algorithm = Ed25519();

  // A real Ed25519 verifier identity — the claim path now verifies the
  // signature in-path, so 'c2ln' placeholder sigs no longer suffice.
  late SimpleKeyPair verifierKeyPair;
  late String verifierPubHex;

  // A real Ed25519 LOCAL identity — the possession-bound claim path
  // (REV3) verifies claimSignatureB64 under receipt.proverPubkey, so the
  // prover must be a real key the test controls, and the service's
  // localProverPubkeyHex resolver returns its hex spelling.
  late SimpleKeyPair localKeyPair;
  late String localPubHex;

  /// The ReceiptSignatureVerifier oracle injected into the service —
  /// equivalent to the production wiring of
  /// `IdentityService.verifySignature`.
  Future<bool> receiptVerifier(
      Uint8List message, Uint8List sig, String publicKeyHex) {
    final pk = SimplePublicKey(hexToBytes(publicKeyHex),
        type: KeyPairType.ed25519);
    return algorithm.verify(message, signature: Signature(sig, publicKey: pk));
  }

  /// Signs the REV3 claim preimage — the ASCII bytes of
  /// 'alexandria:receipt-claim:v{r.v}:{r.receiptId}' — under [keyPair]
  /// (default: the local prover key). This is the possession proof
  /// claimVerifiedReceipt now requires in place of a caller-supplied
  /// localPubkeyHex.
  Future<String> claimSig(WorkReceipt r, {SimpleKeyPair? keyPair}) async {
    final preimage = Uint8List.fromList(utf8.encode(
        'alexandria:receipt-claim:v${r.v}:${r.receiptId}'));
    final sig =
        await algorithm.sign(preimage, keyPair: keyPair ?? localKeyPair);
    return base64Encode(sig.bytes);
  }

  /// Issues a receipt and signs its domain-separated [signingPayload]
  /// with [keyPair] (default: the verifier key) — exactly as a verifier
  /// node would. The receipt's own `v` selects the preimage, so a v1
  /// artifact is signed over the bare canonical body and a v2 artifact
  /// over the 'alexandria:receipt:v2:'-prefixed bytes.
  Future<WorkReceipt> signedReceipt({
    int? v,
    String workType = 'storage',
    String proverPubkey = 'prover_key_hex',
    String? verifierPubkey,
    double amount = 25.0,
    int? expiresAt,
    SimpleKeyPair? keyPair,
    // null (default) = sign with [keyPair]; an explicit string attaches
    // it verbatim — '' builds an unsigned artifact, garbage builds a
    // forgery.
    String? verifierSig,
  }) async {
    final unsigned = WorkReceipt.issue(
      v: v ?? WorkReceipt.wireVersion,
      workType: workType,
      proverPubkey: proverPubkey,
      verifierPubkey: verifierPubkey ?? verifierPubHex,
      cid: 'bafy_claim_test',
      chunkIndices: const [0, 1],
      challengeNonce: 'ab' * 16,
      responseTag: 'cd' * 32,
      workUnits: 4096,
      amount: amount,
      epoch: WorkReceipt.epochFor(DateTime.now()),
      expiresAt: expiresAt ??
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    );
    if (verifierSig != null) {
      return unsigned.withVerifierSig(verifierSig);
    }
    final sig = await algorithm.sign(unsigned.signingPayload,
        keyPair: keyPair ?? verifierKeyPair);
    return unsigned.withVerifierSig(base64Encode(sig.bytes));
  }

  group('CreditService.claimVerifiedReceipt (ALX-010 attested mint)', () {
    late AppDatabase db;
    late CreditService svc;

    setUp(() async {
      verifierKeyPair = await algorithm.newKeyPair();
      verifierPubHex = bytesToHex(
          (await verifierKeyPair.extractPublicKey()).bytes);
      localKeyPair = await algorithm.newKeyPair();
      localPubHex =
          bytesToHex((await localKeyPair.extractPublicKey()).bytes);
      db = AppDatabase();
      svc = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        // Ambient identity resolver — the production provider wires this
        // to IdentityService.getIdentity(); here it serves the test key.
        localProverPubkeyHex: () => localPubHex,
      );
      await svc.ready;
    });

    tearDown(() async {
      await db.close();
    });

    Future<WorkReceipt> persist(WorkReceipt r) async {
      await db.insertWorkReceipt(r.toDbMap());
      return r;
    }

    test('foreign verifier-signed receipt mints attested credit', () async {
      final r = await persist(await signedReceipt(
          proverPubkey: localPubHex, amount: 25.0));
      final minted = await svc.claimVerifiedReceipt(r,
          claimSignatureB64: await claimSig(r));

      expect(minted, 25.0);
      expect(svc.balance, 25.0);
      expect(svc.attestedBalance, 25.0);
      expect(svc.unattestedBalance, 0.0);
      expect(svc.totalStorageEarned, 25.0);

      final tx = svc.transactions
          .firstWhere((t) => t.referenceId == r.receiptId);
      expect(tx.isAttested, isTrue);
      expect(tx.type, CreditType.storageReward);

      // The receipt row is consumed.
      final row = await db.getWorkReceipt(r.receiptId);
      expect(row!['spent'], isTrue);
    });

    test('replay loses the CAS — a receipt can only ever mint once',
        () async {
      final r = await persist(
          await signedReceipt(proverPubkey: localPubHex, amount: 25.0));
      final sig = await claimSig(r);
      expect(await svc.claimVerifiedReceipt(r, claimSignatureB64: sig),
          25.0);
      // Second claim — even replaying the SAME valid claim signature:
      // CAS loses (row already spent) -> 0, nothing mints.
      expect(await svc.claimVerifiedReceipt(r, claimSignatureB64: sig),
          0.0);
      expect(await svc.claimVerifiedReceipt(r.markSpent(),
          claimSignatureB64: sig), 0.0);
      expect(svc.attestedBalance, 25.0);
      expect(svc.balance, 25.0);
    });

    test('receipt the local node signed itself never mints attested value',
        () async {
      final r = await persist(await signedReceipt(
        proverPubkey: 'other_prover',
        verifierPubkey: localPubHex,
      ));
      expect(
        await svc.claimVerifiedReceipt(r,
            claimSignatureB64: await claimSig(r)),
        0.0,
      );
      expect(svc.attestedBalance, 0.0);
      // And the receipt is NOT consumed — it was never claimed.
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('self-issued receipt (prover == verifier) is refused', () async {
      // Signed by the verifier key, but prover == verifier: a
      // self-declaration, refused before verification is even reached.
      final r = await persist(await signedReceipt(
        proverPubkey: verifierPubHex,
      ));
      expect(r.isSelfIssued, isTrue);
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          0.0);
      expect(svc.attestedBalance, 0.0);
    });

    test('receipt naming a FOREIGN prover is refused — claim theft '
        'protection', () async {
      // A held artifact naming prover X is X's claim instrument, not
      // ours: the local node must never mint it (REV1 C3).
      final r = await persist(await signedReceipt(
        proverPubkey: 'foreign_prover',
        amount: 25.0,
      ));
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          0.0);
      expect(svc.attestedBalance, 0.0);
      // Not consumed — it still belongs to the named prover.
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('unsigned receipt is refused', () async {
      final r = await persist(await signedReceipt(
          proverPubkey: localPubHex, verifierSig: ''));
      // verifierSig '' means "don't sign" — the artifact stays unsigned.
      expect(r.isVerifierSigned, isFalse);
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('expired receipt is refused', () async {
      final r = await persist(await signedReceipt(
        proverPubkey: localPubHex,
        expiresAt:
            DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
      ));
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('receipt missing from the ledger is refused', () async {
      // Fully valid and properly signed — but never persisted: the
      // unspent-row requirement refuses it.
      final r = await signedReceipt(proverPubkey: localPubHex);
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          0.0);
      expect(svc.balance, 0.0);
    });

    test('in-memory service has no CAS — claim is refused', () async {
      final mem = CreditService(
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        localProverPubkeyHex: () => localPubHex,
      );
      await mem.ready;
      final r = await signedReceipt(proverPubkey: localPubHex);
      expect(
          await mem.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          0.0);
    });

    test('workType maps to the matching credit type', () async {
      final compute = await persist(await signedReceipt(
          workType: 'compute', proverPubkey: localPubHex, amount: 10.0));
      expect(
          await svc.claimVerifiedReceipt(compute,
              claimSignatureB64: await claimSig(compute)),
          10.0);
      expect(
          svc.transactions
              .firstWhere((t) => t.referenceId == compute.receiptId)
              .type,
          CreditType.computeReward);

      final verify = await persist(await signedReceipt(
          workType: 'verification',
          proverPubkey: localPubHex,
          amount: 10.0));
      expect(
          await svc.claimVerifiedReceipt(verify,
              claimSignatureB64: await claimSig(verify)),
          10.0);
      expect(
          svc.transactions
              .firstWhere((t) => t.referenceId == verify.receiptId)
              .type,
          CreditType.verificationReward);

      expect(svc.totalComputeEarned, 10.0);
      expect(svc.totalVerificationEarned, 10.0);
      expect(svc.attestedBalance, 20.0);
    });

    test('attested mints still respect the daily cap (safety floor)',
        () async {
      // storageReward daily cap is 200 — a 250-credit receipt clamps.
      final r = await persist(
          await signedReceipt(proverPubkey: localPubHex, amount: 250.0));
      final minted = await svc.claimVerifiedReceipt(r,
          claimSignatureB64: await claimSig(r));
      expect(minted, 200.0);
      expect(svc.attestedBalance, 200.0);
      // The receipt is consumed even though the full amount didn't mint —
      // anti-replay: the residual is burned, never re-claimable.
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isTrue);

      // A second receipt the same day finds the cap exhausted: mints
      // nothing, and is still consumed.
      final r2 = await persist(
          await signedReceipt(proverPubkey: localPubHex, amount: 10.0));
      expect(
          await svc.claimVerifiedReceipt(r2,
              claimSignatureB64: await claimSig(r2)),
          0.0);
      expect((await db.getWorkReceipt(r2.receiptId))!['spent'], isTrue);
    });
  });

  group('claimVerifiedReceipt — ALX-012 in-path enforcement', () {
    late AppDatabase db;
    late CreditService svc;

    setUp(() async {
      verifierKeyPair = await algorithm.newKeyPair();
      verifierPubHex = bytesToHex(
          (await verifierKeyPair.extractPublicKey()).bytes);
      localKeyPair = await algorithm.newKeyPair();
      localPubHex =
          bytesToHex((await localKeyPair.extractPublicKey()).bytes);
      db = AppDatabase();
      svc = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        // Ambient identity resolver — the production provider wires this
        // to IdentityService.getIdentity(); here it serves the test key.
        localProverPubkeyHex: () => localPubHex,
      );
      await svc.ready;
    });

    tearDown(() async {
      await db.close();
    });

    test('forged verifierSig (valid base64, wrong key) mints nothing and '
        'leaves the row UNSPENT', () async {
      // The artifact claims the honest verifier's pubkey but was signed
      // by an attacker's key — valid base64, valid 64-byte shape, wrong
      // signature.
      final attacker = await algorithm.newKeyPair();
      final forged = await signedReceipt(
          proverPubkey: localPubHex, amount: 25.0, keyPair: attacker);
      expect(forged.isVerifierSigned, isTrue); // non-empty is NOT proof
      await db.insertWorkReceipt(forged.toDbMap());

      expect(
          await svc.claimVerifiedReceipt(forged,
              claimSignatureB64: await claimSig(forged)),
          0.0);
      expect(svc.balance, 0.0);
      expect(svc.attestedBalance, 0.0);
      // Failed verification runs BEFORE the CAS — the unspent row is
      // never consumed by a forged claim.
      expect((await db.getWorkReceipt(forged.receiptId))!['spent'], isFalse);
    });

    test('garbage verifierSig (64 bytes of noise) is refused unspent',
        () async {
      final noise = base64Encode(Uint8List(64)); // zeros — shape-valid
      final garbage = await signedReceipt(
          proverPubkey: localPubHex, amount: 25.0, verifierSig: noise);
      await db.insertWorkReceipt(garbage.toDbMap());

      expect(
          await svc.claimVerifiedReceipt(garbage,
              claimSignatureB64: await claimSig(garbage)),
          0.0);
      expect((await db.getWorkReceipt(garbage.receiptId))!['spent'],
          isFalse);
    });

    test('a signature over the WRONG domain is refused — v2 forgery from '
        'a bare-canonical signature', () async {
      // Attacker signs the bare canonical JSON (the v1 preimage) but
      // stamps v2 — the domain-separated payload does not match.
      final unsigned = WorkReceipt.issue(
        workType: 'storage',
        proverPubkey: localPubHex,
        verifierPubkey: verifierPubHex,
        challengeNonce: 'ab' * 16,
        responseTag: 'cd' * 32,
        workUnits: 4096,
        amount: 25.0,
        epoch: WorkReceipt.epochFor(DateTime.now()),
        expiresAt:
            DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
      );
      final wrongDomain = await algorithm.sign(
          Uint8List.fromList(utf8.encode(unsigned.canonicalJson())),
          keyPair: verifierKeyPair);
      final forged = unsigned.withVerifierSig(base64Encode(wrongDomain.bytes));
      await db.insertWorkReceipt(forged.toDbMap());

      expect(
          await svc.claimVerifiedReceipt(forged,
              claimSignatureB64: await claimSig(forged)),
          0.0);
      expect((await db.getWorkReceipt(forged.receiptId))!['spent'],
          isFalse);
    });

    test('tampered body (receiptId mismatch) is refused before the store '
        'is touched', () async {
      final honest =
          await signedReceipt(proverPubkey: localPubHex, amount: 25.0);
      // Re-id the artifact: the stored receiptId no longer recomputes
      // from the canonical body.
      final tampered = WorkReceipt.fromDbMap({
        ...honest.toDbMap(),
        'receiptId': 'f' * 64,
      });
      expect(tampered.computeReceiptId(), isNot(equals(tampered.receiptId)));
      // Persist under the claimed id so an unspent row exists.
      await db.insertWorkReceipt(tampered.toDbMap());

      expect(
          await svc.claimVerifiedReceipt(tampered,
              claimSignatureB64: await claimSig(tampered)),
          0.0);
      expect(svc.balance, 0.0);
      expect((await db.getWorkReceipt(tampered.receiptId))!['spent'],
          isFalse);
    });

    test('below-floor receipt (v=0) is refused even with a valid '
        'signature — representable but unclaimable', () async {
      final legacy = await signedReceipt(v: 0, proverPubkey: localPubHex);
      // The signature IS valid under the artifact's own (bare) domain —
      // refusal must come from the claim-time floor, not verification.
      expect(legacy.v, 0);
      expect(legacy.v < CreditService.minClaimableWireVersion, isTrue);
      await db.insertWorkReceipt(legacy.toDbMap());
      final row = await db.getWorkReceipt(legacy.receiptId);
      expect(row, isNotNull, reason: 'below-floor rows are representable');

      expect(
          await svc.claimVerifiedReceipt(legacy,
              claimSignatureB64: await claimSig(legacy)),
          0.0);
      expect(svc.attestedBalance, 0.0);
      expect((await db.getWorkReceipt(legacy.receiptId))!['spent'],
          isFalse);
    });

    test('legacy v1 receipt signed over the bare canonical body still '
        'claims (grace window)', () async {
      final legacy = await signedReceipt(v: 1, proverPubkey: localPubHex);
      expect(legacy.v, 1);
      // Sanity: the v1 preimage really is the bare canonical JSON — a
      // pre-domain build's signature verifies.
      expect(legacy.signingPayload,
          equals(utf8.encode(legacy.canonicalJson())));
      await db.insertWorkReceipt(legacy.toDbMap());

      expect(
          await svc.claimVerifiedReceipt(legacy,
              claimSignatureB64: await claimSig(legacy)),
          25.0);
      expect(svc.attestedBalance, 25.0);
      expect((await db.getWorkReceipt(legacy.receiptId))!['spent'], isTrue);
    });

    test('a service constructed WITHOUT a receiptVerifier fails closed',
        () async {
      final blind = CreditService(
        db: db,
        initialBalance: 0.0,
        localProverPubkeyHex: () => localPubHex,
      );
      await blind.ready;
      final r = await signedReceipt(proverPubkey: localPubHex);
      await db.insertWorkReceipt(r.toDbMap());

      expect(
          await blind.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          0.0);
      expect(blind.attestedBalance, 0.0);
      // Fail-closed also means the row is not consumed.
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });
  });

  group('CreditTransaction.computeHash', () {
    test('emits the full-width sha256 hex (64 chars)', () {
      final hash = CreditTransaction.computeHash(
        id: 'tx_1',
        timestamp: DateTime(2026, 1, 1),
        type: CreditType.storageReward,
        amount: 5.0,
        description: 'full width hash test',
      );
      expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });
}
