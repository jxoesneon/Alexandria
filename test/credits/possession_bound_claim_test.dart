// SCRATCH EVALUATOR FILE — adversarial exploit tests for the
// possession-bound receipt claim (REV3 review) and _paidBountyIds dedup.
// Delete after evaluation. Covers exploit classes 1-7 from the eval brief:
//  1. copied foreign receipt claimed under a different resolved identity
//  2. claimSignatureB64 swaps (wrong key / wrong preimage / malformed)
//  3. resolver abuse (respelled hex, throw, null/empty, per-call TOCTOU)
//  4. concurrency / cross-receipt sig replay
//  5. _paidBountyIds dedup incl. ACROSS-RESTART hole and id-burn ordering
//  6. attested mint reachable without the claim sig (regression)
//  7. version ceiling vs. signature-verification ordering (oracle behavior)
import 'dart:async';
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
  late SimpleKeyPair proverKeyPair; // the receipt's prover of record
  late String proverPubHex;
  late SimpleKeyPair otherKeyPair; // an unrelated identity
  late String otherPubHex;

  /// Production-equivalent oracle (mirrors creditServiceProvider wiring):
  /// strict hexToBytes decode + Ed25519 verify; throws on malformed key.
  /// The claim path wraps every oracle call in the fail-closed try, and
  /// the production adapter additionally catches to false — either way a
  /// throw can never mint.
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

  /// Signs the REV3 claim preimage under [keyPair] (default: prover key).
  Future<String> claimSig(WorkReceipt r, {SimpleKeyPair? keyPair}) async {
    final preimage = Uint8List.fromList(utf8
        .encode('alexandria:receipt-claim:v${r.v}:${r.receiptId}'));
    final sig =
        await algorithm.sign(preimage, keyPair: keyPair ?? proverKeyPair);
    return base64Encode(sig.bytes);
  }

  Future<WorkReceipt> signedReceipt({
    int? v,
    String workType = 'storage',
    String? proverPubkey,
    String? verifierPubkey,
    double amount = 25.0,
    int? expiresAt,
    SimpleKeyPair? keyPair,
    String? verifierSig,
    // v3+ issuance acknowledgment (ALX-012 §5.8): signed over the
    // ack domain under [proverKeyPair] (default: the prover key of
    // record). An explicit string attaches verbatim; '' leaves the
    // artifact un-acked.
    SimpleKeyPair? proverKeyPair_,
    String? proverSig,
  }) async {
    final version = v ?? WorkReceipt.wireVersion;
    final unsigned = WorkReceipt.issue(
      v: version,
      workType: workType,
      proverPubkey: proverPubkey ?? proverPubHex,
      verifierPubkey: verifierPubkey ?? verifierPubHex,
      cid: 'bafy_eval',
      chunkIndices: const [0, 1],
      challengeNonce: 'ab' * 16,
      responseTag: 'cd' * 32,
      workUnits: 4096,
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
            keyPair: proverKeyPair_ ?? proverKeyPair);
        signed = signed.withProverSig(base64Encode(ack.bytes));
      }
    }
    return signed;
  }

  late AppDatabase db;

  CreditService svcWith(
      {FutureOr<String?> Function()? resolver,
      ReceiptSignatureVerifier? verifier,
      String? fixedLocal}) {
    return CreditService(
      db: db,
      initialBalance: 0.0,
      receiptVerifier: verifier ?? receiptVerifier,
      localProverPubkeyHex: resolver ?? () => fixedLocal ?? proverPubHex,
    );
  }

  setUp(() async {
    verifierKeyPair = await algorithm.newKeyPair();
    verifierPubHex =
        bytesToHex((await verifierKeyPair.extractPublicKey()).bytes);
    proverKeyPair = await algorithm.newKeyPair();
    proverPubHex =
        bytesToHex((await proverKeyPair.extractPublicKey()).bytes);
    otherKeyPair = await algorithm.newKeyPair();
    otherPubHex = bytesToHex((await otherKeyPair.extractPublicKey()).bytes);
    db = AppDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  Future<WorkReceipt> persist(WorkReceipt r) async {
    await db.insertWorkReceipt(r.toDbMap());
    return r;
  }

  group('E1: copied foreign receipt under a DIFFERENT resolved identity',
      () {
    test('resolver=key Q, sig by Q — refused at the prover binding', () async {
      final r = await persist(await signedReceipt(amount: 25.0));
      final thief = svcWith(fixedLocal: otherPubHex);
      await thief.ready;
      // Attacker signs the claim preimage with its OWN key Q.
      expect(
          await thief.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r, keyPair: otherKeyPair)),
          0.0);
      expect(thief.attestedBalance, 0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('resolver=key Q with the VALID prover sig bundled — still refused '
        '(possession binding, not bearer)', () async {
      final r = await persist(await signedReceipt(amount: 25.0));
      final stolenBundle = await claimSig(r); // valid sig under prover key
      final thief = svcWith(fixedLocal: otherPubHex);
      await thief.ready;
      expect(
          await thief.claimVerifiedReceipt(r,
              claimSignatureB64: stolenBundle),
          0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
      // The true prover's node can still claim afterwards.
      final honest = svcWith();
      await honest.ready;
      expect(
          await honest.claimVerifiedReceipt(r,
              claimSignatureB64: stolenBundle),
          25.0);
    });
  });

  group('E2: claimSignatureB64 substitution / malformation', () {
    test('sig over the claim preimage by the VERIFIER key — refused', () async {
      final r = await persist(await signedReceipt());
      expect(
          await svcWith().claimVerifiedReceipt(r,
              claimSignatureB64:
                  await claimSig(r, keyPair: verifierKeyPair)),
          0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('sig by local key while proverPubkey names a foreign key — '
        'binding refuses before the sig check', () async {
      final r = await persist(
          await signedReceipt(proverPubkey: otherPubHex));
      // Sign with the key the receipt DOES name (other) and with the
      // local key — both must refuse because the artifact is not ours.
      expect(
          await svcWith().claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r, keyPair: otherKeyPair)),
          0.0);
      expect(
          await svcWith().claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('empty / whitespace / malformed / wrong-length sigs refuse '
        'unspent', () async {
      for (final bad in [
        '',
        '   ',
        '!!!not_base64!!!',
        base64Encode(Uint8List(63)), // short
        base64Encode(Uint8List(65)), // long
        base64Encode(Uint8List(64)), // zeros — shape-valid
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
            'AAAAAAAAAAAAAAAAAAAAAA-' // base64url char
      ]) {
        final r = await persist(await signedReceipt());
        expect(await svcWith().claimVerifiedReceipt(r, claimSignatureB64: bad),
            0.0,
            reason: 'claim sig variant must refuse: "$bad"');
        expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
      }
    });

    test('the verifierSig field replayed as claimSignature — refused '
        '(wrong preimage, wrong key)', () async {
      final r = await persist(await signedReceipt());
      expect(
          await svcWith()
              .claimVerifiedReceipt(r, claimSignatureB64: r.verifierSig),
          0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('sigs over WRONG preimages refuse unspent', () async {
      final r = await persist(await signedReceipt());
      Future<String> signRaw(String s) async {
        final sig = await algorithm.sign(
            Uint8List.fromList(utf8.encode(s)),
            keyPair: proverKeyPair);
        return base64Encode(sig.bytes);
      }

      final wrongs = <String>[
        // old domain without the version segment
        await signRaw('alexandria:receipt-claim:${r.receiptId}'),
        // wrong version inside the claim domain
        await signRaw('alexandria:receipt-claim:v1:${r.receiptId}'),
        // wrong receipt id
        await signRaw('alexandria:receipt-claim:v${r.v}:${'0' * 64}'),
        // entirely different domain
        await signRaw('alexandria:claim:v${r.v}:${r.receiptId}'),
        // the receipt signing payload itself (a verifier-domain object)
        base64Encode((await algorithm.sign(r.signingPayload,
                keyPair: proverKeyPair))
            .bytes),
      ];
      for (final w in wrongs) {
        expect(await svcWith().claimVerifiedReceipt(r, claimSignatureB64: w),
            0.0);
      }
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });
  });

  group('E3: resolver abuse', () {
    test('UPPERCASE resolver spelling still binds (same key — canonical '
        'compare is correct, not a bypass)', () async {
      final r = await persist(await signedReceipt());
      final svc = svcWith(fixedLocal: proverPubHex.toUpperCase());
      await svc.ready;
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          25.0);
    });

    test('interior/edge whitespace-padded resolver spelling binds the '
        'same key', () async {
      final r = await persist(await signedReceipt());
      final padded =
          '  ${proverPubHex.substring(0, 8)} ${proverPubHex.substring(8)}  ';
      expect(WorkReceipt.samePubkey(padded, proverPubHex), isTrue);
      final svc = svcWith(fixedLocal: padded);
      await svc.ready;
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          25.0);
    });

    test('"+5"-respelled resolver fails closed — not strict hex', () async {
      // Find a byte pair with a leading zero nibble so '0d' -> '+d'
      // preserves value under the OLD permissive decoder.
      final hex = proverPubHex;
      var idx = -1;
      for (var i = 0; i + 1 < hex.length; i += 2) {
        if (hex[i] == '0') {
          idx = i;
          break;
        }
      }
      if (idx < 0) return; // this prover key admits no respelling; skip
      final respelled =
          '${hex.substring(0, idx)}+${hex[idx + 1]}${hex.substring(idx + 2)}';
      expect(WorkReceipt.samePubkey(respelled, hex), isFalse);
      final r = await persist(await signedReceipt());
      final svc = svcWith(fixedLocal: respelled);
      await svc.ready;
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('throwing resolvers (sync and async) fail closed unspent', () async {
      final sync = svcWith(resolver: () => throw StateError('boom'));
      await sync.ready;
      final asyncT = svcWith(
          resolver: () => Future<String?>.error(StateError('async boom')));
      await asyncT.ready;
      final r1 = await persist(await signedReceipt());
      final r2 = await persist(await signedReceipt());
      expect(
          await sync.claimVerifiedReceipt(r1,
              claimSignatureB64: await claimSig(r1)),
          0.0);
      expect(
          await asyncT.claimVerifiedReceipt(r2,
              claimSignatureB64: await claimSig(r2)),
          0.0);
      expect((await db.getWorkReceipt(r1.receiptId))!['spent'], isFalse);
      expect((await db.getWorkReceipt(r2.receiptId))!['spent'], isFalse);
    });

    test('null / empty / whitespace resolver values refuse', () async {
      for (final v in <String?>[null, '', '   ', '\t\n']) {
        final svc = svcWith(resolver: () async => v);
        await svc.ready;
        final r = await persist(await signedReceipt());
        expect(
            await svc.claimVerifiedReceipt(r,
                claimSignatureB64: await claimSig(r)),
            0.0,
            reason: 'resolver value must refuse: "$v"');
        expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
      }
    });

    test('TOCTOU: resolver is invoked EXACTLY ONCE per claim — no '
        're-resolution window inside the guard chain', () async {
      var calls = 0;
      final svc = svcWith(resolver: () async {
        calls++;
        return proverPubHex;
      });
      await svc.ready;
      calls = 0; // hydration warms the held-key cache once — count only
      // the claim-time resolutions below.
      final r = await persist(await signedReceipt());
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          25.0);
      expect(calls, 1);
    });

    test('non-hex resolver value matching a non-hex proverPubkey '
        '(tier-1 string equality) still dies at the oracle — a real '
        'decodable key is forced by the sig check', () async {
      // proverPubkey='zztop' == resolver 'zztop' satisfies tier-1
      // equality, but no Ed25519 key can back it.
      final r = await persist(
          await signedReceipt(proverPubkey: 'zztop'));
      final svc = svcWith(fixedLocal: 'zztop');
      await svc.ready;
      expect(
          await svc.claimVerifiedReceipt(r, claimSignatureB64: ''),
          0.0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });
  });

  group('E4: race / cross-receipt replay', () {
    test('concurrent claims of one receipt mint exactly once', () async {
      final r = await persist(await signedReceipt());
      final sig = await claimSig(r);
      final svc = svcWith();
      await svc.ready;
      final results = await Future.wait([
        svc.claimVerifiedReceipt(r, claimSignatureB64: sig),
        svc.claimVerifiedReceipt(r, claimSignatureB64: sig),
        svc.claimVerifiedReceipt(r, claimSignatureB64: sig),
      ]);
      expect(results.where((m) => m > 0).length, 1);
      expect(svc.attestedBalance, 25.0);
    });

    test('concurrent claims from TWO service instances on one db — CAS '
        'still elects exactly one winner', () async {
      final r = await persist(await signedReceipt());
      final sig = await claimSig(r);
      final a = svcWith();
      final b = svcWith();
      await a.ready;
      await b.ready;
      final results = await Future.wait([
        a.claimVerifiedReceipt(r, claimSignatureB64: sig),
        b.claimVerifiedReceipt(r, claimSignatureB64: sig),
      ]);
      expect(results.where((m) => m > 0).length, 1);
    });

    test('claim sig minted for receipt A does not unlock receipt B',
        () async {
      final a = await persist(await signedReceipt(amount: 11.0));
      final b = await persist(await signedReceipt(amount: 22.0));
      final svc = svcWith();
      await svc.ready;
      expect(
          await svc.claimVerifiedReceipt(b,
              claimSignatureB64: await claimSig(a)),
          0.0);
      expect((await db.getWorkReceipt(b.receiptId))!['spent'], isFalse);
      // B still claims with its own sig.
      expect(
          await svc.claimVerifiedReceipt(b,
              claimSignatureB64: await claimSig(b)),
          22.0);
    });
  });

  group('E5: _paidBountyIds dedup', () {
    test('same bountyId pays once per process; empty id refuses', () async {
      final svc = svcWith();
      await svc.ready;
      expect(svc.awardBountyEscrow(amount: 10.0, bountyId: 'b1', cid: 'c'),
          10.0);
      expect(svc.awardBountyEscrow(amount: 10.0, bountyId: 'b1', cid: 'c'),
          0.0);
      expect(svc.awardBountyEscrow(amount: 10.0, bountyId: '', cid: 'c'),
          0.0);
      expect(svc.balance, 10.0);
    });

    test('dedup is durable — a new CreditService on the same db refuses '
        'the same bountyId (deterministic payout tx id)', () async {
      final first = svcWith();
      await first.ready;
      expect(
          first.awardBountyEscrow(amount: 10.0, bountyId: 'b1', cid: 'c'),
          10.0);
      await first.settled;

      // "Restart": fresh service instance, same database. Hydration
      // rebuilds _paidBountyIds from the persisted tx_bounty_payout_*
      // row, so a direct second payout is refused.
      final second = svcWith();
      await second.ready;
      final minted = second.awardBountyEscrow(
          amount: 10.0, bountyId: 'b1', cid: 'c');
      expect(minted, 0.0,
          reason: 'restart must not re-pay: the payout row id '
              'tx_bounty_payout_b1 is the durable dedup record');
      expect(second.balance, 10.0);
      // The persisted row carries the deterministic id.
      final rows = await db.getCreditTransactions();
      final payout = rows.firstWhere(
          (r) => (r['description'] as String).contains('Bounty Escrow'));
      expect(payout['id'], 'tx_bounty_payout_b1');
      expect(payout['referenceId'], 'c');
    });

    test('a refused call does NOT consume the bountyId — probes and '
        'unhydrated calls cannot burn a legit payout (E-REV4-B F3)',
        () async {
      final svc = svcWith();
      await svc.ready;
      // Attacker/bug calls with a non-positive amount first.
      expect(svc.awardBountyEscrow(amount: 0.0, bountyId: 'b9', cid: 'c'),
          0.0);
      // The real, escrowed payout for b9 still lands — the dedup guard
      // sits after the refusal gates, so a refused call never consumes
      // the id.
      expect(svc.awardBountyEscrow(amount: 10.0, bountyId: 'b9', cid: 'c'),
          10.0);
      // …but a PAID bounty is durably refused on replay.
      expect(svc.awardBountyEscrow(amount: 10.0, bountyId: 'b9', cid: 'c'),
          0.0);
    });
  });

  group('E6: no attested mint exists outside claimVerifiedReceipt', () {
    test('every other mint path leaves attestedBalance at 0', () async {
      final svc = svcWith();
      await svc.ready;
      svc.awardStorageCredits(
          sizeBytes: 10 * 1024 * 1024, peerCount: 1, porPassed: true);
      svc.awardComputeCredits(cauchyMb: 5.0, ocrPages: 2);
      svc.awardVerificationCredits(action: 'a', targetId: 't', amount: 10);
      svc.awardBountyEscrow(amount: 10.0, bountyId: 'bx', cid: 'c');
      svc.awardSponsorshipKickback(
          campaignId: 'k', grossCredits: 20.0, dwellTimeSeconds: 5.0);
      expect(svc.balance, greaterThan(0));
      expect(svc.attestedBalance, 0.0);
      expect(svc.transactions.every((t) => !t.isAttested), isTrue);
    });
  });

  group('E7: version ceiling ordering vs. signature verification', () {
    test('v=99 receipt with VALID verifier+claim sigs refuses BEFORE the '
        'oracle is invoked — ceiling is pre-verification', () async {
      var oracleCalls = 0;
      Future<bool> counting(Uint8List m, Uint8List s, String k) async {
        oracleCalls++;
        return receiptVerifier(m, s, k);
      }

      // The v99 artifact is fully self-consistent: signed under
      // 'alexandria:receipt:v99:' by the verifier key, and the claim sig
      // covers 'alexandria:receipt-claim:v99:{id}'. Only the ceiling
      // (receipt.v > WorkReceipt.wireVersion) can refuse it.
      final r = await persist(await signedReceipt(v: 99));
      expect(r.v, 99);
      expect(
          utf8.decode(r.signingPayload),
          startsWith('alexandria:receipt:v99:'));

      final svc = svcWith(verifier: counting);
      await svc.ready;
      final minted = await svc.claimVerifiedReceipt(r,
          claimSignatureB64: await claimSig(r));
      expect(minted, 0.0);
      expect(oracleCalls, 0,
          reason: 'the version ceiling must refuse BEFORE any signature '
              'verification — a future-version artifact never reaches the '
              'oracle (no oracle-observable distinction, row untouched)');
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });

    test('v=0 (below floor) also refuses before the oracle', () async {
      var oracleCalls = 0;
      Future<bool> counting(Uint8List m, Uint8List s, String k) async {
        oracleCalls++;
        return receiptVerifier(m, s, k);
      }

      final r = await persist(await signedReceipt(v: 0));
      final svc = svcWith(verifier: counting);
      await svc.ready;
      expect(
          await svc.claimVerifiedReceipt(r,
              claimSignatureB64: await claimSig(r)),
          0.0);
      expect(oracleCalls, 0);
      expect((await db.getWorkReceipt(r.receiptId))!['spent'], isFalse);
    });
  });
}
