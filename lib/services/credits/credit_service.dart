import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database.dart' hide CreditTransaction, WorkReceipt;
import '../agent/beacon_models.dart' show bytesToHex, hexToBytes;
import '../identity_service.dart';
import 'credit_models.dart';
import 'poch_service.dart';
import 'work_receipt.dart';

/// Resolves the public keys (any spelling — canonicalized internally)
/// the local node CURRENTLY holds — the identities
/// [CreditService.claimVerifiedReceipt] may bind as prover and the keys
/// whose attested mints the egress gate may draw on. Under the
/// single-identity model this resolves to a one-element set; the
/// Set-returning signature is the multi-identity sharding seam
/// (WORKING_ON residual — `attested_pubkey` rows sum only over
/// currently-held keys, so a rotated-away key's attested value stops
/// backing egress the moment it leaves the set). Returns null when the
/// node has no usable identity (claims then refuse). Injected as a
/// function — the same ambient-authority idiom as
/// [ReceiptSignatureVerifier] — so [CreditService] never takes a
/// concrete IdentityService dependency.
typedef LocalProverPubkeyResolver = FutureOr<Set<String>?> Function();

/// Resolves every public key (canonical lowercase hex) the local node
/// has EVER held — the current identity plus retired rotation
/// predecessors (Safety item 3). [CreditService.claimVerifiedReceipt]
/// treats a receipt verifier-signed by ANY of them as self-issued: a
/// rotated-away key is still "local" for self-dealing purposes, so
/// rotation can never launder a retired key into a foreign verifier.
///
/// The resolver is deliberately FAIL-OPEN on absence: a null return (or
/// an empty set) degrades the guard to the current-key-only check —
/// missing history must never break honest claims.
typedef KnownLocalPubkeysResolver = FutureOr<Set<String>?> Function();

/// Provider for CreditService
final creditServiceProvider = ChangeNotifierProvider<CreditService>((ref) {
  final pochService = ref.read(pochServiceProvider);
  final service = CreditService(
    pochService: pochService,
    db: ref.read(databaseProvider),
    // The signature oracle for in-path receipt verification (ALX-012):
    // claimVerifiedReceipt fails closed when this is absent. The receipt
    // pins its verifier pubkey as a hex string — a malformed key decodes
    // to nothing and verifies false, never throws.
    receiptVerifier: (message, signature, publicKeyHex) async {
      try {
        return await ref.read(identityServiceProvider).verifySignature(
            message, signature, Uint8List.fromList(hexToBytes(publicKeyHex)));
      } catch (_) {
        return false;
      }
    },
    // The local prover binding is ambient identity, not caller input
    // (REV3 review): a claim can no longer ASSERT a prover key — it must
    // resolve to one of the node's CURRENTLY-HELD keys. No identity →
    // null → every claim refuses. A missing identity is never
    // auto-created here: minting a fresh key could never satisfy the
    // prover binding anyway. The Set shape is the multi-identity seam —
    // today getIdentity yields at most one key.
    localProverPubkeys: () async {
      try {
        final identity = await ref.read(identityServiceProvider).getIdentity();
        return identity == null ? null : {bytesToHex(identity.publicKey)};
      } catch (_) {
        return null;
      }
    },
    // The append-only local-key history (Safety item 3): a receipt
    // verifier-signed by a RETIRED rotation predecessor is still
    // self-issued. A resolving failure degrades to current-key-only —
    // never fails closed on absent history.
    knownLocalPubkeys: () async {
      try {
        return await ref.read(identityServiceProvider).knownLocalPubkeyHexes();
      } catch (_) {
        return null;
      }
    },
  );
  // Hydration is kicked off in the constructor; surface it here so the
  // intent is explicit. Mutators stay gated until it lands (see
  // [CreditService._hydratedComplete]).
  unawaited(service.ready);
  return service;
});

/// Provider for user credit balance
final creditBalanceProvider = Provider<double>((ref) {
  final service = ref.watch(creditServiceProvider);
  return service.balance;
});

/// Provider for recent credit transactions
final creditTransactionsProvider = Provider<List<CreditTransaction>>((ref) {
  final service = ref.watch(creditServiceProvider);
  return service.transactions;
});

/// Core economic ledger managing Archival Credits, multi-resource rewards,
/// and protocol fee allocations (ALX-005).
class CreditService extends ChangeNotifier {
  final PoCHService? _pochService;
  final AppDatabase? _db;

  /// Ed25519 verification oracle used INSIDE [claimVerifiedReceipt]
  /// (ALX-012). When null the claim path fails closed — a service without
  /// a verifier can never mint attested value.
  final ReceiptSignatureVerifier? _receiptVerifier;

  /// Ambient resolver for EVERY public key the node CURRENTLY holds —
  /// the identities [claimVerifiedReceipt] may bind as prover (quorum
  /// REV3) and the keys whose scoped attested mints back egress. When
  /// null, or when it resolves to null/empty, every claim fails closed:
  /// there is no longer a caller-supplied "local" key to assert.
  final LocalProverPubkeyResolver? _localProverPubkeys;

  /// Ambient resolver for EVERY public key this node has ever held —
  /// current identity plus retired rotation predecessors (Safety item
  /// 3). [claimVerifiedReceipt] refuses receipts verifier-signed by any
  /// of them, so key rotation cannot make a self-signed receipt look
  /// foreign-attested. Null resolver, or a null/empty resolution,
  /// degrades to the current-key-only check — absent history must not
  /// break claims.
  final KnownLocalPubkeysResolver? _knownLocalPubkeys;

  double _balance;

  /// Per-key accounting of attested MINTS (positive `isAttested` rows),
  /// keyed by [WorkReceipt.canonicalPubkey] of the prover the receipt
  /// bound (schema v7 `attested_pubkey`). The `''` key is the UNSCOPED
  /// bucket: pre-v7 legacy rows and any attested credit minted without a
  /// prover binding — counted toward every held-key set, preserving the
  /// single-identity wallet-wide semantics. Rebuilt from the ledger on
  /// hydration by [_rebuildBalance].
  final Map<String, double> _attestedMintedByKey = {};

  /// Total attested value consumed — attested-flagged debit rows
  /// (external egress) plus the attested share ordinary debits burned
  /// once the unattested pool ran dry (see [_burnForDebit]). Burns hit
  /// the egress-ELIGIBLE pool first: value minted under a no-longer-held
  /// key is burned LAST, so a rotation can never launder stranded
  /// attested value into an egress budget.
  double _attestedBurned = 0.0;

  /// Canonical spellings of the prover keys the node CURRENTLY holds,
  /// cached from [_localProverPubkeys] so the synchronous
  /// [attestedBalance] getter has a held-key set to sum over. Refreshed
  /// at hydration, on every claim, and at every attested-debit write;
  /// the durable egress guard ([AppDatabase.insertAttestedDebitIfCovered])
  /// re-resolves the keys at write time. A stale cache can misreport
  /// the fast path in EITHER direction (a just-rotated-out key's mints
  /// can linger) — the durable gate is the authority, the cache is the
  /// fast path.
  Set<String> _heldAttestedKeys = const {};

  /// Unscoped-bucket sentinel for [_attestedMintedByKey] — the empty
  /// string can never be a canonical pubkey ([WorkReceipt.samePubkey]
  /// fails closed on empty input).
  static const String _kUnscopedAttested = '';

  double _archivalCommonsPool;
  double _protocolTreasury;

  double _totalStorageEarned = 0.0;
  double _totalComputeEarned = 0.0;
  double _totalVerificationEarned = 0.0;
  double _totalSponsorshipKickbacks = 0.0;
  double _totalSpent = 0.0;
  double _totalFeesContributed = 0.0;

  final List<CreditTransaction> _transactions = [];

  /// Resolves once persisted state (daily mint caps + ledger history) has
  /// been loaded from [_db]. Never rejects — on failure the service
  /// degrades gracefully to in-memory operation.
  late final Future<void> _hydrated;

  /// Set when [_hydrate] has finished (successfully or degraded), and
  /// immediately in pure in-memory mode. Synchronous mutators cannot
  /// await [_hydrated], so they refuse to run while this is false in
  /// persistent mode: acting on phantom state (empty mint-cap counters,
  /// an un-loaded ledger balance) let pre-hydration calls bypass the
  /// daily cap and overspend the real ledger (E-T2 #1/#2). The honest
  /// tradeoff: a caller racing the first milliseconds of startup loses
  /// the award/spend rather than corrupting persisted state — no
  /// legitimate flow can reach the service before [ready] resolves.
  bool _hydratedComplete = false;

  /// Deterministic ledger id for the one-time genesis welcome
  /// allocation. Two instances racing a fresh database both write this
  /// id; the second insert violates the primary key, is swallowed by
  /// [_persistWrite], and the duplicate row is dropped — genesis can
  /// never be persisted twice (E-T2 #3).
  static const String _kGenesisTxId = 'tx_genesis';

  /// Deterministic payout-row id prefix — the ledger row doubles as the
  /// persisted "already paid" record for a bounty, so hydration can
  /// rebuild [_paidBountyIds] across restarts.
  static const String _kBountyPayoutTxPrefix = 'tx_bounty_payout_';

  /// Deterministic release-row id prefix — the ledger row doubles as
  /// the persisted "already released" record for an escrow referenceId,
  /// so hydration can rebuild [_releasedEscrowIds] across restarts.
  static const String _kEscrowReleaseTxPrefix = 'tx_escrow_release_';

  /// Deterministic hold-row id prefix — [debitEscrow] writes its hold
  /// under `tx_escrow_hold_<referenceId>_<micros>_<seq>` so
  /// [releaseEscrow] can recognise a genuine escrow hold by a shape NO
  /// caller-controlled input can forge (REV4a review F2): [spendCredits]
  /// rows always carry auto-generated `tx_<micros>_<seq>` ids and can
  /// never wear this prefix, so a crafted `reason` string can no longer
  /// mint a releasable pseudo-hold. The micros+seq suffix keeps two
  /// holds under one referenceId distinct — and keeps a POST-RESTART
  /// hold distinct from any row a previous process persisted under the
  /// same referenceId: [_txSeq] is process-scoped, so without the
  /// wall-clock component a recycled `<ref>_<seq>` id would repeat a
  /// persisted primary key and insertOrIgnore would silently drop a
  /// REAL debit (RE-B1: the durable ledger then loses the hold while
  /// the in-memory list keeps it — a phantom refund on next hydrate).
  static const String _kEscrowHoldTxPrefix = 'tx_escrow_hold_';

  /// Human-readable description text on [debitEscrow] hold rows.
  /// DISPLAY-ONLY: releasability is decided by the
  /// [_kEscrowHoldTxPrefix] id shape plus type+sign, never by this
  /// string — caller-controlled `reason` text can contain it, so it
  /// must never gate a refund (the pre-REV4a predicate did exactly that
  /// and made every hold forgeable).
  static const String _kEscrowHoldMarker = 'Bounty Escrow Hold';

  /// Monotonic per-process transaction-id counter (Safety 6f). The old
  /// `_transactions.length` suffix reset to 0 on every process start,
  /// so a micros+length collision could drop a real ledger row via the
  /// db's insertOrIgnore. The counter never resets within a process —
  /// an in-process collision now needs identical microsecond stamps AND
  /// identical sequence values, which the increment makes impossible.
  static int _txSeq = 0;

  /// Description marker identifying genesis rows, including rows written
  /// by older builds that used a random id.
  static const String _kGenesisMarker = 'Genesis Common Heritage';

  /// Outstanding best-effort writes to [_db], tracked so tests and
  /// shutdown paths can await durability via [settled].
  final Set<Future<void>> _pendingWrites = {};

  /// Bounty ids already paid by [awardBountyEscrow] this process —
  /// belt-level dedup (REV3 review): the payout primitive itself refuses
  /// a second payout for the same id, so a bypassed or replayed claim
  /// layer can never double-mint escrow. Also consulted by
  /// [releaseEscrow] (REV4a review F1): an escrow already PAID OUT must
  /// never be refunded — the release would double-mint. Repopulated at
  /// hydration from persisted `tx_bounty_payout_*` rows; out-of-band
  /// payouts are additionally caught by the [releaseEscrow] point query.
  final Set<String> _paidBountyIds = {};

