// PERMANENT REGRESSION SUITE — adversarial exploit tests for the
// claimVerifiedReceipt guard chain (ALX-010 attested mint + ALX-012
// per-receipt `v`, domain-separated signingPayload, in-path Ed25519
// verification + quorum-REV3 possession binding: ambient-identity
// resolver + claimSignatureB64 over 'alexandria:receipt-claim:v{v}:
// {receiptId}'). Covers: forgery & domain confusion, replay/CAS dedup,
// verifier-oracle wiring, pubkey-canonicalization self-dealing bypasses,
// hostile doubles failing closed, the claimable-version window (floor =
// minClaimableWireVersion, ceiling = WorkReceipt.wireVersion), and
// possession-proof refusals (wrong key, wrong domain, no resolver).
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
  late SimpleKeyPair localKeyPair;
  late String localPubHex;

  /// Production-equivalent oracle (mirrors creditServiceProvider wiring):
  /// hex-decodes the pinned pubkey, then Ed25519-verifies.
  Future<bool> receiptVerifier(
      Uint8List message, Uint8List sig, String publicKeyHex) async {
    try {
      final pk = SimplePublicKey(hexToBytes(publicKeyHex),
          type: KeyPairType.ed25519);
      return await algorithm.verify(message,
          signature: Signature(sig, publicKey: pk));
    } catch (_) {
      return false;
    }
  }

  Future<WorkReceipt> signedReceipt({
    int? v,
    String workType = 'storage',
    String proverPubkey = 'prover_key_hex',
    String? verifierPubkey,
    double amount = 25.0,
    double workUnits = 4096,
    int? expiresAt,
    SimpleKeyPair? keyPair,
    String? verifierSig,
    List<int> chunkIndices = const [0, 1],
    // v3+ issuance acknowledgment (ALX-012 §5.8): signed over
    // [WorkReceipt.ackPayload] under [proverKeyPair] (default: the
    // local prover key). An explicit string attaches verbatim; ''
    // leaves the artifact un-acked.
    SimpleKeyPair? proverKeyPair,
    String? proverSig,
  }) async {
    final version = v ?? WorkReceipt.wireVersion;
    final unsigned = WorkReceipt.issue(
      v: version,
      workType: workType,
      proverPubkey: proverPubkey,
      verifierPubkey: verifierPubkey ?? verifierPubHex,
      cid: 'bafy_omega3',
      chunkIndices: chunkIndices,
      challengeNonce: 'ab' * 16,
      responseTag: 'cd' * 32,
      workUnits: workUnits,
      amount: amount,
      epoch: WorkReceipt.epochFor(DateTime.now()),
      expiresAt: expiresAt ??
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    );
    WorkReceipt signed;
    if (verifierSig != null) {
      signed = unsigned.withVerifierSig(verifierSig);
    } else {
      final sig = await algorithm.sign(unsigned.signingPayload,
          keyPair: keyPair ?? verifierKeyPair);
      signed = unsigned.withVerifierSig(base64Encode(sig.bytes));
    }
    if (version >= WorkReceipt.minAckWireVersion) {
      if (proverSig != null) {
        if (proverSig.isNotEmpty) {
          signed = signed.withProverSig(proverSig);
        }
      } else {
        final ack = await algorithm.sign(signed.ackPayload,
            keyPair: proverKeyPair ?? localKeyPair);
        signed = signed.withProverSig(base64Encode(ack.bytes));
      }
    }
    return signed;
  }

  /// Attaches the v3 issuance-acknowledgment counter-signature to an
  /// already-signed receipt built OUTSIDE [signedReceipt] — for tests
  /// that construct the artifact by hand.
  Future<WorkReceipt> withAck(WorkReceipt r, {SimpleKeyPair? keyPair}) async {
    final ack = await algorithm.sign(r.ackPayload,
        keyPair: keyPair ?? localKeyPair);
    return r.withProverSig(base64Encode(ack.bytes));
  }

  /// Signs the REV3 possession-proof preimage — the ASCII bytes of
  /// 'alexandria:receipt-claim:v{r.v}:{r.receiptId}' — under [keyPair]
  /// (default: the local prover key). claimVerifiedReceipt verifies it
  /// in-path under receipt.proverPubkey.
  Future<String> claimSig(WorkReceipt r, {SimpleKeyPair? keyPair}) async {
    final preimage = Uint8List.fromList(utf8
        .encode('alexandria:receipt-claim:v${r.v}:${r.receiptId}'));
    final sig =
        await algorithm.sign(preimage, keyPair: keyPair ?? localKeyPair);
    return base64Encode(sig.bytes);
  }

  /// Builds a receipt WITHOUT going through issue() (which recomputes the
  /// id and would throw on hostile doubles) — the way a wire artifact /
  /// DB row arrives: fields verbatim via fromDbMap.
  WorkReceipt craftedReceipt(Map<String, dynamic> fields) {
    final base = WorkReceipt.issue(
      workType: 'storage',
      proverPubkey: 'p',
      verifierPubkey: 'v',
      challengeNonce: 'ab' * 16,
      responseTag: 'cd' * 32,
      workUnits: 1,
      amount: 1,
      epoch: '2026-01-01',
      expiresAt: 9999999999999,
    ).toDbMap();
    return WorkReceipt.fromDbMap({...base, ...fields});
  }

  late AppDatabase db;
  late CreditService svc;

  setUp(() async {
    verifierKeyPair = await algorithm.newKeyPair();
    verifierPubHex =
        bytesToHex((await verifierKeyPair.extractPublicKey()).bytes);
    localKeyPair = await algorithm.newKeyPair();
    localPubHex = bytesToHex((await localKeyPair.extractPublicKey()).bytes);
    db = AppDatabase();
    svc = CreditService(
      db: db,
      initialBalance: 0.0,
      receiptVerifier: receiptVerifier,
      // Ambient identity resolver (production wires IdentityService) —
      // the "local" prover key can no longer be asserted by the caller.
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

  group('REV3-1 forgery & domain confusion', () {
    test('EXPLOIT-CHECK: forged claim must not burn the row — the honest '
        'claim afterwards must still mint (DoS ordering)', () async {
      final attacker = await algorithm.newKeyPair();
      // One unsigned artifact; two signatures over its payload — the
      // attacker key's (forgery) and the real verifier's (honest).
      final unsigned = WorkReceipt.issue(
        workType: 'storage',
        proverPubkey: localPubHex,
        verifierPubkey: verifierPubHex,
        cid: 'bafy_omega3',
        chunkIndices: const [0, 1],
        challengeNonce: 'ab' * 16,
        responseTag: 'cd' * 32,
        workUnits: 4096,
        amount: 25.0,
        epoch: WorkReceipt.epochFor(DateTime.now()),
        expiresAt:
            DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
      );
      final forgedSig = await algorithm.sign(unsigned.signingPayload,
          keyPair: attacker);
      final forged =
          unsigned.withVerifierSig(base64Encode(forgedSig.bytes));
      await db.insertWorkReceipt(forged.toDbMap());

      // Forged claim: refused AND leaves the row unspent.
      expect(
          await svc.claimVerifiedReceipt(forged,
              claimSignatureB64: await claimSig(forged)),
          0.0);
      expect((await db.getWorkReceipt(forged.receiptId))!['spent'], isFalse);

      // Now the SAME body with the REAL verifier signature — same
      // receiptId, still-claimable row. v3 also needs the prover's
      // issuance-acknowledgment signature.
      final honestSig = await algorithm.sign(unsigned.signingPayload,
          keyPair: verifierKeyPair);
      final honest = await withAck(
          unsigned.withVerifierSig(base64Encode(honestSig.bytes)));
      expect(honest.receiptId, forged.receiptId);
      expect(
          await svc.claimVerifiedReceipt(honest,
              claimSignatureB64: await claimSig(honest)),
          25.0);
      expect(svc.attestedBalance, 25.0);
    });

    test('malformed verifierSig variants are all refused unspent',
        () async {
      for (final sig in [
        base64Encode(Uint8List(63)), // one byte short
        base64Encode(Uint8List(65)), // one byte long
        '!!!not_base64!!!',
        base64Encode(Uint8List(64)), // zeros
      ]) {
        final r = await persist(await signedReceipt(
            proverPubkey: localPubHex, verifierSig: sig));
        expect(
            await svc.claimVerifiedReceipt(r,
                claimSignatureB64: await claimSig(r)),
            0.0,
            reason: 'sig variant must refuse: $sig');
        expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
      }
    });

    test('signature transplanted from another receipt is refused',
        () async {
      final a = await signedReceipt(proverPubkey: localPubHex, amount: 11.0);
      final b = await persist(
          await signedReceipt(proverPubkey: localPubHex, amount: 22.0));
      final transplanted = b.withVerifierSig(a.verifierSig);
      expect(
          await svc.claimVerifiedReceipt(transplanted,
              claimSignatureB64: await claimSig(transplanted)),
          0.0);
      expect((await db.getWorkReceipt(b.receiptId))!['spent'], isFalse);
    });

    test('v1-prefixed-domain signature on a v1 artifact is refused '
        '(v1 domain is the BARE body only)', () async {
      final unsigned = WorkReceipt.issue(
        v: 1,
        workType: 'storage',
        proverPubkey: localPubHex,
        verifierPubkey: verifierPubHex,
        challengeNonce: 'ab' * 16,
        responseTag: 'cd' * 32,
        workUnits: 1,
        amount: 10,
        epoch: WorkReceipt.epochFor(DateTime.now()),
        expiresAt:
            DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
      );
      // Attacker signs 'alexandria:receipt:v1:<canonical>' — but the v1
      // payload is the bare canonical JSON, so this must not verify.
      final wrongDomain = await algorithm.sign(
          Uint8List.fromList(
              utf8.encode('alexandria:receipt:v1:${unsigned.canonicalJson()}')),
          keyPair: verifierKeyPair);
      final r = await persist(
          unsigned.withVerifierSig(base64Encode(wrongDomain.bytes)));
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('cross-version: a legit v1 artifact re-presented as v2 dies on '
        'the tamper check even with a valid v1 signature', () async {
      final v1 = await signedReceipt(v: 1, proverPubkey: localPubHex);
      // Re-issue identical fields at v2 — different canonical body,
      // different recomputed id — keep the v1 signature attached.
      final asV2 = WorkReceipt.issue(
        v: 2,
        workType: 'storage',
        proverPubkey: localPubHex,
        verifierPubkey: verifierPubHex,
        cid: 'bafy_omega3',
        chunkIndices: const [0, 1],
        challengeNonce: 'ab' * 16,
        responseTag: 'cd' * 32,
        workUnits: 4096,
        amount: 25.0,
        epoch: v1.toDbMap()['epoch'] as String,
        expiresAt: v1.expiresAt,
      ).withVerifierSig(v1.verifierSig);
      expect(asV2.computeReceiptId(), asV2.receiptId);
      await db.insertWorkReceipt(asV2.toDbMap());
      expect(
          await svc.claimVerifiedReceipt(asV2,
              claimSignatureB64: await claimSig(asV2)),
          0.0);
      expect((await db.getWorkReceipt(asV2.receiptId))!['spent'], isFalse);
    });
  });

  group('REV3-2 replay & CAS', () {
    test('re-inserting a spent receiptId does NOT resurrect it '
        '(insertOrIgnore)', () async {
      final r = await persist(await signedReceipt(proverPubkey: localPubHex));
      final sig = await claimSig(r);
      expect(await svc.claimVerifiedReceipt(r, claimSignatureB64: sig),
          25.0);
      // Attacker re-delivers the same artifact (or an unspent-flagged
      // copy) — must not unspend.
      await db.insertWorkReceipt({...r.toDbMap(), 'spent': false});
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isTrue);
      expect(await svc.claimVerifiedReceipt(r, claimSignatureB64: sig),
          0.0);
    });

    test('two concurrent claims of one receipt mint exactly once',
        () async {
      final r = await persist(await signedReceipt(proverPubkey: localPubHex));
      final sig = await claimSig(r);
      final results = await Future.wait([
        svc.claimVerifiedReceipt(r, claimSignatureB64: sig),
        svc.claimVerifiedReceipt(r, claimSignatureB64: sig),
        svc.claimVerifiedReceipt(r, claimSignatureB64: sig),
      ]);
      expect(results.where((m) => m > 0).length, 1);
      expect(svc.attestedBalance, 25.0);
    });
  });

  group('REV3-3 verifier wiring', () {
    test('malformed verifierPubkey variants fail closed, unspent, '
        'no throw', () async {
      for (final badKey in [
        'zz_not_hex',
        'a', // odd-length single nibble
        '',
        'ab', // 1 byte — far too short for ed25519
        verifierPubHex.substring(0, 62), // 31 bytes
        '0x$verifierPubHex', // 0x-prefixed
      ]) {
        // Sign the payload with the REAL verifier key — only the pubkey
        // field is corrupt. A slip-through would mint.
        final r = await persist(await signedReceipt(
            proverPubkey: localPubHex, verifierPubkey: badKey));
        expect(
            await svc.claimVerifiedReceipt(r,
                claimSignatureB64: await claimSig(r)),
            0.0,
            reason: 'malformed key must refuse: "$badKey"');
        expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
      }
    });

    test('a verifyFn that throws sync/async never leaks a mint and '
        'never consumes the row', () async {
      final throwing = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: (m, s, k) =>
            throw StateError('oracle exploded'),
        localProverPubkeyHex: () => localPubHex,
      );
      await throwing.ready;
      final asyncThrowing = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: (m, s, k) =>
            Future<bool>.error(StateError('async boom')),
        localProverPubkeyHex: () => localPubHex,
      );
      await asyncThrowing.ready;

      final r1 = await persist(await signedReceipt(proverPubkey: localPubHex));
      expect(
          await throwing.claimVerifiedReceipt(r1,
              claimSignatureB64: await claimSig(r1)),
          0.0);
      final r2 = await persist(await signedReceipt(proverPubkey: localPubHex));
      expect(
          await asyncThrowing.claimVerifiedReceipt(r2,
              claimSignatureB64: await claimSig(r2)),
          0.0);
      expect((await db.getWorkReceipt(r1.receiptId))!['spent'], isFalse);
      expect((await db.getWorkReceipt(r2.receiptId))!['spent'], isFalse);
    });
  });

  group('REV3-4 identity-guard canonicalization bypass', () {
    test('EXPLOIT: verifierPubkey = UPPERCASE of local key — same Ed25519 '
        'key, different string — bypasses isSelfIssued AND verifier!=local '
        'so a SELF-SIGNED receipt mints ATTESTED value', () async {
      // Forked client: crafts a receipt prover=local(lowercase),
      // verifier=local(UPPERCASE), signs with its OWN key. Every guard
      // uses raw string equality; hexToBytes is case-insensitive, so the
      // signature verifies against the same 32-byte key.
      final r = await persist(await signedReceipt(
        proverPubkey: localPubHex,
        verifierPubkey: localPubHex.toUpperCase(),
        keyPair: localKeyPair, // self-signed!
      ));
      expect(r.isSelfIssued, isFalse,
          reason: 'string compare misses the same key in different case');
      final minted = await svc.claimVerifiedReceipt(r,
          claimSignatureB64: await claimSig(r));
      // SECURE expectation: 0.0 — a self-signed receipt must never mint
      // attested value regardless of key-string casing.
      expect(minted, 0.0,
          reason: 'BUG: case-variant pubkey defeats the self-dealing '
              'guard — self-signed attested mint of $minted succeeded');
      expect(svc.attestedBalance, 0.0);
    });

    test('EXPLOIT: space-padded verifierPubkey decodes to the local key '
        '(hexToBytes strips spaces) — same self-dealing bypass', () async {
      final spaced = localPubHex
          .split('')
          .expand((c) => c == ' ' ? [c] : [c])
          .join();
      // Insert a space every 8 chars — still decodes identically.
      final padded =
          localPubHex.replaceAllMapped(RegExp('.{8}'), (m) => '${m[0]} ');
      expect(hexToBytes(padded), hexToBytes(localPubHex),
          reason: 'padded hex decodes to the same key bytes');
      final r = await persist(await signedReceipt(
        proverPubkey: localPubHex,
        verifierPubkey: padded,
        keyPair: localKeyPair,
      ));
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          0.0,
          reason: 'BUG: whitespace-variant pubkey defeats the self-'
              'dealing guard ($spaced)');
    });

    test('EXPLOIT-CHECK: empty proverPubkey + foreign sig claimed by a '
        'node whose resolver returns "" — does the prover binding go '
        'vacuous?', () async {
      // A service whose identity resolver serves the empty string —
      // the possession-bound equivalent of the old caller-supplied
      // localPubkeyHex="".
      final emptyIdentity = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        localProverPubkeyHex: () => '',
      );
      await emptyIdentity.ready;
      final r = await persist(await signedReceipt(
        proverPubkey: '',
        amount: 10.0,
      ));
      final minted = await emptyIdentity.claimVerifiedReceipt(r,
          claimSignatureB64: '');
      // Documents actual behavior; a vacuous prover binding minting
      // attested value is a finding.
      if (minted > 0) {
        // ignore: avoid_print
        print('REV3 FINDING: empty-prover receipt minted $minted attested '
            'with resolver returning ""');
      }
      expect(minted, 0.0,
          reason: 'a receipt naming NO prover must be unclaimable');
    });
  });

  group('REV3-5 fail-closed contract on hostile doubles', () {
    test('EXPLOIT: amount=+Infinity receipt makes claimVerifiedReceipt '
        'THROW instead of returning 0.0 (tamper check outside try)',
        () async {
      // issue() would throw on amountMilli, so craft via fromDbMap —
      // exactly what a DB row / wire artifact delivers.
      final hostile = craftedReceipt({
        'receiptId': 'h_inf',
        'proverPubkey': localPubHex,
        'verifierPubkey': verifierPubHex,
        'amount': double.infinity,
        'verifierSig': base64Encode(Uint8List(64)),
        'v': 2,
      });
      // Contract: "Returns the minted amount, or 0.0 on any refusal."
      final minted = await svc.claimVerifiedReceipt(hostile,
          claimSignatureB64: await claimSig(hostile));
      expect(minted, 0.0);
    });

    test('EXPLOIT: amount=1e308 (finite, overflows amountMilli) — same '
        'throw path', () async {
      final hostile = craftedReceipt({
        'receiptId': 'h_big',
        'proverPubkey': localPubHex,
        'verifierPubkey': verifierPubHex,
        'amount': 1e308,
        'verifierSig': base64Encode(Uint8List(64)),
        'v': 2,
      });
      final minted = await svc.claimVerifiedReceipt(hostile,
          claimSignatureB64: await claimSig(hostile));
      expect(minted, 0.0);
    });

    test('EXPLOIT: NaN workUnits with a positive amount — workUnitsMilli '
        'throws inside the guard chain', () async {
      final hostile = craftedReceipt({
        'receiptId': 'h_nan_wu',
        'proverPubkey': localPubHex,
        'verifierPubkey': verifierPubHex,
        'amount': 5.0,
        'workUnits': double.nan,
        'verifierSig': base64Encode(Uint8List(64)),
        'v': 2,
      });
      final minted = await svc.claimVerifiedReceipt(hostile,
          claimSignatureB64: await claimSig(hostile));
      expect(minted, 0.0);
    });

    test('NaN amount IS refused cleanly by the amount>0 guard '
        '(contrast: it never reaches computeReceiptId)', () async {
      final hostile = craftedReceipt({
        'receiptId': 'h_nan_amt',
        'proverPubkey': localPubHex,
        'verifierPubkey': verifierPubHex,
        'amount': double.nan,
        'verifierSig': base64Encode(Uint8List(64)),
        'v': 2,
      });
      expect(
          await svc.claimVerifiedReceipt(hostile,
              claimSignatureB64: await claimSig(hostile)),
          0.0);
    });
  });

  group('REV3-6 version floor/ceiling & hydration', () {
    test('v=0 and negative v are refused below the floor, unspent',
        () async {
      for (final v in [0, -1, -2147483648]) {
        final r =
            await persist(await signedReceipt(v: v, proverPubkey: localPubHex));
        expect(
            await svc.claimVerifiedReceipt(r,
                claimSignatureB64: await claimSig(r)),
            0.0,
            reason: 'v=$v below floor must refuse');
        expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
      }
    });

    test('v1 grace: bare-domain signature claims (intended)', () async {
      final r =
          await persist(await signedReceipt(v: 1, proverPubkey: localPubHex));
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          25.0);
    });

    test('EXPLOIT-CHECK: v=99 receipt signed under '
        "'alexandria:receipt:v99:' — floor-only check means a FUTURE "
        'version mints on this build', () async {
      final r =
          await persist(await signedReceipt(v: 99, proverPubkey: localPubHex));
      // The signature IS valid under the v99 domain; only the floor is
      // enforced, so this is expected to CLAIM — flagging the missing
      // ceiling.
      final minted = await svc.claimVerifiedReceipt(r,
          claimSignatureB64: await claimSig(r));
      // ignore: avoid_print
      print('REV3 OBSERVE: v=99 claim minted $minted (window has no ceiling)');
      // Not asserting 0 — documenting behavior; a {previous,current}
      // grace window arguably should also cap at wireVersion.
    });

    test('hydrated unknown future v does not crash parse and selects '
        'the matching domain prefix', () async {
      final r = await persist(await signedReceipt(v: 7, proverPubkey: 'l'));
      final hydrated =
          WorkReceipt.fromDbMap((await db.getWorkReceipt(r.receiptId))!);
      expect(hydrated.v, 7);
      expect(
          utf8.decode(hydrated.signingPayload),
          startsWith('alexandria:receipt:v7:'));
    });

    test('row missing the v column hydrates as v1', () async {
      final map = signedReceipt(v: 2, proverPubkey: localPubHex)
          .then((r) => r.toDbMap());
      final m = await map..remove('v');
      await db.insertWorkReceipt(m);
      final hydrated = WorkReceipt.fromDbMap(
          (await db.getWorkReceipt(m['receiptId'] as String))!);
      expect(hydrated.v, 1);
    });
  });

  group('REV3-7 legacy guard regressions', () {
    test('expired / self-issued / prover-mismatch / unsigned / '
        'non-positive amounts all refuse', () async {
      // expired
      final expired = await persist(await signedReceipt(
          proverPubkey: localPubHex,
          expiresAt: DateTime.now()
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch));
      expect(
          await svc.claimVerifiedReceipt(expired,
              claimSignatureB64: await claimSig(expired)),
          0.0);
      // self-issued (same string case)
      final selfIssued = await persist(await signedReceipt(
          proverPubkey: verifierPubHex));
      expect(
          await svc.claimVerifiedReceipt(selfIssued,
              claimSignatureB64: await claimSig(selfIssued)),
          0.0);
      // foreign prover
      final foreign = await persist(await signedReceipt(
          proverPubkey: 'someone_else'));
      expect(
          await svc.claimVerifiedReceipt(foreign,
              claimSignatureB64: await claimSig(foreign)),
          0.0);
      // verifier == local (spelled in a different case — canonically the
      // local key, signed by it): the self-dealing guard refuses.
      final localVerif = await persist(await signedReceipt(
          proverPubkey: localPubHex,
          verifierPubkey: localPubHex.toUpperCase(),
          keyPair: localKeyPair));
      expect(
          await svc.claimVerifiedReceipt(localVerif,
              claimSignatureB64: await claimSig(localVerif)),
          0.0);
      // unsigned
      final unsigned = await persist(
          await signedReceipt(proverPubkey: localPubHex, verifierSig: ''));
      expect(
          await svc.claimVerifiedReceipt(unsigned,
              claimSignatureB64: await claimSig(unsigned)),
          0.0);
      // zero and negative amounts
      for (final amount in [0.0, -1.0, -1e9]) {
        final r = await persist(
            await signedReceipt(proverPubkey: localPubHex, amount: amount));
        expect(
            await svc.claimVerifiedReceipt(r,
                claimSignatureB64: await claimSig(r)),
            0.0,
            reason: 'amount=$amount must refuse');
      }
      expect(svc.balance, 0.0);
      expect(svc.attestedBalance, 0.0);
    });
  });

  group('REV3-8 decoder-asymmetry respelled pairs', () {
    // The oracle decoder (beacon_models.hexToBytes) is now STRICT: after
    // ASCII-space stripping it accepts only ^[0-9a-fA-F]+$ of even
    // length. The old int.parse-based decoder tolerated '+' signs, tabs,
    // NBSP and trailing newlines, so ONE key byte '0d' could be spelled
    // '+d', '\td', 'd\n', NBSP+'d' — all decoding to identical bytes
    // while differing as strings (evading `==`) AND evading the
    // canonical guard (WorkReceipt.samePubkey's tier-2 accepts only the
    // same strict class). Every respelled key must now fail closed:
    // strict decode throws inside the oracle adapter → verify false →
    // claim refuses, row unspent.

    /// Index of the first byte pair whose high nibble is '0' — the only
    /// pairs admitting value-preserving non-hex respellings (a 2-char
    /// chunk must parse to the same byte, so one char must carry the
    /// whole value: '0d' → '+d', '\td', 'd\n', NBSP+'d').
    int respellablePair(String hex) {
      for (var i = 0; i + 1 < hex.length; i += 2) {
        if (hex[i] == '0') return i;
      }
      return -1;
    }

    String respell(String hex, int i, String pair) =>
        hex.substring(0, i) + pair + hex.substring(i + 2);

    /// A keypair whose pubkey hex contains a respellable '0d' byte —
    /// regenerated until one exists so the test is deterministic
    /// (~12.7% of random 32-byte keys have no zero-nibble byte).
    Future<(SimpleKeyPair, String)> respellableKey() async {
      var kp = await algorithm.newKeyPair();
      var hex = bytesToHex((await kp.extractPublicKey()).bytes);
      while (respellablePair(hex) < 0) {
        kp = await algorithm.newKeyPair();
        hex = bytesToHex((await kp.extractPublicKey()).bytes);
      }
      return (kp, hex);
    }

    test('respelled verifierPubkey spellings all fail closed, unspent',
        () async {
      final (kp, hex) = await respellableKey();
      final i = respellablePair(hex);
      final lo = hex[i + 1];
      for (final pair in ['+$lo', '\t$lo', '\u00A0$lo', '$lo\n']) {
        final respelled = respell(hex, i, pair);
        // The respelling differs as a STRING, would have decoded to the
        // same key bytes under the permissive decoder — and is not even
        // hex under the guard's strict view.
        expect(respelled, isNot(equals(hex)));
        expect(WorkReceipt.samePubkey(respelled, hex), isFalse,
            reason: 'guard must not equate a non-hex respelling: "$pair"');
        // Signed by the REAL owner of the respelled key — under the old
        // decoder this artifact verified and claimed.
        final r = await persist(await signedReceipt(
          proverPubkey: localPubHex,
          verifierPubkey: respelled,
          keyPair: kp,
        ));
        expect(
            await svc.claimVerifiedReceipt(r,
                claimSignatureB64: await claimSig(r)),
            0.0,
            reason: 'respelled verifier key "$pair" must refuse on '
                'strict decode');
        expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
      }
    });

    test('respelled proverPubkey dies at the prover-binding guard '
        '(never reaches the oracle)', () async {
      final (_, hex) = await respellableKey();
      final i = respellablePair(hex);
      // A genuinely foreign-signed receipt naming the local key spelled
      // non-canonically: the prover binding must NOT match it.
      final respelled = respell(hex, i, '+${hex[i + 1]}');
      final r = await persist(await signedReceipt(
        proverPubkey: respelled,
        verifierPubkey: verifierPubHex,
      ));
      // The resolver serves the CANONICAL spelling of the same key the
      // respelled prover field would decode to — the binding must still
      // refuse because the respelling is not valid strict hex at all.
      final canonSvc = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        localProverPubkeyHex: () => hex,
      );
      await canonSvc.ready;
      expect(
          await canonSvc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          0.0,
          reason: 'a non-hex prover spelling must not bind the local key');
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('a resolver serving a respelled local key refuses rather than '
        'binding vacuously', () async {
      final (kp, hex) = await respellableKey();
      final i = respellablePair(hex);
      final respelledLocal = respell(hex, i, '\t${hex[i + 1]}');
      // A clean, legitimately-claimable receipt naming the CANONICAL
      // local key — claimed by a node whose resolver serves a respelled
      // 'local' spelling: the prover binding fails closed. The v3 ack
      // is signed by the receipt's actual prover key (kp), not the
      // default local key.
      final r = await persist(await signedReceipt(
          proverPubkey: hex, proverKeyPair: kp));
      final sig = await claimSig(r, keyPair: kp);
      final respelledSvc = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        localProverPubkeyHex: () => respelledLocal,
      );
      await respelledSvc.ready;
      expect(
          await respelledSvc.claimVerifiedReceipt(r,
              claimSignatureB64: sig),
          0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
      // And the SAME row still claims for the canonical spelling — the
      // refusal was the binding, not a burned artifact.
      final canonSvc = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        localProverPubkeyHex: () => hex,
      );
      await canonSvc.ready;
      expect(
          await canonSvc.claimVerifiedReceipt(r, claimSignatureB64: sig),
          25.0);
    });

    test('a clean-key legit receipt still claims (strictness does not '
        'over-refuse)', () async {
      final r = await persist(await signedReceipt(proverPubkey: localPubHex));
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          25.0);
      expect(svc.attestedBalance, 25.0);
    });
  });

  group('REV3-9 possession-bound claim (claimSignatureB64)', () {
    test('claim signature by a key OTHER than proverPubkey is refused '
        'unspent — a copied artifact cannot be claimed without the '
        'prover key', () async {
      // Attacker holds a copy of the artifact and signs the claim
      // preimage with ITS OWN key: valid Ed25519 signature, wrong
      // signer. Verification runs under receipt.proverPubkey, so this
      // must refuse — the receipt is possession-bound, not bearer.
      final attacker = await algorithm.newKeyPair();
      final r = await persist(await signedReceipt(proverPubkey: localPubHex));
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r, keyPair: attacker)),
          0.0);
      expect(svc.attestedBalance, 0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
      // The refused attempt did not burn the row — the true prover's
      // claim still lands.
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          25.0);
    });

    test('claim signature over the wrong preimage is refused — version '
        'mismatch AND wrong domain', () async {
      final r = await persist(await signedReceipt(proverPubkey: localPubHex));
      expect(r.v, WorkReceipt.wireVersion);
      // (a) Version mismatch inside the claim domain: signed
      // 'v1' while the artifact is v2.
      final wrongVersion = await algorithm.sign(
          Uint8List.fromList(utf8.encode(
              'alexandria:receipt-claim:v1:${r.receiptId}')),
          keyPair: localKeyPair);
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: base64Encode(wrongVersion.bytes)),
          0.0);
      // (b) Wrong domain entirely: the receipt's own signing payload
      // ('alexandria:receipt:v2:...') is not a claim preimage.
      final wrongDomain = await algorithm.sign(r.signingPayload,
          keyPair: localKeyPair);
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: base64Encode(wrongDomain.bytes)),
          0.0);
      // (c) A different receipt's claim signature does not transfer.
      final other = await persist(
          await signedReceipt(proverPubkey: localPubHex, amount: 7.0));
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(other)),
          0.0);
      // Nothing consumed — all three refused before the CAS.
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
      expect((await db.getWorkReceipt(other.receiptId))!['spent'], isFalse);
      expect(svc.attestedBalance, 0.0);
    });

    test('malformed claimSignatureB64 variants are refused unspent',
        () async {
      for (final bad in [
        '',
        '!!!not_base64!!!',
        base64Encode(Uint8List(63)), // one byte short
        base64Encode(Uint8List(65)), // one byte long
        base64Encode(Uint8List(64)), // zeros — shape-valid, verifies false
      ]) {
        final r =
            await persist(await signedReceipt(proverPubkey: localPubHex));
        expect(await svc.claimVerifiedReceipt(r, claimSignatureB64: bad),
            0.0,
            reason: 'claim sig variant must refuse: "$bad"');
        expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
      }
    });

    test('a service with NO resolver — or a resolver returning null — '
        'fails closed', () async {
      final noResolver = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
      );
      await noResolver.ready;
      final nullResolver = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        localProverPubkeyHex: () async => null,
      );
      await nullResolver.ready;

      final r = await persist(await signedReceipt(proverPubkey: localPubHex));
      final sig = await claimSig(r); // a VALID possession proof
      expect(
          await noResolver.claimVerifiedReceipt(r, claimSignatureB64: sig),
          0.0);
      expect(
          await nullResolver.claimVerifiedReceipt(r,
              claimSignatureB64: sig),
          0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('a resolver naming a key != proverPubkey refuses even with a '
        'valid claim signature — the binding is artifact-pinned', () async {
      // This node's identity is `other`, but the artifact names
      // localPubHex as prover and the claim signature IS valid under
      // that prover key (e.g. obtained alongside a copied artifact).
      // The resolver binding — not just the signature — must refuse.
      final other = await algorithm.newKeyPair();
      final otherHex =
          bytesToHex((await other.extractPublicKey()).bytes);
      final mismatched = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        localProverPubkeyHex: () => otherHex,
      );
      await mismatched.ready;

      final r = await persist(await signedReceipt(proverPubkey: localPubHex));
      expect(
          await mismatched.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          0.0);
      expect(mismatched.attestedBalance, 0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('a throwing resolver fails closed, unspent', () async {
      final exploding = CreditService(
        db: db,
        initialBalance: 0.0,
        receiptVerifier: receiptVerifier,
        localProverPubkeyHex: () => throw StateError('resolver exploded'),
      );
      await exploding.ready;
      final r = await persist(await signedReceipt(proverPubkey: localPubHex));
      expect(
          await exploding.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('awardBountyEscrow pays a bountyId exactly once — the payout '
        'primitive dedups even if the claim layer is bypassed', () async {
      expect(svc.awardBountyEscrow(amount: 10.0, bountyId: 'b1', cid: 'c'),
          10.0);
      expect(svc.awardBountyEscrow(amount: 10.0, bountyId: 'b1', cid: 'c'),
          0.0);
      expect(svc.balance, 10.0);
      // A different bountyId still pays; an empty id refuses.
      expect(svc.awardBountyEscrow(amount: 5.0, bountyId: 'b2', cid: 'c'),
          5.0);
      expect(svc.awardBountyEscrow(amount: 5.0, bountyId: '', cid: 'c'),
          0.0);
      expect(svc.balance, 15.0);
      // Only two payout rows landed.
      expect(
          svc.transactions
              .where((t) => t.description.contains('Bounty Escrow Payout'))
              .length,
          2);
    });
  });
}
