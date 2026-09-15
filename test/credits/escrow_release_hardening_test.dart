// Review REV4a hardening regression tests — the fixes for the four live
// exploit classes the adversarial pass proved against the REV4 diff:
//  F1  payout<->release double-dip (the two dedup sets never met)
//  F2  'Bounty Escrow Hold' description marker was forgeable via
//      spendCredits' caller-controlled `reason`
//  F3  rotation history missed never-read outgoing keys
//      (identity_service.dart side)
//  F4  double.nan defeated every debit comparison guard
//  F5  debitEscrow accepted an empty referenceId releaseEscrow refused
import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart' hide CreditTransaction;
import 'package:alexandria/services/agent/beacon_models.dart'
    show bytesToHex;
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

/// In-memory SecureStorageService for the F3 identity-history tests.
class _FakeSecureStorage implements SecureStorageService {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);

  @override
  Future<void> deleteAll() async => data.clear();

  @override
  Future<bool> containsKey(String key) async => data.containsKey(key);
}

Map<String, dynamic> _txRow({
  required String id,
  required double amount,
  String type = 'verificationReward',
  String description = 'seeded',
  String? referenceId,
}) =>
    {
      'id': id,
      'timestamp': DateTime.now(),
      'type': type,
      'amount': amount,
      'description': description,
      'referenceId': referenceId,
      'hash': 'h_$id',
      'isAttested': false,
    };

/// Parks the releaseEscrow payout probe behind [probeGate] and (when
/// [holdPayoutRows]) parks the durable payout-row insert behind
/// [payoutGate] — lets a synchronous awardBountyEscrow run INSIDE the
/// probe await for the RE-A TOCTOU regression test.
class _ProbeGateDb extends AppDatabase {
  final Completer<void> probeGate = Completer<void>();
  final Completer<void> payoutGate = Completer<void>();
  bool armProbe = false;
  bool holdPayoutRows = false;
  bool probeParked = false;

  @override
  Future<bool> hasCreditTransaction(String id) async {
    if (armProbe) {
      probeParked = true;
      await probeGate.future;
    }
    return super.hasCreditTransaction(id);
  }

  @override
  Future<void> insertCreditTransaction(Map<String, dynamic> data) async {
    final id = data['id'] as String?;
    if (holdPayoutRows &&
        id != null &&
        id.startsWith('tx_bounty_payout_')) {
      await payoutGate.future;
    }
    return super.insertCreditTransaction(data);
  }
}

/// Simulates a hydration replay window that truncated every seeded row:
/// the windowed read returns nothing while targeted prefix/point reads
/// still see the real table — proves the dedup rebuild is prefix-based
/// (RE-W) without materialising a 100k-row pad.
class _EmptyReplayDb extends AppDatabase {
  @override
  Future<List<Map<String, dynamic>>> getCreditTransactions(
          {int limit = 200}) async =>
      <Map<String, dynamic>>[];
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  CreditService svc({AppDatabase? onDb}) =>
      CreditService(db: onDb ?? db, initialBalance: 0.0);

  void fund(CreditService s, double amount) {
    s.awardVerificationCredits(action: 'seed', targetId: 't', amount: amount);
  }

  // ─────────────────────────────────────────────────────────────────
  group('F1: payout<->release double-dip closed both directions', () {
    test('payout THEN release: releaseEscrow refuses an already-paid '
        'escrow (in-memory set)', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      expect(s.debitEscrow(amount: 20.0, referenceId: 'b1'), isTrue);
      expect(s.awardBountyEscrow(amount: 20.0, bountyId: 'b1', cid: 'c'),
          20.0);
      expect(await s.releaseEscrow(referenceId: 'b1'), 0.0);
      expect(s.balance, 50.0);
    });

    test('release THEN payout: awardBountyEscrow refuses an '
        'already-refunded escrow', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      s.debitEscrow(amount: 20.0, referenceId: 'b2');
      expect(await s.releaseEscrow(referenceId: 'b2'), 20.0);
      expect(
          s.awardBountyEscrow(amount: 20.0, bountyId: 'b2', cid: 'c'),
          0.0);
      expect(s.balance, 50.0);
    });