  /// Escrow referenceIds already refunded by [releaseEscrow] —
  /// belt-level dedup identical in shape to [_paidBountyIds]: the
  /// primitive refuses a second release for the same id so a replayed
  /// cancel can never double-mint a refund. Repopulated at hydration
  /// from persisted `tx_escrow_release_*` rows, so a restart cannot
  /// re-release through a fresh service instance. Also consulted by
  /// [awardBountyEscrow] (REV4a review F1): an escrow already REFUNDED
  /// must never be paid out — the payout would mint from nothing.
  ///
  /// DOCUMENTED SEMANTICS: release dedup is ONCE PER referenceId,
  /// forever. A hold re-posted under an already-released referenceId is
  /// permanently unreleasable — referenceIds must never be recycled
  /// (cancel = once per referenceId). The deterministic release row id
  /// `tx_escrow_release_$referenceId` enforces the same rule durably:
  /// a second release row for the id is insertOrIgnore-dropped, so a
  /// repeat refund could never become canonical anyway.
  final Set<String> _releasedEscrowIds = {};

  CreditService({
    PoCHService? pochService,
    AppDatabase? db,
    ReceiptSignatureVerifier? receiptVerifier,
    LocalProverPubkeyResolver? localProverPubkeys,
    KnownLocalPubkeysResolver? knownLocalPubkeys,
    // Backward-compatible single-identity spelling of
    // [localProverPubkeys] — the resolved key is wrapped into a
    // one-element set. Used only when [localProverPubkeys] is absent.
    FutureOr<String?> Function()? localProverPubkeyHex,
    double initialBalance = 100.0, // Initial welcome grant for new users
  })  : _pochService = pochService,
        _db = db,
        _receiptVerifier = receiptVerifier,
        _localProverPubkeys = localProverPubkeys ??
            (localProverPubkeyHex == null
                ? null
                : () async {
                    final key = await localProverPubkeyHex();
                    return key == null ? null : {key};
                  }),
        _knownLocalPubkeys = knownLocalPubkeys,
        // Persistent mode starts at 0.0 — never at the phantom
        // [initialBalance] — so no spend can race the real ledger
        // balance before hydration rebuilds it (E-T2 #2).
        _balance = db == null ? initialBalance : 0.0,
        _archivalCommonsPool = 250.0,
        _protocolTreasury = 50.0 {
    if (db == null) {
      // Pure in-memory mode (backward compatible): genesis is recorded
      // synchronously so [balance] and [transactions] are immediately sane.
      _hydrated = Future<void>.value();
      _hydratedComplete = true;
      if (initialBalance > 0) {
        _recordTransaction(
          id: _kGenesisTxId,
          type: CreditType.verificationReward,
          amount: initialBalance,
          description: '$_kGenesisMarker Welcome Allocation',
          isAttested: false,
        );
      }
    } else {
      // Persistent mode: genesis and balance are decided by the ledger,
      // so they must wait for hydration (see [_hydrate]).
      _hydrated = _hydrate(initialBalance);
    }
  }

  // Getters
  double get balance => _balance;
  double get archivalCommonsPool => _archivalCommonsPool;
  double get protocolTreasury => _protocolTreasury;
  double get totalStorageEarned => _totalStorageEarned;
  double get totalComputeEarned => _totalComputeEarned;
  double get totalVerificationEarned => _totalVerificationEarned;
  double get totalSponsorshipKickbacks => _totalSponsorshipKickbacks;
  double get totalSpent => _totalSpent;
  double get totalFeesContributed => _totalFeesContributed;
  List<CreditTransaction> get transactions =>
      List.unmodifiable(_transactions.reversed);

  /// Completes when persisted state (daily mint caps + ledger history) has
  /// been hydrated from the database. Resolves immediately when no
  /// database is attached. Never rejects. In persistent mode, mutating
  /// entry points refuse to run until this completes — see
  /// [_hydratedComplete].
  Future<void> get ready => _hydrated;

  /// Returns true (after logging) when a mutating call arrived while
  /// persistent state was still unhydrated — see [_hydratedComplete] for
  /// why refusing is strictly safer than acting on phantom state.
  bool _rejectIfUnhydrated(String op) {
    if (_db == null || _hydratedComplete) return false;
    debugPrint('CreditService: $op refused — persistent state is not '
        'hydrated yet; await CreditService.ready before mutating');
    return true;
  }

  /// Completes when hydration has finished AND every database write
  /// queued so far has landed (or failed harmlessly). Awards write through
  /// unawaited by design, so tests and shutdown paths that need durability
  /// guarantees should await this rather than [ready].
  Future<void> get settled =>
      Future.wait<void>(<Future<void>>[_hydrated, ..._pendingWrites]);

  /// Portion of the balance backed by foreign verifier-signed work
  /// receipts (verifier pubkey != local identity — ALX-010). This is the
  /// only value eligible to egress to external systems; the attested
  /// spend path ([spendCredits] `isAttested: true`) enforces it
  /// atomically inside the debit. NET of spending — internal debits
  /// consume unattested value first, then attested, and egress debits
  /// consume attested value directly, so attestation already spent can
  /// never back a second egress (E-T3 #1).
  ///
  /// PROVER-KEY-SCOPED (schema v7 — the multi-identity residual closed):
  /// attested mints are recorded under `attested_pubkey` and summed over
  /// the CURRENTLY-HELD key set ([_heldAttestedKeys]) plus the unscoped
  /// legacy bucket — value minted under a rotated-out key stops backing
  /// egress the moment the resolver drops it. Under single-identity the
  /// held set is exactly the one key every mint is scoped to, so the
  /// sum reproduces the old wallet-wide semantics bit-for-bit. The
  /// durable re-check at write time
  /// ([AppDatabase.insertAttestedDebitIfCovered]) is the authority when
  /// this instance's view is stale.
  double get attestedBalance {
    var minted = _attestedMintedByKey[_kUnscopedAttested] ?? 0.0;
    for (final key in _heldAttestedKeys) {
      minted += _attestedMintedByKey[key] ?? 0.0;
    }
    return (minted - _attestedBurned)
        .clamp(0.0, _balance < 0.0 ? 0.0 : _balance);
  }

  /// Self-certified value: spendable inside Alexandria (replication fees,
  /// bounties) but barred from egress. Clamped at zero so a partial ledger
  /// can never report a negative internal balance.
  double get unattestedBalance =>
      (_balance - attestedBalance).clamp(0.0, double.infinity);

  /// Protocol micro-fee rate on spendable transactions (5% - ALX-005 §5.2)
  static const double protocolFeeRate = 0.05;

  /// Minimum receipt wire version eligible to claim (ALX-012). Accepts
  /// {1, 2} — an Ethereum-style {previous, current} grace window so
  /// pre-domain v1 receipts already in flight stay claimable while their
  /// 24h TTL bounds the legacy exposure; a future bump retires a scheme.
  /// The claimable window is also CAPPED at [WorkReceipt.wireVersion]:
  /// this node must not attest a scheme it does not implement, so a
  /// future-version artifact mints nothing on this build. Receipts
  /// outside the window are still REPRESENTABLE in the ledger — they are
  /// persisted, just never claimable.
  static const int minClaimableWireVersion = 1;

  /// Daily accrual caps per action type (ALX-005 §6.1 anti-gaming invariant).
  static const Map<CreditType, double> dailyMintCaps = {
    CreditType.storageReward: 200.0,
    CreditType.computeReward: 150.0,
    CreditType.verificationReward: 100.0,
    CreditType.sponsorshipKickback: 150.0,
  };

  /// Credits minted today per type, keyed by UTC day.
  final Map<String, double> _dailyMinted = {};

