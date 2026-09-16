// ALX-012 residual-closure coverage:
//  1. Signed WorkReceipt UPGRADE — an unsigned first insert must not
//     permanently block a later signed redelivery carrying the same
//     receiptId. CreditService.ingestWorkReceipt verifies each incoming
//     signature in-path before persisting it, never overwrites a stored
//     signature (first-signed-wins, like first-insert-wins for the
//     body), and never touches `spent`.
//  2. Remote-claim FRESHNESS — claimVerifiedReceipt accepts
//     (verifierNonce, expiryMillis) TOGETHER; the possession signature
//     must cover the extended preimage
//     'alexandria:receipt-claim:v{v}:{receiptId}:{nonce}:{expiry}'.
//     Missing halves, stale expiry, a mismatched nonce and replay all
//     fail closed, leaving the row unspent for the true prover.
//  3. Prover-key-scoped attested balances — attested mints are recorded
//     under `attested_pubkey`; only value scoped to CURRENTLY-HELD keys
//     (plus the unscoped legacy bucket) backs an egress. A rotated-out
//     key's minted value stops counting.
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

void main() {
  final algorithm = Ed25519();

  late SimpleKeyPair verifierKeyPair;
  late String verifierPubHex;
  late SimpleKeyPair proverKeyPairA;
  late String proverPubHexA;
  late SimpleKeyPair proverKeyPairB;
  late String proverPubHexB;

  Future<bool> receiptVerifier(
      Uint8List message, Uint8List sig, String publicKeyHex) {
    final pk = SimplePublicKey(hexToBytes(publicKeyHex),
        type: KeyPairType.ed25519);
    return algorithm.verify(message, signature: Signature(sig, publicKey: pk));
  }

  /// An UNSIGNED artifact — what a verifier emits before signing (or a
  /// redelivery that lost its signatures in transit).
  WorkReceipt unsignedReceipt({
    int v = 3,
    String? proverPubkey,
    double amount = 25.0,
    int? expiresAt,
    String nonce = 'ab',
  }) {
    return WorkReceipt.issue(
      v: v,
      workType: 'storage',
      proverPubkey: proverPubkey ?? proverPubHexA,
      verifierPubkey: verifierPubHex,
      cid: 'bafy_upgrade_test',
      chunkIndices: const [0, 1],
      challengeNonce: nonce * 16,
      responseTag: 'cd' * 32,
      workUnits: 4096,
      amount: amount,
      epoch: WorkReceipt.epochFor(DateTime.now()),
      expiresAt: expiresAt ??
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    );
  }

  /// Attaches a real verifier signature (Ed25519 over [signingPayload]).
  Future<WorkReceipt> withVerifierSig(WorkReceipt r) async {
    final sig =
        await algorithm.sign(r.signingPayload, keyPair: verifierKeyPair);
    return r.withVerifierSig(base64Encode(sig.bytes));
  }

  /// Attaches a real prover ack (Ed25519 over [ackPayload]) under
  /// [keyPair] (default: the receipt's named prover, proverKeyPairA).
  Future<WorkReceipt> withProverSig(WorkReceipt r,
      {SimpleKeyPair? keyPair}) async {
    final sig = await algorithm.sign(r.ackPayload,
        keyPair: keyPair ?? proverKeyPairA);
    return r.withProverSig(base64Encode(sig.bytes));
  }

  Future<WorkReceipt> signedReceipt({
    String? proverPubkey,
    SimpleKeyPair? proverKeyPair,
    double amount = 25.0,
    String nonce = 'ab',
  }) async {
    final unsigned = unsignedReceipt(
        proverPubkey: proverPubkey, amount: amount, nonce: nonce);
    final signed = await withVerifierSig(unsigned);
    return withProverSig(signed,
        keyPair: proverKeyPair ?? proverKeyPairA);
  }

  /// Local-claim possession signature over the static preimage.
  Future<String> claimSig(WorkReceipt r, {SimpleKeyPair? keyPair}) async {
    final sig = await algorithm.sign(r.claimPreimage(),
        keyPair: keyPair ?? proverKeyPairA);
    return base64Encode(sig.bytes);
  }

  /// Remote-claim possession signature over the freshness preimage.
  Future<String> remoteClaimSig(
    WorkReceipt r,
    String nonce,
    int expiry, {
    SimpleKeyPair? keyPair,
    // Signs an ARBITRARY preimage — lets the tests forge mismatched
    // freshness parameters.
    Uint8List? preimageOverride,
  }) async {
    final sig = await algorithm.sign(
        preimageOverride ??
            r.claimPreimage(verifierNonce: nonce, expiryMillis: expiry),
        keyPair: keyPair ?? proverKeyPairA);
    return base64Encode(sig.bytes);
  }

  setUp(() async {
    verifierKeyPair = await algorithm.newKeyPair();
    verifierPubHex =
        bytesToHex((await verifierKeyPair.extractPublicKey()).bytes);
    proverKeyPairA = await algorithm.newKeyPair();
    proverPubHexA =
        bytesToHex((await proverKeyPairA.extractPublicKey()).bytes);
    proverKeyPairB = await algorithm.newKeyPair();
    proverPubHexB =
        bytesToHex((await proverKeyPairB.extractPublicKey()).bytes);
  });

  group('ingestWorkReceipt — signed upgrade of an unsigned first insert',
      () {
    late AppDatabase db;
    late CreditService svc;

    setUp(() async {
      db = AppDatabase();
      svc = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        localProverPubkeyHex: () => proverPubHexA,
      );
      await svc.ready;
    });

    tearDown(() async {
      await db.close();
    });

    test('unsigned first insert persists; the signed redelivery upgrades '
        'both signatures and becomes claimable', () async {
      final unsigned = unsignedReceipt();
      expect(await svc.ingestWorkReceipt(unsigned), isTrue);
      var row = await db.getWorkReceipt(unsigned.receiptId);
      expect(row!['verifierSig'], isEmpty);
      expect(row['proverSig'], isNull);

      // First claim attempt refuses — the artifact is still unsigned.
      expect(await svc.claimVerifiedReceipt(unsigned, claimSignatureB64: ''),
          0.0);

      // The signed redelivery carries the SAME receiptId — it must
      // upgrade the stored signatures, not be deduped away.
      final signed = await withProverSig(await withVerifierSig(unsigned));
      expect(await svc.ingestWorkReceipt(signed), isTrue);
      row = await db.getWorkReceipt(unsigned.receiptId);
      expect(row!['verifierSig'], signed.verifierSig);
      expect(row['proverSig'], signed.proverSig);

      // And the now-complete artifact mints attested value.
      expect(
          await svc.claimVerifiedReceipt(
              WorkReceipt.fromDbMap(row),
              claimSignatureB64: await claimSig(unsigned)),
          25.0);
    });

    test('a forged verifierSig upgrade is refused — the stored row stays '
        'unsigned', () async {
      final unsigned = unsignedReceipt();
      expect(await svc.ingestWorkReceipt(unsigned), isTrue);

      final forged = unsigned.withVerifierSig(
          base64Encode(Uint8List.fromList(List.filled(64, 0xAA))));
      expect(await svc.ingestWorkReceipt(forged), isFalse);
      final row = await db.getWorkReceipt(unsigned.receiptId);
      expect(row!['verifierSig'], isEmpty);
    });

    test('a forged proverSig upgrade is refused', () async {
      // Stored row: verifier-signed but un-acked.
      final partial = await withVerifierSig(unsignedReceipt());
      expect(await svc.ingestWorkReceipt(partial), isTrue);

      final forged = partial.withProverSig(
          base64Encode(Uint8List.fromList(List.filled(64, 0xBB))));
      expect(await svc.ingestWorkReceipt(forged), isFalse);
      final row = await db.getWorkReceipt(partial.receiptId);
      expect(row!['proverSig'], isNull);
    });

    test('proverSig-only upgrade fills the missing ack', () async {
      final partial = await withVerifierSig(unsignedReceipt());
      expect(await svc.ingestWorkReceipt(partial), isTrue);

      final complete = await withProverSig(partial);
      expect(await svc.ingestWorkReceipt(complete), isTrue);
      final row = await db.getWorkReceipt(partial.receiptId);
      expect(row!['proverSig'], complete.proverSig);
    });

    test('first-signed-wins: a DIFFERENT signature can never overwrite '
        'a stored one (no downgrade)', () async {
      final signed = await signedReceipt();
      expect(await svc.ingestWorkReceipt(signed), isTrue);

      // Same receiptId, same shape, different signature bytes — the
      // stored column is non-empty so the redelivery is a no-op.
      final imposter = signed.withVerifierSig(
          base64Encode(Uint8List.fromList(List.filled(64, 0xCC))));
      expect(await svc.ingestWorkReceipt(imposter), isFalse);
      final row = await db.getWorkReceipt(signed.receiptId);
      expect(row!['verifierSig'], signed.verifierSig);
      expect(row['proverSig'], signed.proverSig);
    });

    test('a tampered body (receiptId mismatch) is refused on the merge '
        'path', () async {
      final signed = await signedReceipt();
      expect(await svc.ingestWorkReceipt(signed), isTrue);

      // Forge an artifact that NAMES the stored id but carries a
      // different canonical body — computeReceiptId != receiptId.
      final tampered = WorkReceipt.fromDbMap({
        ...signed.toDbMap(),
        'amount': 9999.0, // body changed; receiptId left stale
      });
      expect(tampered.computeReceiptId() == tampered.receiptId, isFalse);
      expect(await svc.ingestWorkReceipt(tampered), isFalse);
      final row = await db.getWorkReceipt(signed.receiptId);
      expect(row!['amount'], 25.0);
    });

    test('upgrade never touches spent — a consumed receipt stays '
        'consumed', () async {
      final unsigned = unsignedReceipt();
      expect(await svc.ingestWorkReceipt(unsigned), isTrue);
      expect(
          await db.claimReceiptAtomically(unsigned.receiptId), isTrue);

      final signed = await withProverSig(await withVerifierSig(unsigned));
      expect(await svc.ingestWorkReceipt(signed), isTrue);
      final row = await db.getWorkReceipt(unsigned.receiptId);
      expect(row!['spent'], isTrue,
          reason: 'the signature upgrade must not resurrect a spent '
              'receipt — first-insert-wins covers bookkeeping too');
      expect(await svc.claimVerifiedReceipt(
          WorkReceipt.fromDbMap(row),
          claimSignatureB64: await claimSig(unsigned)), 0.0);
    });
  });

  group('claimVerifiedReceipt — remote-claim freshness', () {
    late AppDatabase db;
    late CreditService svc;

    setUp(() async {
      db = AppDatabase();
      svc = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        localProverPubkeyHex: () => proverPubHexA,
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

    int freshExpiry() => DateTime.now()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch;

    test('a valid freshness-bound remote claim mints', () async {
      final r = await persist(await signedReceipt());
      final expiry = freshExpiry();
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64:
                  await remoteClaimSig(r, 'srv_nonce_1', expiry),
              verifierNonce: 'srv_nonce_1',
              expiryMillis: expiry),
          25.0);
      final row = await db.getWorkReceipt(r.receiptId);
      expect(row!['spent'], isTrue);
    });

    test('expired freshness is refused — the row stays unspent',
        () async {
      final r = await persist(await signedReceipt());
      final stale = DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64:
                  await remoteClaimSig(r, 'srv_nonce_2', stale),
              verifierNonce: 'srv_nonce_2',
              expiryMillis: stale),
          0.0);
      final row = await db.getWorkReceipt(r.receiptId);
      expect(row!['spent'], isFalse,
          reason: 'a refused freshness check must leave the row for the '
              'true prover\'s fresh claim');
    });

    test('one freshness half without the other is a malformed challenge',
        () async {
      final r = await persist(await signedReceipt());
      final expiry = freshExpiry();
      // Nonce without expiry.
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64:
                  await remoteClaimSig(r, 'srv_nonce_3', expiry),
              verifierNonce: 'srv_nonce_3'),
          0.0);
      // Expiry without nonce.
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r),
              expiryMillis: expiry),
          0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('a signature over the LOCAL preimage does not satisfy a remote '
        'challenge (domain mismatch fails closed)', () async {
      final r = await persist(await signedReceipt());
      final expiry = freshExpiry();
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r),
              verifierNonce: 'srv_nonce_4',
              expiryMillis: expiry),
          0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('a signature binding a DIFFERENT nonce is refused', () async {
      final r = await persist(await signedReceipt());
      final expiry = freshExpiry();
      // Signed 'nonce_A' but the challenge presented 'nonce_B'.
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64:
                  await remoteClaimSig(r, 'nonce_A', expiry),
              verifierNonce: 'nonce_B',
              expiryMillis: expiry),
          0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('remote claim replay loses the CAS — a second claim of the '
        'same receipt mints nothing', () async {
      final r = await persist(await signedReceipt());
      final expiry = freshExpiry();
      final sig = await remoteClaimSig(r, 'srv_nonce_5', expiry);
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: sig,
              verifierNonce: 'srv_nonce_5',
              expiryMillis: expiry),
          25.0);
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: sig,
              verifierNonce: 'srv_nonce_5',
              expiryMillis: expiry),
          0.0);
      expect(svc.balance, 25.0);
    });
  });

  group('prover-key-scoped attested balance (schema v7)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    Future<WorkReceipt> persist(WorkReceipt r) async {
      await db.insertWorkReceipt(r.toDbMap());
      return r;
    }

    test('a multi-key wallet mints under the receipt\'s OWN prover key '
        '— both shards back egress', () async {
      final held = {proverPubHexA, proverPubHexB};
      final svc = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        localProverPubkeys: () async => held,
      );
      await svc.ready;

      // Claim under key A.
      final ra = await persist(await signedReceipt(
          proverPubkey: proverPubHexA, nonce: 'aa'));
      expect(
          await svc.claimVerifiedReceipt(ra,
              claimSignatureB64:
                  await claimSig(ra, keyPair: proverKeyPairA)),
          25.0);
      // Claim under key B.
      final rb = await persist(await signedReceipt(
          proverPubkey: proverPubHexB,
          proverKeyPair: proverKeyPairB,
          nonce: 'bb'));
      expect(
          await svc.claimVerifiedReceipt(rb,
              claimSignatureB64:
                  await claimSig(rb, keyPair: proverKeyPairB)),
          25.0);

      await svc.settled;
      expect(svc.attestedBalance, 50.0);

      // Persisted rows carry their own scope.
      final rows = await db.getCreditTransactions();
      final mints =
          rows.where((r) => r['isAttested'] == true).toList();
      expect(mints.length, 2);
      final scopes =
          mints.map((r) => r['attestedPubkey'] as String).toSet();
      expect(scopes, {proverPubHexA, proverPubHexB});
    });

    test('a rotated-out key\'s minted value stops backing egress',
        () async {
      // Phase 1: the wallet holds ONLY key A and mints under it.
      var held = {proverPubHexA};
      final first = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        localProverPubkeys: () async => held,
      );
      await first.ready;
      final r = await persist(await signedReceipt(
          proverPubkey: proverPubHexA, nonce: 'cc'));
      expect(
          await first.claimVerifiedReceipt(r,
              claimSignatureB64:
                  await claimSig(r, keyPair: proverKeyPairA)),
          25.0);
      await first.settled;
      expect(first.attestedBalance, 25.0);

      // Rotation: key A leaves the held set; the wallet now holds only
      // key B. A fresh service instance rehydrates the scoped mint but
      // resolves the CURRENT held set — A's shard is unreachable.
      held = {proverPubHexB};
      final rotated = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        localProverPubkeys: () async => held,
      );
      await rotated.ready;
      expect(rotated.balance, 25.0,
          reason: 'the ledger balance is wallet-wide — rotation does '
              'not destroy the minted value');
      expect(rotated.attestedBalance, 0.0,
          reason: 'the minted value is scoped to key A, which is no '
              'longer held — it cannot back egress');
      expect(
          rotated.spendCredits(
              amount: 10.0,
              reason: 'egress attempt',
              isAttested: true),
          isFalse,
          reason: 'egress against a rotated-out key\'s attested value '
              'refuses outright');
    });

    test('legacy unscoped attested rows (attested_pubkey IS NULL) count '
        'for any held key', () async {
      // A pre-v7 attested mint: isAttested, no scope column value.
      await db.insertCreditTransaction({
        'id': 'tx_legacy_attested',
        'timestamp':
            DateTime.now().subtract(const Duration(seconds: 1)),
        'type': 'storageReward',
        'amount': 40.0,
        'description': 'legacy attested mint',
        'hash': 'h_legacy',
        'isAttested': true,
      });
      final svc = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        localProverPubkeys: () async => {proverPubHexB},
      );
      await svc.ready;
      expect(svc.attestedBalance, 40.0,
          reason: 'NULL is the unscoped legacy bucket — under '
              'single-identity it reproduces the old wallet-scoped '
              'semantics');
      expect(
          svc.spendCredits(
              amount: 10.0,
              reason: 'legacy-backed egress',
              isAttested: true),
          isTrue);
    });
  });
}