    test('the guard survives a restart — hydration rebuilds '
        '_paidBountyIds from the payout row', () async {
      final first = svc();
      await first.ready;
      fund(first, 50.0);
      first.debitEscrow(amount: 20.0, referenceId: 'b3');
      first.awardBountyEscrow(amount: 20.0, bountyId: 'b3', cid: 'c');
      await first.settled;

      final second = svc();
      await second.ready;
      expect(await second.releaseEscrow(referenceId: 'b3'), 0.0);
      expect(second.balance, 50.0);
    });

    test('a payout row written OUT-OF-BAND after hydration blocks the '
        'release via the durable hasCreditTransaction probe', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      s.debitEscrow(amount: 20.0, referenceId: 'b4');
      await s.settled;
      // Simulates a remote claim settling — the payout row lands in the
      // ledger without passing through THIS service instance, so the
      // in-memory _paidBountyIds never learned of it.
      await db.insertCreditTransaction(_txRow(
        id: 'tx_bounty_payout_b4',
        amount: 20.0,
        description: 'Bounty Escrow Payout (b4)',
        referenceId: 'bafy_x',
      ));
      expect(await s.releaseEscrow(referenceId: 'b4'), 0.0);
      expect(s.balance, 30.0);
    });

    test('a legit release still lands (guard ordering sanity)', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      s.debitEscrow(amount: 20.0, referenceId: 'b5');
      expect(await s.releaseEscrow(referenceId: 'b5'), 20.0);
      expect(s.balance, 50.0);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group('F2: hold rows carry a non-forgeable id shape', () {
    test('debitEscrow writes its hold under the tx_escrow_hold_ id '
        'prefix', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      s.debitEscrow(amount: 10.0, referenceId: 'b_id');
      final hold =
          s.transactions.where((t) => t.referenceId == 'b_id').single;
      expect(hold.id, startsWith('tx_escrow_hold_'));
      expect(hold.amount, -10.0);
    });

    test('spendCredits with a crafted reason cannot mint a releasable '
        '"hold"', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      expect(
          s.spendCredits(
              amount: 30.0,
              reason: 'Bounty Escrow Hold (totally legit)',
              referenceId: 'r_sp'),
          isTrue);
      expect(await s.releaseEscrow(referenceId: 'r_sp'), 0.0);
      expect(s.balance, 20.0);
    });

    test('a spoofed spend under a REAL referenceId does not inflate the '
        'legitimate refund', () async {
      final s = svc();
      await s.ready;
      fund(s, 100.0);
      s.debitEscrow(amount: 10.0, referenceId: 'b_real');
      s.spendCredits(
          amount: 40.0,
          reason: 'x Bounty Escrow Hold y',
          referenceId: 'b_real');
      expect(await s.releaseEscrow(referenceId: 'b_real'), 10.0);
      expect(s.balance, 60.0);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group('F4: non-finite amounts are refused at every ledger entry', () {
    test('debitEscrow(double.nan) is refused — NaN defeats every '
        'comparison guard', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      expect(s.debitEscrow(amount: double.nan, referenceId: 'nan1'),
          isFalse);
      expect(s.balance.isFinite, isTrue);
      expect(s.balance, 50.0);
    });

    test('a refused NaN hold cannot cascade into unbounded spending',
        () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      s.debitEscrow(amount: double.nan, referenceId: 'nan2');
      expect(s.spendCredits(amount: 1e6, reason: 'drain'), isFalse);
      expect(await s.releaseEscrow(referenceId: 'nan2'), 0.0);
    });

    test('spendCredits(double.nan / double.infinity) is refused',
        () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      expect(s.spendCredits(amount: double.nan, reason: 'nan'), isFalse);
      expect(s.spendCredits(amount: double.infinity, reason: 'inf'),
          isFalse);
      expect(s.balance, 50.0);
    });

    test('awardBountyEscrow(double.nan) is refused', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      expect(
          s.awardBountyEscrow(
              amount: double.nan, bountyId: 'nb', cid: 'c'),
          0.0);
      expect(s.balance, 50.0);
    });

    test('mint paths refuse non-finite awards', () async {
      final s = svc();
      await s.ready;
      expect(
          s.awardVerificationCredits(
              action: 'a', targetId: 't', amount: double.nan),
          0.0);
      expect(s.awardComputeCredits(cauchyMb: double.nan), 0.0);
      final receipt = s.awardSponsorshipKickback(
          campaignId: 'c', grossCredits: double.nan, dwellTimeSeconds: 1);
      expect(receipt.clientKickback, 0.0);
      expect(receipt.protocolFee, 0.0);
      expect(s.balance, 0.0);
      expect(s.balance.isFinite, isTrue);
    });

    test('a negative sponsorship gross cannot drain pools/treasury',
        () async {
      final s = svc();
      await s.ready;
      final treasuryBefore = s.protocolTreasury;
      final poolBefore = s.archivalCommonsPool;
      final receipt = s.awardSponsorshipKickback(
          campaignId: 'c', grossCredits: -100.0, dwellTimeSeconds: 1);
      expect(receipt.clientKickback, 0.0);
      expect(s.protocolTreasury, treasuryBefore);
      expect(s.archivalCommonsPool, poolBefore);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group('F5: referenceId contract symmetry + once-per-id semantics', () {
    test('debitEscrow refuses empty/whitespace referenceIds — the ids '
        'releaseEscrow refuses', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      expect(s.debitEscrow(amount: 10.0, referenceId: ''), isFalse);
      expect(s.debitEscrow(amount: 10.0, referenceId: '   '), isFalse);
      expect(await s.releaseEscrow(referenceId: ''), 0.0);
      expect(s.balance, 50.0);
    });

    test('documented semantics: a hold re-posted under an '
        'already-released referenceId is permanently unreleasable',
        () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      s.debitEscrow(amount: 20.0, referenceId: 'b_reuse');
      expect(await s.releaseEscrow(referenceId: 'b_reuse'), 20.0);
      // Cancel = once per referenceId, forever. A recycled id debits
      // (the caller's error) but can never be released — the durable
      // tx_escrow_release_b_reuse row already exists.
      expect(s.debitEscrow(amount: 15.0, referenceId: 'b_reuse'), isTrue);
      expect(await s.releaseEscrow(referenceId: 'b_reuse'), 0.0);
      expect(s.balance, 35.0);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group('F3: rotation history covers never-read outgoing keys', () {
    final algorithm = Ed25519();

    /// Writes key [kp] into secure storage the way a PRE-FEATURE install
    /// did — no pubkey-history append ever ran for it.
    Future<String> seedPreFeatureKey(
        _FakeSecureStorage storage, SimpleKeyPair kp) async {
      final pubHex =
          bytesToHex((await kp.extractPublicKey()).bytes);
      await storage.write('alexandria_identity_private_key',
          (await kp.extractPrivateKeyBytes())
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join());
      await storage.write('alexandria_identity_public_key', pubHex);
      await storage.write('alexandria_identity_created',
          DateTime.now().toIso8601String());
      return pubHex;
    }

    test('a pre-feature key rotated away before ANY read is still '
        'recorded in the history', () async {
      final storage = _FakeSecureStorage();
      final keyA = await algorithm.newKeyPair();
      final keyB = await algorithm.newKeyPair();
      final pubA = await seedPreFeatureKey(storage, keyA);
      final pubB =
          bytesToHex((await keyB.extractPublicKey()).bytes);

      final identity = IdentityService(storage);
      addTearDown(identity.dispose);

      // Rotate straight to B without ever calling getIdentity — the
      // serve-time history append never ran for A.
      await identity.importIdentity(
          Uint8List.fromList(await keyB.extractPrivateKeyBytes()));

      expect(await identity.knownLocalPubkeyHexes(),
          containsAll({pubA, pubB}),
          reason: 'the outgoing key must enter the history at REPLACE '
              'time — not only at serve time');
    });

    test('a never-read key deleted then replaced is still recorded',
        () async {
      final storage = _FakeSecureStorage();
      final keyA = await algorithm.newKeyPair();
      final keyB = await algorithm.newKeyPair();
      final pubA = await seedPreFeatureKey(storage, keyA);
      final pubB =
          bytesToHex((await keyB.extractPublicKey()).bytes);

      final identity = IdentityService(storage);
      addTearDown(identity.dispose);

      await identity.deleteIdentity();
      await identity.importIdentity(
          Uint8List.fromList(await keyB.extractPrivateKeyBytes()));

      expect(await identity.knownLocalPubkeyHexes(),
          containsAll({pubA, pubB}));
    });

    test('a failing history store never blocks the identity mutation',
        () async {
      final storage = _FakeSecureStorage();
      final keyA = await algorithm.newKeyPair();
      final keyB = await algorithm.newKeyPair();
      await seedPreFeatureKey(storage, keyA);

      // Corrupt the history blob so every append read chokes.
      await storage.write('alexandria_identity_pubkey_history',
          '{not json');

      final identity = IdentityService(storage);
      addTearDown(identity.dispose);
      // The rotation must still succeed — history is best-effort.
      final id = await identity.importIdentity(
          Uint8List.fromList(await keyB.extractPrivateKeyBytes()));
      expect(bytesToHex(id.publicKey),
          bytesToHex((await keyB.extractPublicKey()).bytes));
    });
  });

  // ─────────────────────────────────────────────────────────────────
  group('REV4 re-eval fixes (RE-A / RE-B1 / RE-B2 / RE-W)', () {
    test('RE-A: an awardBountyEscrow landing DURING the payout-probe '
        'await is observed by the post-await _paidBountyIds re-check — '
        'the release refuses instead of refunding on top of the mint',
        () async {
      final gdb = _ProbeGateDb();
      addTearDown(gdb.close);
      final s = svc(onDb: gdb);
      await s.ready;
      fund(s, 50.0);
      expect(s.debitEscrow(amount: 20.0, referenceId: 'v'), isTrue);
      await s.settled;

      gdb.armProbe = true;
      gdb.holdPayoutRows = true;
      final releaseF = s.releaseEscrow(referenceId: 'v');
      while (!gdb.probeParked) {
        await Future<void>.delayed(Duration.zero);
      }

      // The interleaved claim-settlement mints and records 'v' in
      // _paidBountyIds while its payout row stays parked — invisible
      // to the durable probe.
      expect(s.awardBountyEscrow(amount: 20.0, bountyId: 'v', cid: 'c'),
          20.0);
      expect(s.balance, 50.0);

      gdb.probeGate.complete();
      expect(await releaseF, 0.0,
          reason: 'the in-memory re-check after the probe await must '
              'see the racing mint');
      expect(s.balance, 50.0);

      gdb.payoutGate.complete();
      await s.settled;
      // Canonical across restart: hold(-20)+payout(+20) = 50, no
      // phantom release row.
      final s2 = svc(onDb: gdb);
      await s2.ready;
      expect(s2.balance, 50.0);
    });

    test('RE-B1: hold ids carry wall-clock micros — a recycled '
        '<ref>_<seq> id cannot drop the re-posted debit after restart',
        () async {
      final s1 = svc();
      await s1.ready;
      fund(s1, 100.0);
      expect(s1.debitEscrow(amount: 1.0, referenceId: 'probe'), isTrue);
      final probeRow =
          s1.transactions.firstWhere((t) => t.referenceId == 'probe');
      // New shape: tx_escrow_hold_<ref>_<micros>_<seq>.
      final parts = probeRow.id.split('_');
      expect(parts.length, greaterThanOrEqualTo(6));
      final seq = int.parse(parts.last);
      await s1.settled;

      // A "pre-restart" row occupying the bare <ref>_<seq> id the old
      // build would have minted next.
      await db.insertCreditTransaction(_txRow(
        id: 'tx_escrow_hold_shared_${seq + 1}',
        amount: -20.0,
        type: 'priorityAccessDebit',
        description: 'Bounty Escrow Hold (shared)',
        referenceId: 'shared',
      ));

      final s2 = svc();
      await s2.ready;
      expect(s2.balance, 79.0); // 100 - 1 probe - 20 seeded hold

      expect(s2.debitEscrow(amount: 20.0, referenceId: 'shared'),
          isTrue);
      await s2.settled;
      final holdRows = (await db.getCreditTransactions())
          .where((r) =>
              (r['id'] as String).startsWith('tx_escrow_hold_shared_'))
          .toList();
      expect(holdRows.length, 2,
          reason: 'the wall-clock id component must keep the re-posted '
              'hold a distinct primary key — insertOrIgnore cannot '
              'drop a real debit');

      expect(await s2.releaseEscrow(referenceId: 'shared'), 40.0);
      await s2.settled;
      final s3 = svc();
      await s3.ready;
      expect(s3.balance, 99.0); // 100 - 1 - 20 - 20 + 40
    });

    test('RE-B2: a pre-REV4a legacy hold row (auto id + exact marker '
        'description) is releasable after upgrade', () async {
      await db.insertCreditTransaction(_txRow(
        id: 'tx_1700000000000000_7',
        amount: -20.0,
        type: 'priorityAccessDebit',
        description: 'Bounty Escrow Hold (legacy_ref)',
        referenceId: 'legacy_ref',
      ));
      final s = svc();
      await s.ready;
      expect(await s.releaseEscrow(referenceId: 'legacy_ref'), 20.0);
      expect(s.balance, 20.0); // -20 hold + 20 release
    });

    test('RE-B2: the legacy fallback is EXACT-match — a spendCredits '
        'debit can never wear the marker description', () async {
      final s = svc();
      await s.ready;
      fund(s, 50.0);
      // spendCredits appends ' (incl. 5% treasury fee)' — the stored
      // description is never exactly 'Bounty Escrow Hold (<ref>)'.
      expect(
          s.spendCredits(
              amount: 30.0,
              reason: 'Bounty Escrow Hold (forged)',
              referenceId: 'forged'),
          isTrue);
      expect(await s.releaseEscrow(referenceId: 'forged'), 0.0);
      expect(s.balance, 20.0);
    });

    test('RE-D: a hydrated hold row with a non-finite amount is '
        'refused', () async {
      await db.insertCreditTransaction(_txRow(
        id: 'tx_escrow_hold_inf_0',
        amount: double.negativeInfinity,
        type: 'priorityAccessDebit',
        description: 'Bounty Escrow Hold (inf)',
        referenceId: 'inf',
      ));
      final s = svc();
      await s.ready;
      expect(await s.releaseEscrow(referenceId: 'inf'), 0.0);
      expect(s.balance.isFinite, isTrue);
    });

    test('RE-W: dedup rebuild reads the id-prefix listings, not the '
        'replay window — sets stay complete when the window truncates',
        () async {
      final edb = _EmptyReplayDb();
      addTearDown(edb.close);
      await edb.insertCreditTransaction(_txRow(
        id: 'tx_bounty_payout_w1',
        amount: 20.0,
        description: 'Bounty Escrow Payout (w1)',
        referenceId: 'cid_w1',
      ));
      await edb.insertCreditTransaction(_txRow(
        id: 'tx_escrow_release_w2',
        amount: 15.0,
        type: 'priorityAccessDebit',
        description: 'Escrow Release (w2)',
        referenceId: 'w2',
      ));

      final s = svc(onDb: edb);
      await s.ready;
      // Every replayed row was "beyond the window" — yet the dedup
      // sets must still know these ids.
      expect(s.isBountyPayoutRecorded('w1'), isTrue);
      expect(s.isEscrowReleased('w2'), isTrue);
      expect(s.awardBountyEscrow(amount: 20.0, bountyId: 'w1', cid: 'c'),
          0.0);
      expect(await s.releaseEscrow(referenceId: 'w2'), 0.0);
    });

    test('RE-W documented bound: a hold beyond the replay window '
        'cannot be released (ids are listable, amounts are not) — '
        'but a PAID beyond-window escrow still refuses via dedup',
        () async {
      final edb = _EmptyReplayDb();
      addTearDown(edb.close);
      await edb.insertCreditTransaction(_txRow(
        id: 'tx_escrow_hold_w3_1700000000000000_0',
        amount: -20.0,
        type: 'priorityAccessDebit',
        description: 'Bounty Escrow Hold (w3)',
        referenceId: 'w3',
      ));
      await edb.insertCreditTransaction(_txRow(
        id: 'tx_escrow_hold_w4_1700000000000001_0',
        amount: -20.0,
        type: 'priorityAccessDebit',
        description: 'Bounty Escrow Hold (w4)',
        referenceId: 'w4',
      ));
      await edb.insertCreditTransaction(_txRow(
        id: 'tx_bounty_payout_w4',
        amount: 20.0,
        description: 'Bounty Escrow Payout (w4)',
        referenceId: 'cid_w4',
      ));

      final s = svc(onDb: edb);
      await s.ready;
      // Unpaid but beyond-window: unreleasable (documented bound —
      // the amount is unreadable through the DAO surface).
      expect(await s.releaseEscrow(referenceId: 'w3'), 0.0);
      // Paid AND beyond-window: refused by the dedup set — never a
      // refund-on-top-of-payout double-mint.
      expect(await s.releaseEscrow(referenceId: 'w4'), 0.0);
    });
  });
}