  static String _dayKey() {
    final now = DateTime.now().toUtc();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Clamps a mint award to the remaining daily allowance for [type].
  /// Returns the effective award (0 when the daily cap is exhausted).
  /// The counter is written through to [DailyMinted] so caps survive
  /// restarts (the "~600C/day per restart" farming vector, ALX-005 §6.1).
  double _capDailyMint(CreditType type, double requested) {
    // Non-finite requests mint nothing (REV4a review F4): NaN defeats
    // every comparison below (`NaN <= 0`, `NaN.clamp`) and would flow
    // straight into the ledger as an unbounded mint.
    if (!requested.isFinite) return 0.0;
    final cap = dailyMintCaps[type];
    if (cap == null) return requested;
    final dayKey = _dayKey();
    final key = '$dayKey:${type.name}';
    final remaining = (cap - (_dailyMinted[key] ?? 0.0)).clamp(0.0, cap);
    final granted = requested.clamp(0.0, remaining);
    if (granted > 0) {
      final total = (_dailyMinted[key] ?? 0.0) + granted;
      _dailyMinted[key] = total;
      final db = _db;
      if (db != null) {
        _persistWrite(db.upsertDailyMinted(dayKey, type.name, total));
      }
    }
    return granted;
  }

  /// Dynamic Rarity Weight Function (ALX-005 §4.1). Multipliers above 1.0
  /// require [rarityAttested]: an independent peer's attestation that the
  /// content is genuinely under-replicated. A claimant's own self-reported
  /// peer count can never unlock rarity rewards (self-dealing guard).
  ///
  /// [rarityAttested] is deliberately NOT wire-reachable: it is sealed to
  /// this library and `test/` via @visibleForTesting — every production
  /// caller must omit it (the analyzer flags any other use), so a remote
  /// agent, UI action or forked client can never self-declare attestation.
  /// Until a foreign-attestation oracle derives the flag internally, all
  /// production mints evaluate at the flat 1.0x weight.
  static double rarityWeightFor(int peerCount,
      {@visibleForTesting bool rarityAttested = false}) {
    if (!rarityAttested) return 1.0;
    if (peerCount <= 1) return 5.0; // Critically Endangered
    if (peerCount == 2) return 3.0; // Vulnerable
    if (peerCount < 5) return 1.5; // Near-Safe
    return 1.0; // Healthy
  }

  /// Award credits for Proof of Retrievability (PoR) storage retention (Pillar 1)
  /// [rarityAttested] is sealed to tests (@visibleForTesting) — production
  /// derives rarity attestation internally, never from a caller-supplied
  /// argument (see [rarityWeightFor]).
  double awardStorageCredits({
    required int sizeBytes,
    required int peerCount,
    required bool porPassed,
    String? cid,
    @visibleForTesting bool rarityAttested = false,
  }) {
    if (_rejectIfUnhydrated('awardStorageCredits')) return 0.0;
    if (!porPassed) {
      // Slashing penalty for failed PoR challenge. Only the debit the
      // runtime floor actually applies is persisted (round-1 red
      // finding): the old path clamped _balance to 0 but wrote the FULL
      // -penalty row, so _rebuildBalance replayed phantom debt the
      // runtime never charged — a restart reported a lower balance than
      // the live service. The penalty deliberately does NOT run
      // _burnForDebit: slashing may never eat foreign-verifier-signed
      // (attested) value — _attestedBalance is left alone and the
      // attestedBalance getter clamps the transient raw surplus. The
      // persisted row is `storageReward`-typed negative, so replay
      // applies the same balance floor and the same attested carve-out.
      const penalty = 5.0;
      final applied = _balance < penalty ? _balance : penalty;
      _balance -= applied;
      if (applied > 0.0) {
        _recordTransaction(
          type: CreditType.storageReward,
          amount: -applied,
          description:
              'PoR Challenge Failure Penalty (CID: ${cid ?? "unknown"})',
          referenceId: cid,
          isAttested: false,
        );
      }
      notifyListeners();
      return -penalty;
    }

    // A non-positive byte count has proven nothing — the reward clamp's
    // 0.1 floor would mint +0.1 ℭ on garbage input (round-1 red
    // finding: mint-on-garbage). Reject before _capDailyMint so the
    // invalid call consumes no daily allowance either.
    if (sizeBytes <= 0) return 0.0;

    final rarityWeight =
        rarityWeightFor(peerCount, rarityAttested: rarityAttested);

    final mbSize = sizeBytes / (1024 * 1024);
    final earned = _capDailyMint(CreditType.storageReward,
        (mbSize * 0.1 * rarityWeight).clamp(0.1, 50.0));
    if (!earned.isFinite || earned <= 0) return 0.0;

    _balance += earned;
    _totalStorageEarned += earned;

    _pochService?.recordPoRChallengeAnswered();

    _recordTransaction(
      type: CreditType.storageReward,
      amount: earned,
      description:
          'PoR Storage Reward (${rarityWeight}x rarity, CID: ${cid ?? "block"})',
      referenceId: cid,
      // Self-certified PoR: rarityAttested unlocks the multiplier but is
      // NOT a foreign verifier-signed work receipt, so the minted value
      // remains unattested.
      isAttested: false,
    );

    notifyListeners();
    return earned;
  }

  /// Award credits for compute donation: Cauchy Reed-Solomon encoding, FastCDC, OCR (Pillar 2)
  double awardComputeCredits({
    double cauchyMb = 0.0,
    double fastCdcMb = 0.0,
    int ocrPages = 0,
    String? description,
    String? referenceId,
  }) {
    if (_rejectIfUnhydrated('awardComputeCredits')) return 0.0;
    // Formula: 2.0 * CRS_MB + 0.5 * CDC_MB + 5.0 * OCR_Pages
    final earned = _capDailyMint(CreditType.computeReward,
        (2.0 * cauchyMb) + (0.5 * fastCdcMb) + (5.0 * ocrPages));
    if (!earned.isFinite || earned <= 0) return 0.0;

    _balance += earned;
    _totalComputeEarned += earned;

    _recordTransaction(
      type: CreditType.computeReward,
      amount: earned,
      description: description ??
          'Compute Contribution (${cauchyMb.toStringAsFixed(1)}MB RS, $ocrPages OCR pages)',
      referenceId: referenceId,
      isAttested: false,
    );

    notifyListeners();
    return earned;
  }

  /// Award credits for metadata verification, DOI cross-validation, and consensus auditing (Pillar 3)
  double awardVerificationCredits({
    required String action,
    required String targetId,
    double amount = 3.0,
  }) {
    if (_rejectIfUnhydrated('awardVerificationCredits')) return 0.0;
    amount = _capDailyMint(CreditType.verificationReward, amount);
    if (!amount.isFinite || amount <= 0) return 0.0;

    _balance += amount;
    _totalVerificationEarned += amount;

    _pochService?.recordPoRChallengeAnswered();

    _recordTransaction(
      type: CreditType.verificationReward,
      amount: amount,
      description: 'Verification Action: $action',
      referenceId: targetId,
      isAttested: false,
    );

    notifyListeners();
    return amount;
  }

  /// Credits an escrowed bounty payout to the claimant. Not a mint — the
  /// originator already debited [amount] at bounty-post time, so this path
  /// deliberately bypasses daily mint caps (ALX-010: claim value = escrow).
  ///
  /// The [bountyId] dedup guard runs AFTER the refusal gates but BEFORE
  /// the mint (REV3 review belt-level dedup): a refused call — malformed
  /// id, unhydrated service, non-positive/non-finite amount — does NOT
  /// consume the id, so a probe or early call can never permanently
  /// burn a legit payout (E-REV4-B F3). Double-payment remains impossible
  /// because the set-add is atomic with the mint in a synchronous
  /// method.
  ///
  /// Reverse-direction double-dip guard (REV4a review F1): an escrow
  /// already REFUNDED via [releaseEscrow] must never be paid out —
  /// paying a released hold mints from nothing. This method is
  /// synchronous (callers consume the returned double directly), so it
  /// cannot point-query the db mid-flight: the in-memory
  /// [_releasedEscrowIds] set — repopulated at hydration from persisted
  /// `tx_escrow_release_*` rows — is the belt, and the moltbook layer's
  /// `claimed_bounties` CAS + payout-row probe + tombstone sweep are
  /// the durable suspenders for a release that landed out-of-band after
  /// hydration.
  ///
  /// Durability: the payout row is written under the deterministic id
  /// `$_kBountyPayoutTxPrefix$bountyId` and hydration repopulates
  /// [_paidBountyIds] from persisted rows, so a restart cannot re-pay
  /// through a fresh service instance (E-REV4-A residual).
  ///
  /// LEDGER-AUTHORITATIVE DEDUP (multi-instance stale-view residual):
  /// this method is synchronous — callers consume the returned double
  /// directly — so it cannot probe the ledger BEFORE minting. Instead
  /// the row is persisted through the insert-if-absent CAS
  /// ([AppDatabase.insertCreditTransactionIfAbsent]) and a lost CAS
  /// reconciles the in-memory mint to the canonical row's amount via
  /// [_reconcileMintedCredit]: a second live instance that never saw
  /// the first payout self-corrects at settle time instead of keeping a
  /// phantom balance. The `claimed_bounties` CAS in
  /// `MoltbookService.claimBounty` remains the authoritative gate for
  /// the claim layer above.
  ///
  /// OPTIMISTIC-RETURN SEMANTICS (UI-convenience API): the returned
  /// amount precedes the durable CAS settle — a losing write reconciles
  /// asynchronously via [_reconcileMintedCredit] (see [spendCredits]'s
  /// note). `MoltbookService.claimBounty` already proves durability
  /// itself with a `settled` wait + `hasCreditTransaction` probe;
  /// callers that want `amount ⇒ committed` from the primitive itself
  /// should use [awardBountyEscrowDurable].
  double awardBountyEscrow({
    required double amount,
    required String bountyId,
    required String cid,
  }) {
    if (bountyId.isEmpty) return 0.0;
    if (_rejectIfUnhydrated('awardBountyEscrow')) return 0.0;
    if (!amount.isFinite || amount <= 0) return 0.0;
    if (_releasedEscrowIds.contains(bountyId)) return 0.0;
    if (!_paidBountyIds.add(bountyId)) return 0.0;
    _balance += amount;
    _totalVerificationEarned += amount;
    final db = _db;
    _recordTransaction(
      id: '$_kBountyPayoutTxPrefix$bountyId',
      type: CreditType.verificationReward,
      amount: amount,
      description: 'Bounty Escrow Payout ($bountyId, CID: $cid)',
      referenceId: cid,
      isAttested: false,
      durableGate:
          db == null ? null : (row) => db.insertCreditTransactionIfAbsent(row),
      onDurableReject: _reconcileMintedCredit,
    );
    notifyListeners();
    return amount;
  }

  /// DURABLE variant of [awardBountyEscrow] — the trust-path form
  /// (closes the optimistic-return residual on the bounty payout): the
  /// payout row is committed through the deterministic-id CAS BEFORE
  /// the balance mutates, so a non-zero return provably corresponds to
  /// a durably-committed `tx_bounty_payout_$bountyId` row — the
  /// durability proof `MoltbookService.claimBounty` currently hand-
  /// builds with a `settled` wait + `hasCreditTransaction` probe.
  ///
  /// Strictly stronger than the sync form in one more way: it probes
  /// the durable release tombstone
  /// (`tx_escrow_release_$bountyId`) BEFORE paying — a release that
  /// landed out-of-band after hydration refuses the payout, closing
  /// the REV4a-F1 reverse-direction race durably rather than through the
  /// in-memory set alone.
  ///
  /// WRITE-FAILURE POLICY — FAIL CLOSED: a write that throws returns
  /// 0.0 (nothing mutates) — a retryable refusal beats an unprovable
  /// mint. A lost CAS means a sibling already paid this bounty: the id
  /// is absorbed into [_paidBountyIds] and 0.0 returned.
  Future<double> awardBountyEscrowDurable({
    required double amount,
    required String bountyId,
    required String cid,
  }) async {
    await _hydrated;
    if (bountyId.isEmpty) return 0.0;
    if (_rejectIfUnhydrated('awardBountyEscrowDurable')) return 0.0;
    if (!amount.isFinite || amount <= 0) return 0.0;
    final db = _db;
    if (db != null) {
      try {
        if (await db
            .hasCreditTransaction('$_kEscrowReleaseTxPrefix$bountyId')) {
          // Durable release tombstone this instance never saw — the
          // escrow was refunded out-of-band; paying it now mints from
          // nothing. Absorb the id so later calls take the fast path.
          _releasedEscrowIds.add(bountyId);
          return 0.0;
        }
      } catch (_) {
        // Fail open on the probe — the payout CAS below stays the
        // authoritative dedup, and a broken store cannot persist the
        // payout row either (the write attempt will fail closed).
      }
    }
    // NO awaits between these checks and the set-add below except the
    // durable CAS itself — two racing calls can both reach the write,
    // but the primary key decides the single winner.
    if (_releasedEscrowIds.contains(bountyId)) return 0.0;
    if (_paidBountyIds.contains(bountyId)) return 0.0;
    final tx = _buildTransaction(
      id: '$_kBountyPayoutTxPrefix$bountyId',
      type: CreditType.verificationReward,
      amount: amount,
      description: 'Bounty Escrow Payout ($bountyId, CID: $cid)',
      referenceId: cid,
      isAttested: false,
    );
    if (db != null) {
      final bool landed;
      try {
        landed = await db.insertCreditTransactionIfAbsent(_transactionRow(tx));
      } catch (e) {
        debugPrint('CreditService: durable bounty payout refused — '
            'ledger write failed: $e');
        return 0.0;
      }
      if (!landed) {
        // CAS lost — a sibling already owns the payout row; absorb the
        // durable truth so later calls take the fast path.
        _paidBountyIds.add(bountyId);
        return 0.0;
      }
    }
    _paidBountyIds.add(bountyId);
    _balance += amount;
    _totalVerificationEarned += amount;
    _commitInMemory(tx);
    notifyListeners();
    return amount;
  }

  /// Claims a verifier-signed [WorkReceipt] as ATTESTED value — the only
  /// path that mints `isAttested` credit and therefore the only path that
  /// makes [attestedBalance] non-vacuous (ALX-010).
  ///
  /// The prover identity is bound TWO ways (REV3 review, ALX-012 §5.4):
  /// the "local" key set is resolved through the injected
  /// [_localProverPubkeys] — ambient authority, never a caller-supplied
  /// string — and [claimSignatureB64] must be an Ed25519 signature by
  /// the PROVER key over the domain-separated claim preimage
  /// `'alexandria:receipt-claim:v{receipt.v}:{receipt.receiptId}'`
  /// (ASCII). `receiptId` is the sha256 of the canonical body, so the
  /// signature binds every field. Together they convert the receipt
  /// from a bearer instrument into a possession-bound one: a copied
  /// artifact cannot be claimed by a node that does not hold the prover
  /// private key, and a forked client cannot name a foreign prover key
  /// as "local". For wire v>=3 the artifact-carried `proverSig` is
  /// additionally REQUIRED and verified as the issuance acknowledgment
  /// (ALX-012 §5.8) — provenance that the prover received the artifact;
  /// the claim signature remains the anti-theft mechanism.
  ///
  /// Guards, in order (ALL evaluated inside the fail-closed try — any
  /// throw returns 0.0 with the row left unspent):
  ///  * the resolved local pubkey must be non-empty — a service with no
  ///    resolver, or a node with no identity, refuses every claim;
  ///  * non-empty `proverPubkey`, `verifierPubkey` — an absent key makes
  ///    the identity binding vacuous;
  ///  * [WorkReceipt.isVerifierSigned] — an unsigned artifact carries no
  ///    attestation weight;
  ///  * `!samePubkey(prover, verifier)` — prover == verifier is a
  ///    self-declaration;
  ///  * `samePubkey(prover, resolvedLocal)` — the receipt must name THIS
  ///    node's identity as prover; a held artifact naming a foreign
  ///    prover is that prover's claim instrument (claim theft, REV1 C3);
  ///  * `!samePubkey(verifier, resolvedLocal)` and
  ///    `!samePubkey(verifier, k)` for every k the injected
  ///    [_knownLocalPubkeys] history resolves — a receipt signed by ANY
  ///    key this node has ever held (including retired rotation
  ///    predecessors) can never mint attested value locally
  ///    (self-dealing guard, Safety item 3);
  ///  * all identity compares are CANONICAL ([WorkReceipt.samePubkey]):
  ///    uppercase or whitespace-padded hex spellings of the same key
  ///    decode identically and cannot slip past the self-dealing guards;
  ///  * `!receipt.isExpired()` — stale receipts cannot be claimed;
  ///  * `receipt.amount.isFinite && receipt.workUnits.isFinite &&
  ///    receipt.amount > 0` — hostile doubles must be refused BEFORE the
  ///    canonicalizer, which throws on non-finite/overflowing milli
  ///    values (see [WorkReceipt.amountMilli]);
  ///  * `[minClaimableWireVersion] <= receipt.v <=
  ///    [WorkReceipt.wireVersion]` — the claim-time window (ALX-012):
  ///    below-floor AND above-ceiling artifacts are representable but
  ///    unclaimable; a node never attests a scheme it doesn't implement;
  ///  * `receipt.computeReceiptId() == receipt.receiptId` — the tamper
  ///    check: the stored id must recompute from the canonical body;
  ///  * the receipt row must exist UNSPENT in the ledger store;
  ///  * IN-PATH signature verification (ALX-012 Safety mandate):
  ///    [WorkReceipt.verifyVerifierSignature] runs against the injected
  ///    [_receiptVerifier] over the receipt's own domain-separated
  ///    signing payload — a service constructed WITHOUT a verifier fails
  ///    closed, and a forged/garbage `verifierSig` is refused WITHOUT
  ///    consuming the row;
  ///  * IN-PATH POSSESSION PROOF (REV3 review): [claimSignatureB64] must
  ///    decode to 64 bytes and verify, via the same oracle, under
  ///    `receipt.proverPubkey` over the claim preimage above — a bad,
  ///    foreign-key, or wrong-domain signature is refused WITHOUT
  ///    consuming the row, so the true prover's later claim still lands;
  ///  * the claim itself is a single atomic conditional UPDATE
  ///    ([AppDatabase.claimReceiptAtomically]) — a lost CAS race or a
  ///    replay returns 0.0 (this is also why a replayed claim signature
  ///    is harmless: single-consumption is enforced by the row, so the
  ///    static preimage needs no nonce until claims become remote);
  ///  * the mint is STILL subject to the daily accrual caps (safety
  ///    floor): a claim can never exceed the day's remaining allowance
  ///    for its mapped [CreditType] ('storage'→storageReward,
  ///    'compute'→computeReward, 'verification'→verificationReward,
  ///    other→storageReward). A cap-exhausted claim still consumes the
  ///    receipt — it may only ever mint once (anti-replay).
  ///
  /// REMOTE CLAIM FRESHNESS (ALX-012 §5.8, DPoP-style): passing
  /// [verifierNonce] and [expiryMillis] selects the remote claim
  /// preimage `alexandria:receipt-claim:v{v}:{receiptId}:{nonce}:{expiry}`
  /// ([WorkReceipt.claimPreimage]) — a copied claim signature is
  /// worthless outside the verifier-issued nonce/expiry window, so a
  /// replayed remote authorization cannot mint. BOTH values must be
  /// supplied together and the expiry must be a finite future
  /// epoch-millis — a nonce without an expiry is unbounded replay and
  /// an expiry without a nonce is unbound to the verifier's challenge.
  /// Omitting both keeps the static local preimage — local claims need
  /// no freshness because the row's atomic CAS is already
  /// single-consumption.
  ///
  /// Returns the minted amount, or 0.0 on any refusal. Requires
  /// persistent mode: an in-memory service has no CAS primitive to dedup
  /// claims against.
  Future<double> claimVerifiedReceipt(
    WorkReceipt receipt, {
    required String claimSignatureB64,
    String? verifierNonce,
    int? expiryMillis,
  }) async {
    // Async path — await hydration so the daily-cap counters and balance
    // are real rather than phantom pre-hydration state.
    await _hydrated;
    final db = _db;
    if (db == null) return 0.0;

    // EVERY guard and check lives inside this try: the claim contract is
    // fail-closed — any throw (a hostile double reaching the
    // canonicalizer's milli conversion, a broken store, an exploding
    // verifier oracle, a resolver that throws, malformed base64) returns
    // 0.0 with the row left unspent rather than propagating out of the
    // guard chain.
    try {
      // Remote-claim freshness: exactly-on-or-both — one half without
      // the other is a malformed challenge, never a claim.
      final remote = verifierNonce != null || expiryMillis != null;
      if (remote) {
        final expiry = expiryMillis;
        if (verifierNonce == null ||
            verifierNonce.isEmpty ||
            expiry == null ||
            expiry <= 0 ||
            expiry <= DateTime.now().millisecondsSinceEpoch) {
          // Expired or malformed freshness: a stale remote claim can
          // never mint — refuse BEFORE touching the row so the true
          // prover's fresh claim still lands.
          return 0.0;
        }
      }

      // The local prover keys come ONLY from the injected resolver —
      // ambient identity, never caller input. A null resolver or a null/
      // empty resolution refuses every claim. Identity is then compared
      // CANONICALLY via WorkReceipt.samePubkey — raw string equality is
      // defeatable by case/whitespace variants of the same hex key (an
      // UPPERCASE or space-padded verifierPubkey still decodes to the
      // local key, so a self-signed receipt could mint ATTESTED value).
      // All key fields must also be non-empty: a '' prover against a ''
      // local key would otherwise satisfy the binding vacuously.
      // The resolver is a SET: a wallet holding several live identities
      // may claim a receipt naming ANY currently held key — the minted
      // value is then scoped to that key's attested_pubkey column.
      final localPubkeys = await _localProverPubkeys?.call();
      final heldKeys = localPubkeys == null
          ? const <String>{}
          : localPubkeys
              .where((k) => k.isNotEmpty)
              .map(WorkReceipt.canonicalPubkey)
              .toSet();

      // Rotation self-vouch history (Safety item 3): the self-dealing
      // check below is extended from "verifier is the CURRENT key" to
      // "verifier is ANY key this node has ever held" — importIdentity
      // rotation replaces the key, so a receipt signed by the retired
      // predecessor would otherwise look foreign and mint attested
      // value. The history resolver is deliberately FAIL-OPEN: a null
      // resolver, a null/empty resolution, or a throw all degrade to
      // the held-keys check — absent history must not break
      // honest claims (unlike the prover resolver above, which fails
      // closed because an absent identity makes the claim void).
      Set<String>? knownLocal;
      try {
        knownLocal = await _knownLocalPubkeys?.call();
      } catch (_) {
        knownLocal = null;
      }
      bool verifierIsKnownLocal() {
        for (final hex in heldKeys) {
          if (WorkReceipt.samePubkey(receipt.verifierPubkey, hex)) {
            return true;
          }
        }
        final known = knownLocal;
        if (known == null) return false;
        for (final hex in known) {
          if (WorkReceipt.samePubkey(receipt.verifierPubkey, hex)) {
            return true;
          }
        }
        return false;
      }

      bool proverIsHeld() {
        for (final hex in heldKeys) {
          if (WorkReceipt.samePubkey(receipt.proverPubkey, hex)) {
            return true;
          }
        }
        return false;
      }

      if (heldKeys.isEmpty ||
          receipt.proverPubkey.isEmpty ||
          receipt.verifierPubkey.isEmpty ||
          !receipt.isVerifierSigned ||
          WorkReceipt.samePubkey(
              receipt.proverPubkey, receipt.verifierPubkey) ||
          !proverIsHeld() ||
          verifierIsKnownLocal() ||
          receipt.isExpired() ||
          !(receipt.amount > 0) ||
          !receipt.amount.isFinite ||
          !receipt.workUnits.isFinite ||
          receipt.v < minClaimableWireVersion ||
          receipt.v > WorkReceipt.wireVersion ||
          receipt.computeReceiptId() != receipt.receiptId) {
        return 0.0;
      }

      // Cheap pre-check for honest failures (missing/known-spent row);
      // the CAS below remains the authoritative dedup primitive.
      final row = await db.getWorkReceipt(receipt.receiptId);
      if (row == null || row['spent'] == true) return 0.0;

      // In-path verification (ALX-012): a non-empty verifierSig is NOT
      // proof — the Ed25519 signature must actually verify over the
      // receipt's domain-separated payload, and the service fails closed
      // when no verifier oracle was injected. Runs BEFORE the CAS so a
      // forged artifact never consumes the unspent row.
      final verifier = _receiptVerifier;
      if (verifier == null ||
          !await receipt.verifyVerifierSignature(verifier)) {
        return 0.0;
      }

      // Issuance acknowledgment (ALX-012 §5.8): v>=3 receipts carry the
      // prover's counter-signature over the ack domain — proof the
      // artifact was DELIVERED to the prover, not merely emitted by the
      // verifier. This is provenance, NOT the anti-theft mechanism (a
      // copied artifact copies the ack too); claim-time possession
      // below remains the theft defense. v1/v2 receipts predate the
      // flow and stay claimable within their window.
      if (receipt.v >= WorkReceipt.minAckWireVersion &&
          !await receipt.verifyProverSignature(verifier)) {
        return 0.0;
      }

      // Possession proof (REV3 review): the caller must sign the
      // domain-separated claim preimage under the PROVER key the
      // receipt names — the remote preimage when a freshness challenge
      // was supplied, the static local form otherwise. receiptId
      // already binds the canonical body, so this signature proves
      // possession of the prover private key for THIS artifact — a
      // copied receipt presented by a node lacking the key cannot
      // mint. Malformed base64 throws into the fail-closed try; a
      // wrong-key/wrong-domain signature verifies false; either way
      // the row is left UNSPENT for the true prover's claim.
      final claimSigBytes = base64Decode(claimSignatureB64);
      if (claimSigBytes.length != 64 ||
          !await verifier(
            receipt.claimPreimage(
              verifierNonce: verifierNonce,
              expiryMillis: expiryMillis,
            ),
            claimSigBytes,
            receipt.proverPubkey,
          )) {
        return 0.0;
      }

      // Atomic claim: single `UPDATE ... WHERE receipt_id=? AND spent=0`
      // checked by rows-affected — losing the race means another claim
      // consumed the receipt first.
      if (!await db.claimReceiptAtomically(receipt.receiptId)) {
        return 0.0;
      }
    } catch (e) {
      // Fail closed: a broken store must never mint attested value.
      debugPrint('CreditService: receipt claim failed closed: $e');
      return 0.0;
    }

    final type = switch (receipt.workType) {
      'compute' => CreditType.computeReward,
      'verification' => CreditType.verificationReward,
      _ => CreditType.storageReward,
    };
    // Safety floor: attested mints respect the daily caps too. When the
    // cap is already exhausted the receipt stays spent — the claim was
    // consumed and the residual value is burned rather than replayable.
    final granted = _capDailyMint(type, receipt.amount);
    if (granted <= 0) return 0.0;

    // Durable-first mint (optimistic-return residual): persist the
    // attested mint row BEFORE the in-memory balance reflects it, so
    // the returned amount corresponds to a durably-committed row.
    // Fail-OPEN on a write error, unlike the debit paths — a lost mint
    // row under-reports on the next hydration replay (the conservative
    // direction), never over-reports, and a broken store must not void
    // value the receipt CAS already consumed.
    final mintTx = _buildTransaction(
      type: type,
      amount: granted,
      description: 'Verified work receipt claim '
          '(${receipt.workType}, receipt ${receipt.receiptId})',
      referenceId: receipt.receiptId,
      isAttested: true,
      // Prover-key scoping (schema v7): the mint is tagged with the
      // canonical key the receipt names — egress eligibility follows
      // the key, so a rotated-out identity's attested value stops
      // backing egress the moment it leaves the held set.
      attestedPubkey: WorkReceipt.canonicalPubkey(receipt.proverPubkey),
    );
    try {
      await db.insertCreditTransactionIfAbsent(_transactionRow(mintTx));
    } catch (_) {
      // Best-effort durability for mints — see the note above.
    }

    _balance += granted;
    switch (type) {
      case CreditType.storageReward:
        _totalStorageEarned += granted;
      case CreditType.computeReward:
        _totalComputeEarned += granted;
      case CreditType.verificationReward:
        _totalVerificationEarned += granted;
      default:
        break;
    }

    // The claim already proved the prover key is held — absorb it into
    // the held-key cache so the minted value is immediately
    // egress-eligible WITHOUT a second resolution (re-resolving here
    // would also reopen a TOCTOU window inside the guard chain).
    _heldAttestedKeys = {
      ..._heldAttestedKeys,
      WorkReceipt.canonicalPubkey(receipt.proverPubkey),
    };
    _commitInMemory(mintTx);
    notifyListeners();
    return granted;
  }

  /// Persists an incoming [WorkReceipt] artifact with SIGNED-UPGRADE
  /// semantics (ALX-012 §5.8 — `insertWorkReceipt` first-insert-wins
  /// residual): a previously stored UNSIGNED row no longer blocks a
  /// later signed redelivery of the same `receiptId`.
  ///
  ///  * No existing row → plain insert (first-insert-wins preserved).
  ///  * Existing row + incoming carries a signature the stored row
  ///    lacks → the signature is VERIFIED in-path first
  ///    ([WorkReceipt.verifyVerifierSignature] /
  ///    [WorkReceipt.verifyProverSignature] against the
  ///    injected [_receiptVerifier]); only verified material is then
  ///    merged via [AppDatabase.upgradeWorkReceiptSignatures], which
  ///    COALESCEs — a stored signature is never overwritten and `spent`
  ///    is never touched, so an upgrade can neither downgrade a signed
  ///    row nor resurrect a spent one.
  ///  * The incoming `receiptId` must recompute from its canonical body
  ///    — a sig-carrying artifact can't graft onto an unrelated row.
  ///  * No verifier oracle → every upgrade refuses (fail closed).
  ///
  /// Returns true when the row was inserted or at least one signature
  /// was merged.
  Future<bool> ingestWorkReceipt(WorkReceipt receipt) async {
    await _hydrated;
    final db = _db;
    if (db == null) return false;
    try {
      final existing = await db.getWorkReceipt(receipt.receiptId);
      if (existing == null) {
        await db.insertWorkReceipt(receipt.toDbMap());
        return true;
      }
      if (receipt.computeReceiptId() != receipt.receiptId) {
        return false; // tampered artifact — never merge
      }
      final newVerifierSig = receipt.verifierSig.isNotEmpty &&
          ((existing['verifierSig'] as String?) ?? '').isEmpty;
      final newProverSig = (receipt.proverSig?.isNotEmpty ?? false) &&
          ((existing['proverSig'] as String?) ?? '').isEmpty;
      if (!newVerifierSig && !newProverSig) {
        return false; // nothing the stored row lacks — first-wins
      }
      final verifier = _receiptVerifier;
      if (verifier == null) return false;
      if (newVerifierSig && !await receipt.verifyVerifierSignature(verifier)) {
        return false; // a forged upgrade is refused, not persisted
      }
      if (newProverSig && !await receipt.verifyProverSignature(verifier)) {
        return false;
      }
      return await db.upgradeWorkReceiptSignatures(
        receipt.receiptId,
        verifierSig: newVerifierSig ? receipt.verifierSig : null,
        proverSig: newProverSig ? receipt.proverSig : null,
      );
    } catch (e) {
      debugPrint('CreditService: receipt ingest failed closed: $e');
      return false;
    }
  }

  /// Award credits from an ethical, opt-in institutional sponsorship impression (ALX-005 §5.2)
  /// Splits gross: 85% to client, 10% to endangered seeders, 5% to protocol treasury
  ImpressionReceipt awardSponsorshipKickback({
    required String campaignId,
    required double grossCredits,
    required double dwellTimeSeconds,
  }) {
    if (_rejectIfUnhydrated('awardSponsorshipKickback')) {
      // Honest zeroed receipt — nothing was minted or split.
      return ImpressionReceipt(
        campaignId: campaignId,
        timestamp: DateTime.now(),
        dwellTimeSeconds: dwellTimeSeconds,
        nonce: 'unhydrated',
        grossCredits: grossCredits,
        clientKickback: 0.0,
        archivalCommonsPool: 0.0,
        protocolFee: 0.0,
      );
    }
    if (!grossCredits.isFinite || grossCredits <= 0) {
      // Non-finite or non-positive gross must never enter the ledger:
      // NaN/∞ would poison the balance outright (F4), and a negative
      // gross computes NEGATIVE pool/treasury splits — a drain, not a
      // kickback. Return the same honest-zero receipt shape as the
      // unhydrated refusal.
      return ImpressionReceipt(
        campaignId: campaignId,
        timestamp: DateTime.now(),
        dwellTimeSeconds: dwellTimeSeconds,
        nonce: 'invalid',
        grossCredits: grossCredits,
        clientKickback: 0.0,
        archivalCommonsPool: 0.0,
        protocolFee: 0.0,
      );
    }
    final clientKickback =
        _capDailyMint(CreditType.sponsorshipKickback, grossCredits * 0.85);
    final seederCut = grossCredits * 0.10;
    final fee = grossCredits * 0.05;

    _balance += clientKickback;
    _totalSponsorshipKickbacks += clientKickback;
    _archivalCommonsPool += seederCut;
    _protocolTreasury += fee;
    _totalFeesContributed += fee;

    final nonce = DateTime.now().millisecondsSinceEpoch.toRadixString(16);

    _recordTransaction(
      type: CreditType.sponsorshipKickback,
      amount: clientKickback,
      description:
          'Sponsorship Kickback (85% share of ${grossCredits.toStringAsFixed(1)} credits)',
      referenceId: campaignId,
      isAttested: false,
    );

    final receipt = ImpressionReceipt(
      campaignId: campaignId,
      timestamp: DateTime.now(),
      dwellTimeSeconds: dwellTimeSeconds,
      nonce: nonce,
      grossCredits: grossCredits,
      clientKickback: clientKickback,
      archivalCommonsPool: seederCut,
      protocolFee: fee,
    );

    notifyListeners();
    return receipt;
  }

  /// Spend credits on network resources (e.g. priority streaming, custom permanent pin)
  /// Deducts amount and automatically transfers a 5% micro-fee to the protocol treasury
  ///
  /// When [isAttested] is true the debit settles against the ATTESTED
  /// pool specifically — the egress budget (round-1 red finding): it is
  /// refused outright unless [attestedBalance] covers [amount], and it
  /// accrues [_attestedBurned] directly instead of routing through
  /// [_burnForDebit]. [_burnForDebit] consumes the UNATTESTED pool
  /// first — the correct priority for an internal spend — but an
  /// attested-flagged debit taking that path would leave the attested
  /// quota untouched, so a per-call egress gate degrades into a rate
  /// limit while self-certified value drains out behind
  /// verifier-signed credit. The ledger row is recorded with
  /// `isAttested: true` so [_rebuildBalance] burns the same pool on
  /// replay — a runtime/replay divergence would resurrect the egressed
  /// quota on every restart. Fee, _totalSpent and
  /// _totalFeesContributed accounting are identical for both paths.
  ///
  /// OPTIMISTIC-RETURN SEMANTICS (UI-convenience API): this synchronous
  /// method returns BEFORE its durable write settles — a losing write
  /// reconciles asynchronously ([_rollbackAttestedDebit] /
  /// [_reconcileMintedCredit]), so the returned `true` may briefly
  /// over-report until [settled] resolves. The durable ledger never
  /// records the losing write — the residual bound is observational,
  /// not financial. Callers whose returned value must correspond to a
  /// durably-committed row (egress rails, escrow payout) must use
  /// [spendCreditsDurable] instead.
  bool spendCredits({
    required double amount,
    required String reason,
    String? referenceId,
    CreditType debitType = CreditType.priorityAccessDebit,
    bool isAttested = false,
  }) {
    if (_rejectIfUnhydrated('spendCredits')) return false;
    // `!amount.isFinite` first (F4): NaN makes BOTH comparisons below
    // false — `NaN <= 0` and `_balance < NaN` — so an unguarded NaN
    // debit sails through and poisons _balance into NaN, after which
    // every spend succeeds forever (unbounded drain).
    if (!amount.isFinite || amount <= 0 || _balance < amount) {
      return false;
    }

    final fee = amount * protocolFeeRate;
    final double burnedAttested;
    if (isAttested) {
      // The held-key-scoped attested pool must cover the debit
      // outright — self-certified value can NEVER supplement a
      // foreign-verifier-backed egress, and value minted under a
      // prover key this wallet no longer holds doesn't count.
      if (attestedBalance < amount) return false;
      _attestedBurned += amount;
      burnedAttested = amount;
    } else {
      burnedAttested = _burnForDebit(amount);
    }
    _balance -= amount;
    _protocolTreasury += fee;
    _totalSpent += amount;
    _totalFeesContributed += fee;

    // Attested egress is persisted through the durable coverage gate
    // (multi-instance stale-view residual): the in-memory check above
    // is the synchronous fast path; insertAttestedDebitIfCovered
    // re-resolves the held keys and re-sums the durable scoped pool at
    // write time, so a sibling instance draining the same ledger
    // cannot make this over-spend canonical. A refused row rolls the
    // in-memory debit back via [_rollbackAttestedDebit] — the returned
    // `true` can't be retroactively revoked (the artifact may already
    // be emitted), so the bound is: the ledger never records the
    // over-spend and the local mint self-corrects at settle.
    final db = _db;
    _recordTransaction(
      type: debitType,
      amount: -amount,
      description:
          '$reason (incl. ${(protocolFeeRate * 100).toInt()}% treasury fee)',
      referenceId: referenceId,
      isAttested: isAttested,
      burnedAttested: burnedAttested,
      durableGate: isAttested && db != null
          ? (row) => _persistAttestedDebit(db, row, amount)
          : null,
      onDurableReject:
          isAttested ? (tx, _) => _rollbackAttestedDebit(tx) : null,
    );

    notifyListeners();
    return true;
  }

  /// DURABLE variant of [spendCredits] — the trust-path form (closes
  /// the optimistic-return residual on egress, escrow and payout
  /// flows): the ledger row is committed through the durable gate
  /// BEFORE any in-memory state mutates, so a returned `true` provably
  /// corresponds to a durably-committed row — no [settled] wait, no
  /// post-hoc reconcile, no artifact emitted against an uncommitted
  /// debit.
  ///
  /// The attested form persists through
  /// [AppDatabase.insertAttestedDebitIfCovered], which since schema v8
  /// is a SUFFICIENT gate (scoped mints − every durable attested burn):
  /// a refusal here is the ledger's own verdict, not a stale in-memory
  /// view — the caller sees `false` and nothing mutates, which the
  /// synchronous [spendCredits] could only express as an after-the-fact
  /// rollback.
  ///
  /// WRITE-FAILURE POLICY — FAIL CLOSED: a db write that throws returns
  /// `false` (nothing mutates), deliberately stricter than the
  /// best-effort sync path: the durable contract prefers a retryable
  /// refusal over an unprovable success. In pure in-memory mode
  /// ([_db] == null) the method degenerates to the same mutation order
  /// as [spendCredits] — the row is the in-memory ledger itself.
  Future<bool> spendCreditsDurable({
    required double amount,
    required String reason,
    String? referenceId,
    CreditType debitType = CreditType.priorityAccessDebit,
    bool isAttested = false,
  }) async {
    await _hydrated;
    if (_rejectIfUnhydrated('spendCreditsDurable')) return false;
    if (!amount.isFinite || amount <= 0 || _balance < amount) {
      return false;
    }

    final fee = amount * protocolFeeRate;
    final double burnedAttested;
    if (isAttested) {
      // Fast path only — the durable gate below is authoritative.
      if (attestedBalance < amount) return false;
      burnedAttested = amount;
    } else {
      burnedAttested = _previewBurnForDebit(amount);
    }

    final tx = _buildTransaction(
      type: debitType,
      amount: -amount,
      description:
          '$reason (incl. ${(protocolFeeRate * 100).toInt()}% treasury fee)',
      referenceId: referenceId,
      isAttested: isAttested,
      burnedAttested: burnedAttested,
    );
    final db = _db;
    if (db != null) {
      final bool landed;
      try {
        landed = isAttested
            ? await _persistAttestedDebit(db, _transactionRow(tx), amount)
            : await db.insertCreditTransactionIfAbsent(_transactionRow(tx));
      } catch (e) {
        debugPrint('CreditService: durable spend refused — '
            'ledger write failed: $e');
        return false;
      }
      if (!landed) return false;
    }

    // NO awaits below — the commit is one atomic in-isolate step.
    _attestedBurned += burnedAttested;
    _balance -= amount;
    _protocolTreasury += fee;
    _totalSpent += amount;
    _totalFeesContributed += fee;
    _commitInMemory(tx);
    notifyListeners();
    return true;
  }

  /// Debits credits into a bounty escrow WITHOUT the treasury fee — this is a
  /// hold, not a spend: the full amount is owed to the future claimant, so
  /// skimming it here would mint unbacked value on payout (ALX-010, quorum
  /// E-T5 #5: post+claim cycle must be net-zero).
  ///
  /// The hold row carries the NON-FORGEABLE deterministic id
  /// `$_kEscrowHoldTxPrefix<referenceId>_<micros>_<seq>` (F2) —
  /// [releaseEscrow] recognises genuine holds by that id shape, so a
  /// [spendCredits] debit can never pose as escrow. The wall-clock
  /// micros component makes the id restart-safe: [_txSeq] alone resets
  /// per process, so a bare `<ref>_<seq>` id could repeat a persisted
  /// primary key after a restart and insertOrIgnore would drop the REAL
  /// second debit (RE-B1). referenceIds must not be recycled:
  /// release dedup is once-per-referenceId forever, so a hold posted
  /// under an already-released id is permanently unreleasable (see
  /// [_releasedEscrowIds]).
  ///
  /// OPTIMISTIC-RETURN SEMANTICS (UI-convenience API): the returned
  /// `true` precedes the durable hold-row write — see [spendCredits]'s
  /// note. A lost write cannot manufacture a releasable hold for a
  /// sibling (the release scan reads durable rows), but callers that
  /// need `true ⇒ committed` must use [debitEscrowDurable].
  bool debitEscrow({required double amount, required String referenceId}) {
    if (_rejectIfUnhydrated('debitEscrow')) return false;
    // Symmetric with [releaseEscrow]'s refusal (F5): a hold taken under
    // an empty/whitespace referenceId could never be released — the
    // release path refuses the same ids — so the debit must refuse up
    // front rather than strand funds.
    if (referenceId.trim().isEmpty) return false;
    // `!amount.isFinite` first (F4): NaN defeats both comparisons below
    // and would poison _balance into NaN — after which every spend
    // succeeds (unbounded drain).
    if (!amount.isFinite || amount <= 0 || _balance < amount) {
      return false;
    }
    final burnedAttested = _burnForDebit(amount);
    _balance -= amount;
    _totalSpent += amount;
    _recordTransaction(
      id: '$_kEscrowHoldTxPrefix${referenceId}_'
          '${DateTime.now().microsecondsSinceEpoch}_${_txSeq++}',
      type: CreditType.priorityAccessDebit,
      amount: -amount,
      description: '$_kEscrowHoldMarker ($referenceId)',
      referenceId: referenceId,
      isAttested: false,
      burnedAttested: burnedAttested,
    );
    notifyListeners();
    return true;
  }

  /// DURABLE variant of [debitEscrow] — the trust-path form (closes
  /// the optimistic-return residual): the escrow hold row is committed
  /// through the insert-if-absent CAS BEFORE the balance mutates, so a
  /// returned `true` provably corresponds to a durably-committed hold.
  /// A lost CAS (the deterministic hold id already taken) or a write
  /// failure returns `false` with nothing mutated — FAIL CLOSED, unlike
  /// the best-effort sync form.
  Future<bool> debitEscrowDurable(
      {required double amount, required String referenceId}) async {
    await _hydrated;
    if (_rejectIfUnhydrated('debitEscrowDurable')) return false;
    if (referenceId.trim().isEmpty) return false;
    if (!amount.isFinite || amount <= 0 || _balance < amount) {
      return false;
    }
    final burnedAttested = _previewBurnForDebit(amount);
    final tx = _buildTransaction(
      id: '$_kEscrowHoldTxPrefix${referenceId}_'
          '${DateTime.now().microsecondsSinceEpoch}_${_txSeq++}',
      type: CreditType.priorityAccessDebit,
      amount: -amount,
      description: '$_kEscrowHoldMarker ($referenceId)',
      referenceId: referenceId,
      isAttested: false,
      burnedAttested: burnedAttested,
    );
    final db = _db;
    if (db != null) {
      final bool landed;
      try {
        landed = await db.insertCreditTransactionIfAbsent(_transactionRow(tx));
      } catch (e) {
        debugPrint('CreditService: durable escrow debit refused — '
            'ledger write failed: $e');
        return false;
      }
      if (!landed) return false;
    }
    _attestedBurned += burnedAttested;
    _balance -= amount;
    _totalSpent += amount;
    _commitInMemory(tx);
    notifyListeners();
    return true;
  }

  /// Releases a bounty escrow hold back to the poster — the cancel/
  /// refund half of [debitEscrow] (Safety 6c: the hold is no longer a
  /// one-way burn). Credits the ORIGINAL debited amount back — never
  /// more, never less — so post→cancel is net-zero exactly like
  /// post→claim.
  ///
  /// The releasable hold is a ledger row carrying THIS [referenceId],
  /// the escrow-hold shape ([CreditType.priorityAccessDebit] with a
  /// NEGATIVE finite amount) and one of two non-forgeable markers
  /// (REV4a review F2 + RE-B2):
  ///  * a row id under the [_kEscrowHoldTxPrefix] deterministic prefix —
  ///    only [debitEscrow] can mint that id shape: [spendCredits] rows
  ///    carry auto-generated ids, so a caller-crafted `reason`
  ///    containing the 'Bounty Escrow Hold' text can no longer
  ///    fabricate a releasable hold, and the positive release row can
  ///    never be re-matched as a hold;
  ///  * LEGACY fallback for rows written by pre-REV4a builds, which carry
  ///    an auto `tx_<micros>_<seq>` id — matched by the EXACT
  ///    description `Bounty Escrow Hold (<referenceId>)`. Exact
  ///    equality stays unforgeable because [spendCredits] always
  ///    appends ' (incl. 5% treasury fee)' to the caller's reason —
  ///    a `contains` match would be forgeable and is deliberately not
  ///    used. Without this fallback every escrow posted before the
  ///    upgrade would be stranded.
  ///
  /// Forward-direction double-dip guard (REV4a review F1): an escrow
  /// already PAID OUT via [awardBountyEscrow] must never be refunded —
  /// a release on top of the payout double-mints. The in-memory
  /// [_paidBountyIds] set covers same-process payouts and
  /// hydration-rebuilt state; the direct primary-key probe
  /// `hasCreditTransaction('tx_bounty_payout_$referenceId')` covers
  /// payouts that landed out-of-band after hydration (e.g. a remote
  /// claim settling — via its own claimed_bounties row — while a
  /// cancel is in flight). The probe fails OPEN on a throw: a store
  /// that cannot answer cannot persist the release row either, and the
  /// dedup row IS the payment record, so an unpersisted refund stays
  /// re-releasable rather than double-minting durably.
  ///
  /// Dedup mirrors [awardBountyEscrow]: the in-memory
  /// [_releasedEscrowIds] set gates replay within this process, and the
  /// refund row is written under the deterministic id
  /// `$_kEscrowReleaseTxPrefix$referenceId` so hydration repopulates the
  /// set across restarts. DOCUMENTED SEMANTICS: release is ONCE PER
  /// referenceId, forever — a hold re-posted under an already-released
  /// id is permanently unreleasable and its would-be release row could
  /// never persist anyway (insertOrIgnore keeps the first
  /// `tx_escrow_release_$referenceId`). Refusal gates run BEFORE the
  /// set-add — an empty id, an unhydrated service, a paid-out escrow,
  /// or a call that finds no hold does NOT consume the id, so a probe
  /// can never permanently burn a legitimate release (same ordering as
  /// the E-REV4-B F3 payout fix). If several holds exist under one
  /// referenceId (e.g. a re-posted bounty), a single release refunds
  /// their sum — cancel semantics.
  ///
  /// Probe-window TOCTOU (RE-A): the durable payout probe above AWAITS,
  /// and a synchronous [awardBountyEscrow] can land inside that await —
  /// minting the payout and adding the id to [_paidBountyIds] while the
  /// probe still read "unpaid". The in-memory set is therefore
  /// re-checked INSIDE the no-await region below; there is no await
  /// between that re-check and the [_releasedEscrowIds] add, so no
  /// interleave can slip a mint past it.
  ///
  /// HYDRATION-WINDOW BOUND — CLOSED: hold rows OLDER than the ~100k-row
  /// replay window were durable but unreadable to the in-memory scan
  /// (the id-prefix listing returns ids only, never amounts). The
  /// [AppDatabase.getEscrowHoldRows] listing above fetches amount-bearing
  /// rows by the deterministic hold-id prefix + exact referenceId match
  /// over the FULL table and merges them with the in-window scan
  /// (deduped by primary-key id), so a durable hold is always
  /// releasable. [_paidBountyIds] and [_releasedEscrowIds] are rebuilt
  /// from targeted prefix reads over the full table too — a paid-out or
  /// already-released escrow is refused regardless of the window.
  ///
  /// Works in pure in-memory mode (the transaction list is the source
  /// of truth either way); durability of the dedup record requires a
  /// db. Returns the refunded amount (> 0), or 0.0 on any refusal.
  Future<double> releaseEscrow({required String referenceId}) async {
    // Async so hydration lands first — releasing against a phantom
    // (unhydrated) ledger would miss the persisted hold row and
    // wrongly refuse.
    await _hydrated;
    if (referenceId.trim().isEmpty) return 0.0;
    if (_rejectIfUnhydrated('releaseEscrow')) return 0.0;
    if (_paidBountyIds.contains(referenceId)) return 0.0;
    final db = _db;
    // Durable hold rows for this referenceId — fetched alongside the
    // payout probe so the merge below is window-independent.
    List<Map<String, dynamic>>? durableHolds;
    if (db != null) {
      try {
        if (await db
            .hasCreditTransaction('$_kBountyPayoutTxPrefix$referenceId')) {
          // Durable proof-of-payment this instance never saw (written
          // out-of-band or after hydration) — refunding on top of it
          // double-mints the escrow.
          return 0.0;
        }
        if (await db
            .hasCreditTransaction('$_kEscrowReleaseTxPrefix$referenceId')) {
          // Durable release tombstone this instance never saw
          // (multi-instance stale-view residual): a sibling instance
          // already refunded this escrow — the in-memory set is only
          // a same-process fast path, the ledger is the authority.
          // Absorb the id so later calls take the fast path.
          _releasedEscrowIds.add(referenceId);
          return 0.0;
        }
        // BEYOND-WINDOW HOLDS: the replay window (~100k rows) cannot
        // see hold rows older than it, but the ledger keeps them.
        // Listing by the deterministic hold-id prefix + exact
        // referenceId match is unbounded — a stale cancel can always
        // find its durable hold.
        durableHolds = await db.getEscrowHoldRows(referenceId);
      } catch (_) {
        // Fail open on the probes/listing: see the docstring — a
        // broken store cannot persist the dedup row, so this refund
        // never becomes canonical. durableHolds stays null and the
        // in-window scan below still runs.
      }
    }

    // From here to the [_releasedEscrowIds].add there must be NO await:
    // the contains-checks, the hold scan and the set-add are one atomic
    // in-isolate step. An interleaved await between check and add lets
    // every concurrent release pass the check before the id lands —
    // the payout probe above therefore runs BEFORE this region, not
    // inside it (REV4a: that exact window paid 3 overlapping releases).
    //
    // RE-A: the probe await is itself a TOCTOU window — a synchronous
    // awardBountyEscrow landing inside it mints the payout AND records
    // the id in _paidBountyIds while the durable row was still
    // invisible to the probe. Re-check the in-memory set HERE, after
    // the await and before the scan/add, so that racing mint is
    // observed and the release refuses instead of refunding on top.
    if (_paidBountyIds.contains(referenceId)) return 0.0;
    if (_releasedEscrowIds.contains(referenceId)) return 0.0;

    var refundAmount = 0.0;
    var found = false;
    final seenHoldIds = <String>{};
    for (final tx in _transactions) {
      if (_isReleasableHold(tx, referenceId)) {
        found = true;
        refundAmount += -tx.amount;
        seenHoldIds.add(tx.id);
      }
    }
    // Merge durable holds the replay window missed — re-applying the
    // full [_isReleasableHold] predicate (the DAO deliberately
    // over-selects) and skipping rows already counted from the
    // in-memory list by primary-key id, so a windowed hold is never
    // double-refunded.
    if (durableHolds != null) {
      for (final row in durableHolds) {
        final tx = CreditTransaction.fromJson(row);
        if (!seenHoldIds.add(tx.id)) continue;
        if (!_isReleasableHold(tx, referenceId)) continue;
        found = true;
        refundAmount += -tx.amount;
      }
    }
    if (!found || !refundAmount.isFinite || refundAmount <= 0) {
      return 0.0;
    }

    _releasedEscrowIds.add(referenceId);

    // DURABLE-FIRST (optimistic-return residual — CLOSED): the release
    // row is committed through the insert-if-absent CAS BEFORE the
    // refund mutates the in-memory view, so the returned amount always
    // corresponds to a durably-committed row. The [_releasedEscrowIds]
    // add deliberately stays in the no-await region ABOVE the write:
    // a synchronous [awardBountyEscrow] or a second release landing
    // during the write await still sees the id burned and refuses —
    // the TOCTOU protection the REV4a/RE-A ordering was built for.
    final releaseTx = _buildTransaction(
      id: '$_kEscrowReleaseTxPrefix$referenceId',
      // Mirrors the debit row's type so hold and release stay
      // ledger-symmetric; the refunded value is self-certified, never
      // attested — a released escrow is not foreign-attested work.
      type: CreditType.priorityAccessDebit,
      amount: refundAmount,
      description: 'Escrow Release ($referenceId)',
      referenceId: referenceId,
      isAttested: false,
    );
    if (db != null) {
      final bool landed;
      try {
        landed = await db
            .insertCreditTransactionIfAbsent(_transactionRow(releaseTx));
      } catch (e) {
        // The store could not commit the dedup record — the refund must
        // not become canonical in memory either (a phantom refund would
        // over-report until the next hydration replay). FAIL CLOSED:
        // unburn the id so the escrow stays releasable for a retry —
        // the durable row is the release record, and none exists.
        _releasedEscrowIds.remove(referenceId);
        debugPrint('CreditService: escrow release write failed: $e');
        return 0.0;
      }
      if (!landed) {
        // CAS lost — a sibling writer owns
        // `tx_escrow_release_$referenceId`. Align this instance's view
        // to the canonical row exactly the way the old
        // reconcile-on-reject unwind did: credit the canonical amount
        // so the in-memory balance matches what the next hydration
        // replay will compute.
        double? canonical;
        try {
          canonical = await db.getCreditTransactionAmount(releaseTx.id);
        } catch (_) {
          canonical = null;
        }
        if (canonical != null && canonical > 0) {
          _balance += canonical;
          _totalSpent = (_totalSpent - canonical).clamp(0.0, double.infinity);
          _commitInMemory(CreditTransaction(
            id: releaseTx.id,
            timestamp: releaseTx.timestamp,
            type: releaseTx.type,
            amount: canonical,
            description: releaseTx.description,
            referenceId: releaseTx.referenceId,
            hash: releaseTx.hash,
            isAttested: releaseTx.isAttested,
            attestedPubkey: releaseTx.attestedPubkey,
            burnedAttested: releaseTx.burnedAttested,
          ));
          notifyListeners();
          return canonical;
        }
        return 0.0;
      }
    }
    _balance += refundAmount;
    // The hold added to _totalSpent at debit time; a release is the
    // debit unwound, so the session's net-spend stat unwinds with it.
    _totalSpent = (_totalSpent - refundAmount).clamp(0.0, double.infinity);
    _commitInMemory(releaseTx);
    notifyListeners();
    return refundAmount;
  }

  /// Whether [tx] is a releasable escrow-hold row for [referenceId].
  /// New-shape holds are recognised by the non-forgeable
  /// [_kEscrowHoldTxPrefix] id (REV4a F2). Rows written by PRE-REV4a builds
  /// carry an auto `tx_<micros>_<seq>` id instead — they are matched by
  /// the EXACT description `Bounty Escrow Hold (<referenceId>)`
  /// (RE-B2): [spendCredits] always appends ' (incl. 5% treasury fee)'
  /// to the caller's reason, so the exact-match shape cannot be
  /// fabricated through any public debit path — a `contains` match
  /// WOULD be forgeable and stays rejected. Non-finite amounts are
  /// never releasable (RE-D): a hydrated `-infinity` hold row must not
  /// mint an infinite refund, and skipping it keeps a poisoned row
  /// from stranding a legitimate hold sharing the referenceId.
  bool _isReleasableHold(CreditTransaction tx, String referenceId) =>
      tx.referenceId == referenceId &&
      tx.type == CreditType.priorityAccessDebit &&
      tx.amount < 0 &&
      tx.amount.isFinite &&
      (tx.id.startsWith(_kEscrowHoldTxPrefix) ||
          tx.description == '$_kEscrowHoldMarker ($referenceId)');

  /// Whether [referenceId]'s escrow has already been released (or
  /// tombstoned) — a synchronous read of [_releasedEscrowIds], which
  /// hydration rebuilds from durable `tx_escrow_release_*` rows via a
  /// targeted prefix listing (NOT the replay window), so the answer is
  /// correct even for releases older than the hydration window.
  /// MoltbookService consults this for ingest-time tombstone checks.
  bool isEscrowReleased(String referenceId) =>
      _releasedEscrowIds.contains(referenceId);

  /// Whether a bounty payout was already recorded for [bountyId] — a
  /// synchronous read of [_paidBountyIds], rebuilt at hydration from
  /// durable `tx_bounty_payout_*` rows via a targeted prefix listing
  /// (NOT the replay window), so the answer is correct even for payouts
  /// older than the hydration window.
  bool isBountyPayoutRecorded(String bountyId) =>
      _paidBountyIds.contains(bountyId);

  /// Computes how much of an [amount] debit would consume the ATTESTED
  /// pool under the unattested-first rule, WITHOUT mutating state —
  /// reads the pre-debit [_balance], so it must run before the balance
  /// is reduced. This is the same arithmetic [_rebuildBalance] applies
  /// at replay and the value persisted per-row into schema-v8
  /// `burned_attested` (the durable sufficiency input of
  /// [AppDatabase.insertAttestedDebitIfCovered]).
  double _previewBurnForDebit(double amount) {
    final unattested = _balance - _attestedNetAllKeys;
    final burn = amount - (unattested > 0.0 ? unattested : 0.0);
    return burn > 0.0 ? burn : 0.0;
  }

  /// Consumes [amount] of value for a debit, drawing on the self-certified
  /// (unattested) portion first and attested value only once that is
  /// exhausted. MUST be called before [_balance] is reduced — it reads the
  /// pre-debit balance. Attested value burned here accrues to
  /// [_attestedBurned] — debits never shrink a key's minted total, so the
  /// held-key-scoped [attestedBalance] stays a clean minted-minus-burned.
  /// Returns the attested share consumed — the value the caller persists
  /// as the row's `burned_attested` (schema v8).
  double _burnForDebit(double amount) {
    final burn = _previewBurnForDebit(amount);
    if (burn > 0.0) _attestedBurned += burn;
    return burn;
  }

  /// Net attested value across ALL keys (held, retired, unscoped) —
  /// the pool an ordinary debit draws on once unattested value runs
  /// dry. Internal burns are wallet-wide: an internal spend doesn't
  /// care whose prover key earned the attestation it consumes, only
  /// egress is key-scoped.
  double get _attestedNetAllKeys {
    var minted = 0.0;
    for (final m in _attestedMintedByKey.values) {
      minted += m;
    }
    return minted - _attestedBurned;
  }

  /// Builds a [CreditTransaction] (deterministic id when supplied,
  /// otherwise `tx_<micros>_<seq>`) WITHOUT touching any in-memory
  /// state — the first half of [_recordTransaction], split out so the
  /// durable-first mutators can persist the row BEFORE it becomes
  /// observable in the local view.
  CreditTransaction _buildTransaction({
    required CreditType type,
    required double amount,
    required String description,
    String? id,
    String? referenceId,
    bool isAttested = false,
    String? attestedPubkey,
    double burnedAttested = 0.0,
  }) {
    // [id] is normally time-derived; genesis passes the deterministic
    // [_kGenesisTxId] so racing instances collapse onto one ledger row.
    // The suffix is the monotonic [_txSeq] — NOT _transactions.length,
    // which resets per process and let a micros+length collision drop a
    // real ledger row via insertOrIgnore (Safety 6f).
    final txId =
        id ?? 'tx_${DateTime.now().microsecondsSinceEpoch}_${_txSeq++}';
    final timestamp = DateTime.now();
    final hash = CreditTransaction.computeHash(
      id: txId,
      timestamp: timestamp,
      type: type,
      amount: amount,
      description: description,
      referenceId: referenceId,
      isAttested: isAttested,
    );
    return CreditTransaction(
      id: txId,
      timestamp: timestamp,
      type: type,
      amount: amount,
      description: description,
      referenceId: referenceId,
      hash: hash,
      isAttested: isAttested,
      attestedPubkey: attestedPubkey,
      burnedAttested: burnedAttested,
    );
  }

  /// Appends an already-built transaction to the in-memory ledger view —
  /// the second half of [_recordTransaction]. Attested mints accrue to
  /// their prover-key bucket here.
  void _commitInMemory(CreditTransaction tx) {
    _transactions.add(tx);
    if (tx.isAttested && tx.amount > 0) {
      final key = tx.attestedPubkey ?? _kUnscopedAttested;
      _attestedMintedByKey[key] =
          (_attestedMintedByKey[key] ?? 0.0) + tx.amount;
    }
  }

  /// The persisted form of [tx] — includes `burnedAttested` (schema v8)
  /// so every debit carries its own attested-burn attribution and the
  /// durable egress gate can sum mints-minus-burns.
  static Map<String, dynamic> _transactionRow(CreditTransaction tx) =>
      <String, dynamic>{
        'id': tx.id,
        'timestamp': tx.timestamp,
        'type': tx.type.name,
        'amount': tx.amount,
        'description': tx.description,
        'referenceId': tx.referenceId,
        'hash': tx.hash,
        'isAttested': tx.isAttested,
        'attestedPubkey': tx.attestedPubkey,
        'burnedAttested': tx.burnedAttested,
      };

  /// Records the new transaction's row and — when [durableGate] is
  /// supplied and a db
  /// is attached — persists it through that gate instead of the plain
  /// write-through. A gate returning false means the ledger REFUSED the
  /// row (a lost deterministic-id CAS, or an attested debit the durable
  /// held-key sum doesn't cover — the multi-instance stale-view
  /// reconciliation: the ledger is the authority on dedup, the in-memory
  /// sets are fast-path only). [onDurableReject] then runs with the
  /// canonical amount actually persisted (null = nothing landed) so the
  /// in-memory mint can reconcile — it already returned true to a
  /// synchronous caller, so the correction is an async unwind, never a
  /// retroactive refusal.
  CreditTransaction _recordTransaction({
    required CreditType type,
    required double amount,
    required String description,
    String? id,
    String? referenceId,
    bool isAttested = false,
    String? attestedPubkey,
    double burnedAttested = 0.0,
    Future<bool> Function(Map<String, dynamic> row)? durableGate,
    void Function(CreditTransaction tx, double? canonicalAmount)?
        onDurableReject,
  }) {
    final tx = _buildTransaction(
      type: type,
      amount: amount,
      description: description,
      id: id,
      referenceId: referenceId,
      isAttested: isAttested,
      attestedPubkey: attestedPubkey,
      burnedAttested: burnedAttested,
    );
    _commitInMemory(tx);

    // Best-effort write-through: a persistence failure must never break
    // an award, so errors are swallowed inside [_persistWrite].
    final db = _db;
    if (db != null) {
      final row = _transactionRow(tx);
      final gate = durableGate;
      if (gate == null) {
        _persistWrite(db.insertCreditTransaction(row));
      } else {
        _persistWrite(() async {
          final landed = await gate(row);
          if (!landed && onDurableReject != null) {
            // The ledger refused the row — read back what it actually
            // keeps under this deterministic id so the in-memory mint
            // reconciles to canonical (null = nothing persisted).
            double? canonical;
            try {
              canonical = await db.getCreditTransactionAmount(tx.id);
            } catch (_) {
              canonical = null;
            }
            onDurableReject(tx, canonical);
          }
        }());
      }
    }
    return tx;
  }

  /// Re-resolves the held-key set and refreshes [_heldAttestedKeys]
  /// (canonical spellings). A null resolver or a resolving failure
  /// leaves the cache untouched — transient failures must not shrink
  /// the egress view mid-flight; the durable write-time gate re-resolves
  /// independently, so staleness here can never become canonical.
  /// Returns the freshly resolved canonical set, or the stale cache when
  /// resolution failed.
  Future<Set<String>> _refreshHeldAttestedKeys() async {
    final resolver = _localProverPubkeys;
    if (resolver == null) return _heldAttestedKeys;
    try {
      final keys = await resolver();
      if (keys != null) {
        _heldAttestedKeys = keys.map(WorkReceipt.canonicalPubkey).toSet();
      }
    } catch (_) {
      // Transient resolution failure — keep the last-known cache.
    }
    return _heldAttestedKeys;
  }

  /// Reconciles an in-memory mint whose deterministic-id row the ledger
  /// refused (a second CreditService instance already owns
  /// `tx_bounty_payout_<id>`/`tx_escrow_release_<id>` — the stale-view
  /// residual). [canonicalAmount] is what the durable row actually
  /// carries: identical → this instance's mint equals canonical, nothing
  /// to unwind; different → align to canonical; null (nothing persisted)
  /// → full rollback. The in-memory correction runs after the
  /// synchronous caller already saw the mint — a stale-view window is
  /// bounded by durability, not by the check.
  void _reconcileMintedCredit(CreditTransaction tx, double? canonicalAmount) {
    final delta = (canonicalAmount ?? 0.0) - tx.amount;
    if (delta == 0.0 && canonicalAmount != null) {
      return; // our mint is exactly what the ledger kept
    }
    _balance = (_balance + delta).clamp(0.0, double.infinity);
    _totalVerificationEarned =
        (_totalVerificationEarned + delta).clamp(0.0, double.infinity);
    _transactions.remove(tx);
    if (canonicalAmount != null && canonicalAmount != 0.0) {
      // Keep the canonical row's amount in the in-memory history so
      // displays/replays of this instance agree with the durable one.
      _transactions.add(CreditTransaction(
        id: tx.id,
        timestamp: tx.timestamp,
        type: tx.type,
        amount: canonicalAmount,
        description: tx.description,
        referenceId: tx.referenceId,
        hash: tx.hash,
        isAttested: tx.isAttested,
        attestedPubkey: tx.attestedPubkey,
      ));
    }
    debugPrint('CreditService: reconciled ${tx.id} to canonical amount '
        '$canonicalAmount (was ${tx.amount}) — a second writer owns '
        'the durable row');
    notifyListeners();
  }

  /// Rolls back an attested debit the durable held-key gate refused
  /// ([AppDatabase.insertAttestedDebitIfCovered]) — a stale-view
  /// instance that minted an egress over attested value the ledger
  /// doesn't back. The synchronous caller already consumed `true`
  /// (documented residual: an emitted artifact can't be recalled — the
  /// gate's job is to keep the over-spend non-canonical and bound the
  /// drain), so this restores balance, treasury and attested-burned
  /// accounting exactly.
  void _rollbackAttestedDebit(CreditTransaction tx) {
    final debit = -tx.amount; // tx.amount is negative
    _attestedBurned = (_attestedBurned - debit).clamp(0.0, double.infinity);
    _balance += debit;
    final fee = debit * protocolFeeRate;
    _protocolTreasury -= fee;
    _totalFeesContributed =
        (_totalFeesContributed - fee).clamp(0.0, double.infinity);
    _totalSpent = (_totalSpent - debit).clamp(0.0, double.infinity);
    _transactions.remove(tx);
    debugPrint('CreditService: attested debit ${tx.id} rolled back — '
        'the durable held-key attested sum does not cover it');
    notifyListeners();
  }

  /// Write-time re-validation for attested egress (multi-instance
  /// stale-view residual): resolves the CURRENT held keys fresh, then
  /// lets the ledger decide whether the durable scoped attested sum
  /// covers the debit — the in-memory [attestedBalance] check already
  /// ran as the synchronous fast path.
  Future<bool> _persistAttestedDebit(
      AppDatabase db, Map<String, dynamic> row, double credits) async {
    final held = await _refreshHeldAttestedKeys();
    return db.insertAttestedDebitIfCovered(row,
        heldAttestedPubkeys: held, requiredCredits: credits);
  }

  /// Tracks a best-effort database write so [settled] can await it, and
  /// swallows failures — a broken database must never break a mint.
  void _persistWrite(Future<void> write) {
    final tracked = write.catchError((Object e) {
      debugPrint('CreditService: best-effort ledger write failed: $e');
    });
    _pendingWrites.add(tracked);
    unawaited(tracked.whenComplete(() => _pendingWrites.remove(tracked)));
  }

  /// Whether any transaction — persisted or recorded locally — is the
  /// genesis welcome allocation. Matches the deterministic
  /// [_kGenesisTxId] as well as the description marker used by older
  /// builds that wrote genesis under a random id.
  bool get _hasGenesisTx => _transactions.any(
      (t) => t.id == _kGenesisTxId || t.description.contains(_kGenesisMarker));

  /// Rebuilds [_balance], [_attestedMintedByKey] and [_attestedBurned]
  /// by replaying the transaction list in chronological order — the
  /// ledger (plus any locally recorded rows) is the source of truth, so
  /// a restart can neither reset the balance to a fresh genesis nor
  /// re-grant it. Ordinary debits burn unattested-first, matching
  /// [_burnForDebit]; attested-flagged debit rows (external egress,
  /// [spendCredits] with `isAttested: true`) settle against the attested
  /// pool directly — replaying them through the unattested-first path
  /// would resurrect the egressed quota on every restart.
  /// Storage-reward debits are PoR penalties: the runtime floor caps
  /// them at the live balance, so replay applies the same floor — a
  /// clamped debit must never become durable phantom debt.
  ///
  /// Attested mints accrue per `attested_pubkey` (canonical, `''` =
  /// unscoped legacy bucket); burns are wallet-wide, matching
  /// [_burnForDebit]'s internal-burn semantics.
  void _rebuildBalance() {
    var b = 0.0;
    var burned = 0.0;
    final minted = <String, double>{};
    double mintedTotal() => minted.values.fold(0.0, (sum, m) => sum + m);
    for (final tx in _transactions) {
      if (tx.amount >= 0) {
        b += tx.amount;
        if (tx.isAttested) {
          final key = tx.attestedPubkey ?? _kUnscopedAttested;
          minted[key] = (minted[key] ?? 0.0) + tx.amount;
        }
      } else if (tx.type == CreditType.storageReward) {
        // PoR penalty: the runtime can only ever have deducted
        // min(|amount|, balance-at-the-time) — apply the same floor.
        final applied = (-tx.amount).clamp(0.0, b);
        b -= applied;
      } else if (tx.isAttested) {
        // Attested-flagged debit (external egress): settles against
        // the attested pool directly — never routed through the
        // unattested-first burn.
        burned += -tx.amount;
        b += tx.amount;
      } else {
        final spend = -tx.amount;
        final unattested = b - (mintedTotal() - burned);
        final burn = spend - (unattested > 0.0 ? unattested : 0.0);
        if (burn > 0.0) burned += burn;
        b += tx.amount;
      }
    }
    _balance = b.clamp(0.0, double.infinity);
    _attestedBurned = burned.clamp(0.0, double.infinity);
    _attestedMintedByKey
      ..clear()
      ..addAll(minted);
  }

  /// Best-effort targeted id-prefix read for hydration (RE-W): a failed
  /// listing resolves to null so the dedup rebuild can degrade to the
  /// windowed scan instead of taking all of hydration down with it.
  static Future<List<String>?> _tryIdsWithPrefix(
          AppDatabase db, String prefix) =>
      db
          .getCreditTransactionIdsWithPrefix(prefix)
          .then<List<String>?>((ids) => ids, onError: (_) => null);

  /// Loads persisted state so the credit economy survives restarts:
  /// today's mint-cap counters and the ledger history. When the ledger
  /// already contains rows it is treated as the source of truth — the
  /// balance is rebuilt from it and no second genesis grant is issued.
  Future<void> _hydrate(double initialBalance) async {
    final db = _db;
    if (db == null) {
      _hydratedComplete = true;
      return;
    }
    try {
      final dayKey = _dayKey();

      // Issue every hydration read UP FRONT so the two RE-W prefix
      // listings stay off the critical path — sequential round-trips
      // here would lengthen [ready] and let mutator-gated callers race
      // a slower hydration. Each failed prefix read resolves to null
      // via [_tryIdsWithPrefix] and degrades to the windowed scan
      // below instead of taking all of hydration down with it.
      const hydrationWindow = 100000;
      final mintedF = db.getDailyMinted(dayKey);
      final rowsF = db.getCreditTransactions(limit: hydrationWindow);
      final payoutIdsF = _tryIdsWithPrefix(db, _kBountyPayoutTxPrefix);
      final releaseIdsF = _tryIdsWithPrefix(db, _kEscrowReleaseTxPrefix);
      final genesisF = db.hasGenesisTransaction();

      // 1. Restore today's mint-cap counters, keeping the maximum of the
      // persisted and in-memory values so a counter can never be
      // clobbered into under-recording the day's mints (E-T2 #1).
      final minted = await mintedF;
      for (final entry in minted.entries) {
        final key = '$dayKey:${entry.key}';
        final inMemory = _dailyMinted[key] ?? 0.0;
        _dailyMinted[key] = entry.value > inMemory ? entry.value : inMemory;
      }

      // 2. Warm ledger history (query returns newest-first).
      final rows = await rowsF;
      final persisted =
          rows.map(CreditTransaction.fromJson).toList().reversed.toList();
      final knownIds = _transactions.map((t) => t.id).toSet();
      _transactions.insertAll(
          0, persisted.where((t) => !knownIds.contains(t.id)));

      // Rebuild the dedup sets from persisted deterministic-id rows —
      // the payout row is the durable "already paid" record (a
      // restarted service cannot re-pay a bounty through a direct
      // awardBountyEscrow call, E-REV4-A residual), and the release row
      // is the durable "already released" record (a restart cannot
      // re-refund an escrow through releaseEscrow, Safety 6c).
      // TARGETED prefix reads over the FULL table — never the windowed
      // replay (RE-W): rows beyond the hydration window are invisible
      // to a _transactions scan and would false-orphan the dedup
      // record, re-minting a durably-paid bounty or re-releasing a
      // refunded escrow. Per-set windowed fallback for when the prefix
      // read itself failed — incomplete beyond the window, but
      // strictly better than an empty set.
      final payoutIds = await payoutIdsF;
      if (payoutIds != null) {
        for (final id in payoutIds) {
          _paidBountyIds.add(id.substring(_kBountyPayoutTxPrefix.length));
        }
      } else {
        for (final tx in _transactions) {
          if (tx.id.startsWith(_kBountyPayoutTxPrefix)) {
            _paidBountyIds.add(tx.id.substring(_kBountyPayoutTxPrefix.length));
          }
        }
      }
      final releaseIds = await releaseIdsF;
      if (releaseIds != null) {
        for (final id in releaseIds) {
          _releasedEscrowIds.add(id.substring(_kEscrowReleaseTxPrefix.length));
        }
      } else {
        for (final tx in _transactions) {
          if (tx.id.startsWith(_kEscrowReleaseTxPrefix)) {
            _releasedEscrowIds
                .add(tx.id.substring(_kEscrowReleaseTxPrefix.length));
          }
        }
      }

      // A full window means older rows were dropped silently: replaying
      // the truncated list would compute a WRONG balance and the
      // in-memory genesis scan would miss a genesis row beyond the
      // window (double genesis). Reconstruct the balance from
      // SUM(amount) over the full table and check genesis directly.
      // The sum is taken BEFORE any local grant so the just-issued
      // genesis write can never race it.
      final truncated = rows.length == hydrationWindow;
      double? ledgerSum;
      if (truncated) {
        debugPrint('CreditService: ledger hydration filled the '
            '$hydrationWindow-row window — falling back to SUM(amount) '
            'for balance reconstruction; attested value cannot be '
            'replayed from a truncated window and is conservatively '
            'zeroed (egress under-counts, never over-counts).');
        ledgerSum = await db.getLedgerBalanceSum();
      }

      // 3. Genesis is granted iff no genesis row exists anywhere — a
      // ledger with activity but no genesis row still receives exactly
      // one (E-T2 #7), and two instances racing a fresh database converge
      // on a single row via the deterministic [_kGenesisTxId] primary
      // key (E-T2 #3). The direct DB query is authoritative — the
      // in-memory scan only covers the (possibly truncated) window.
      // genesisF was issued with the reads above — always awaited so a
      // rejection propagates into this try (never an unhandled error).
      final genesisExists = _hasGenesisTx || await genesisF;
      var grantedGenesis = false;
      if (initialBalance > 0 && !genesisExists) {
        _recordTransaction(
          id: _kGenesisTxId,
          type: CreditType.verificationReward,
          amount: initialBalance,
          description: '$_kGenesisMarker Welcome Allocation',
          isAttested: false,
        );
        grantedGenesis = true;
      }
      if (truncated) {
        // ledgerSum predates the grant above, so the local grant is
        // added deterministically — never double-counted via a write
        // that may or may not have landed inside the SUM.
        _balance =
            ((ledgerSum ?? 0.0) + (grantedGenesis ? initialBalance : 0.0))
                .clamp(0.0, double.infinity);
        _attestedBurned = 0.0;
        _attestedMintedByKey.clear();
      } else {
        _rebuildBalance();
      }
      // Warm the held-key cache for the prover-scoped attestedBalance
      // getter — a resolver failure keeps the empty set (only unscoped
      // legacy value is egress-eligible until the next refresh).
      await _refreshHeldAttestedKeys();
    } catch (e, st) {
      // Degrade to in-memory operation; never let persistence break awards.
      debugPrint('CreditService: hydration failed, running in-memory: $e\n$st');
      // Grant genesis when the ledger lacks it — not merely when the
      // local list is empty — so a partial hydration can never strand
      // the welcome allocation out of the persisted ledger (E-T2 #7).
      if (initialBalance > 0 && !_hasGenesisTx) {
        _recordTransaction(
          id: _kGenesisTxId,
          type: CreditType.verificationReward,
          amount: initialBalance,
          description: '$_kGenesisMarker Welcome Allocation',
          isAttested: false,
        );
      }
      _rebuildBalance();
    }
    _hydratedComplete = true;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }
}
