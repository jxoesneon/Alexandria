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

/// Resolves the local node's canonical identity pubkey (hex) — the
/// identity [CreditService.claimVerifiedReceipt] may bind as prover.
/// Returns null when the node has no usable identity (claims then
/// refuse). Injected as a function — the same ambient-authority idiom
/// as [ReceiptSignatureVerifier] — so [CreditService] never takes a
/// concrete IdentityService dependency.
typedef LocalProverPubkeyResolver = FutureOr<String?> Function();

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
    // (Review REV3): a claim can no longer ASSERT a prover key — it must
    // resolve to the node's real identity. No identity → null → every
    // claim refuses. A missing identity is never auto-created here:
    // minting a fresh key could never satisfy the prover binding anyway.
    localProverPubkeyHex: () async {
      try {
        final identity =
            await ref.read(identityServiceProvider).getIdentity();
        return identity == null ? null : bytesToHex(identity.publicKey);
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
        return await ref
            .read(identityServiceProvider)
            .knownLocalPubkeyHexes();
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

  /// Ambient resolver for the local node's canonical identity pubkey
  /// (hex) — the ONLY identity [claimVerifiedReceipt] may bind as
  /// prover (Review REV3). When null, or when it resolves to
  /// null/empty, every claim fails closed: there is no longer a
  /// caller-supplied "local" key to assert.
  final LocalProverPubkeyResolver? _localProverPubkeyHex;

  /// Ambient resolver for EVERY public key this node has ever held —
  /// current identity plus retired rotation predecessors (Safety item
  /// 3). [claimVerifiedReceipt] refuses receipts verifier-signed by any
  /// of them, so key rotation cannot make a self-signed receipt look
  /// foreign-attested. Null resolver, or a null/empty resolution,
  /// degrades to the current-key-only check — absent history must not
  /// break claims.
  final KnownLocalPubkeysResolver? _knownLocalPubkeys;

  double _balance;

  /// Running net of attested value: attested credits add, debits burn the
  /// unattested portion first and then attested (see [_burnForDebit]).
  /// Recomputed from the ledger on hydration by [_rebuildBalance].
  double _attestedBalance = 0.0;
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
  /// caller-controlled input can forge (Review REV4a F2): [spendCredits]
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
  /// belt-level dedup (Review REV3): the payout primitive itself refuses
  /// a second payout for the same id, so a bypassed or replayed claim
  /// layer can never double-mint escrow. Also consulted by
  /// [releaseEscrow] (Review REV4a F1): an escrow already PAID OUT must
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
  /// [awardBountyEscrow] (Review REV4a F1): an escrow already REFUNDED
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
    LocalProverPubkeyResolver? localProverPubkeyHex,
    KnownLocalPubkeysResolver? knownLocalPubkeys,
    double initialBalance = 100.0, // Initial welcome grant for new users
  })  : _pochService = pochService,
        _db = db,
        _receiptVerifier = receiptVerifier,
        _localProverPubkeyHex = localProverPubkeyHex,
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
  List<CreditTransaction> get transactions => List.unmodifiable(_transactions.reversed);

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
  /// only value eligible to egress to external systems; the egress gate
  /// reads this getter. NET of spending — internal debits consume
  /// unattested value first, then attested, so attestation already spent
  /// internally can never back a second egress (E-T3 #1).
  ///
  /// Wallet-scoped under the single-identity model — the single-String
  /// [LocalProverPubkeyResolver] signature is the forcing point: if
  /// multi-identity lands, `credit_transactions` gains an
  /// `attested_pubkey` column and this becomes a per-pubkey sum over
  /// currently-held keys.
  double get attestedBalance =>
      _attestedBalance.clamp(0.0, _balance < 0.0 ? 0.0 : _balance);

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
    // Non-finite requests mint nothing (Review REV4a F4): NaN defeats
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
      // Slashing penalty for failed PoR challenge
      const penalty = 5.0;
      _balance = (_balance - penalty).clamp(0.0, double.infinity);
      _recordTransaction(
        type: CreditType.storageReward,
        amount: -penalty,
        description: 'PoR Challenge Failure Penalty (CID: ${cid ?? "unknown"})',
        referenceId: cid,
        isAttested: false,
      );
      notifyListeners();
      return -penalty;
    }

    final rarityWeight = rarityWeightFor(peerCount, rarityAttested: rarityAttested);

    final mbSize = sizeBytes / (1024 * 1024);
    final earned = _capDailyMint(
        CreditType.storageReward, (mbSize * 0.1 * rarityWeight).clamp(0.1, 50.0));
    if (!earned.isFinite || earned <= 0) return 0.0;

    _balance += earned;
    _totalStorageEarned += earned;

    _pochService?.recordPoRChallengeAnswered();

    _recordTransaction(
      type: CreditType.storageReward,
      amount: earned,
      description: 'PoR Storage Reward (${rarityWeight}x rarity, CID: ${cid ?? "block"})',
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
    final earned = _capDailyMint(
        CreditType.computeReward, (2.0 * cauchyMb) + (0.5 * fastCdcMb) + (5.0 * ocrPages));
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
  /// the mint (Review REV3 belt-level dedup): a refused call — malformed
  /// id, unhydrated service, non-positive/non-finite amount — does NOT
  /// consume the id, so a probe or early call can never permanently
  /// burn a legit payout (E-REV4-B F3). Double-payment remains impossible
  /// because the set-add is atomic with the mint in a synchronous
  /// method.
  ///
  /// Reverse-direction double-dip guard (Review REV4a F1): an escrow
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
  /// through a fresh service instance (E-REV4-A residual). Residual: a
  /// payout older than the hydration window could be missed — the
  /// durable `claimed_bounties` CAS in `MoltbookService.claimBounty`
  /// remains the authoritative gate.
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
    _recordTransaction(
      id: '$_kBountyPayoutTxPrefix$bountyId',
      type: CreditType.verificationReward,
      amount: amount,
      description: 'Bounty Escrow Payout ($bountyId, CID: $cid)',
      referenceId: cid,
      isAttested: false,
    );
    notifyListeners();
    return amount;
  }

  /// Claims a verifier-signed [WorkReceipt] as ATTESTED value — the only
  /// path that mints `isAttested` credit and therefore the only path that
  /// makes [attestedBalance] non-vacuous (ALX-010).
  ///
  /// The prover identity is bound TWO ways (Review REV3, ALX-012 §5.4):
  /// the "local" key is resolved through the injected
  /// [_localProverPubkeyHex] — ambient authority, never a caller-supplied
  /// string — and [claimSignatureB64] must be an Ed25519 signature by
  /// the PROVER key over the domain-separated claim preimage
  /// `'alexandria:receipt-claim:v{receipt.v}:{receipt.receiptId}'`
  /// (ASCII). `receiptId` is the sha256 of the canonical body, so the
  /// signature binds every field. Together they convert the receipt
  /// from a bearer instrument into a possession-bound one: a copied
  /// artifact cannot be claimed by a node that does not hold the prover
  /// private key, and a forked client cannot name a foreign prover key
  /// as "local". The artifact-carried `proverSig` stays unverified —
  /// it is issuance-time provenance, not the anti-theft mechanism.
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
  ///  * IN-PATH POSSESSION PROOF (Review REV3): [claimSignatureB64] must
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
  /// Returns the minted amount, or 0.0 on any refusal. Requires
  /// persistent mode: an in-memory service has no CAS primitive to dedup
  /// claims against.
  Future<double> claimVerifiedReceipt(
    WorkReceipt receipt, {
    required String claimSignatureB64,
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
      // The local prover key comes ONLY from the injected resolver —
      // ambient identity, never caller input. A null resolver or a null/
      // empty resolution refuses every claim. Identity is then compared
      // CANONICALLY via WorkReceipt.samePubkey — raw string equality is
      // defeatable by case/whitespace variants of the same hex key (an
      // UPPERCASE or space-padded verifierPubkey still decodes to the
      // local key, so a self-signed receipt could mint ATTESTED value).
      // All three key fields must also be non-empty: a '' prover against
      // a '' local key would otherwise satisfy the binding vacuously.
      final localPubkeyHex = await _localProverPubkeyHex?.call();

      // Rotation self-vouch history (Safety item 3): the self-dealing
      // check below is extended from "verifier is the CURRENT key" to
      // "verifier is ANY key this node has ever held" — importIdentity
      // rotation replaces the key, so a receipt signed by the retired
      // predecessor would otherwise look foreign and mint attested
      // value. The history resolver is deliberately FAIL-OPEN: a null
      // resolver, a null/empty resolution, or a throw all degrade to
      // the REV3 current-key check — absent history must not break
      // honest claims (unlike the prover resolver above, which fails
      // closed because an absent identity makes the claim void).
      Set<String>? knownLocal;
      try {
        knownLocal = await _knownLocalPubkeys?.call();
      } catch (_) {
        knownLocal = null;
      }
      bool verifierIsKnownLocal(String currentHex) {
        if (WorkReceipt.samePubkey(receipt.verifierPubkey, currentHex)) {
          return true;
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

      if (localPubkeyHex == null ||
          localPubkeyHex.isEmpty ||
          receipt.proverPubkey.isEmpty ||
          receipt.verifierPubkey.isEmpty ||
          !receipt.isVerifierSigned ||
          WorkReceipt.samePubkey(
              receipt.proverPubkey, receipt.verifierPubkey) ||
          !WorkReceipt.samePubkey(receipt.proverPubkey, localPubkeyHex) ||
          verifierIsKnownLocal(localPubkeyHex) ||
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

      // Possession proof (Review REV3): the caller must sign the
      // domain-separated claim preimage under the PROVER key the
      // receipt names. receiptId already binds the canonical body, so
      // this signature proves possession of the prover private key for
      // THIS artifact — a copied receipt presented by a node lacking the
      // key cannot mint. Malformed base64 throws into the fail-closed
      // try; a wrong-key/wrong-domain signature verifies false; either
      // way the row is left UNSPENT for the true prover's claim.
      final claimSigBytes = base64Decode(claimSignatureB64);
      if (claimSigBytes.length != 64 ||
          !await verifier(
            Uint8List.fromList(utf8.encode(
                'alexandria:receipt-claim:v${receipt.v}:${receipt.receiptId}')),
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

    _recordTransaction(
      type: type,
      amount: granted,
      description: 'Verified work receipt claim '
          '(${receipt.workType}, receipt ${receipt.receiptId})',
      referenceId: receipt.receiptId,
      isAttested: true,
    );
    notifyListeners();
    return granted;
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
    final clientKickback = _capDailyMint(
        CreditType.sponsorshipKickback, grossCredits * 0.85);
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
      description: 'Sponsorship Kickback (85% share of ${grossCredits.toStringAsFixed(1)} credits)',
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
  bool spendCredits({
    required double amount,
    required String reason,
    String? referenceId,
    CreditType debitType = CreditType.priorityAccessDebit,
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
    _burnForDebit(amount);
    _balance -= amount;
    _protocolTreasury += fee;
    _totalSpent += amount;
    _totalFeesContributed += fee;

    _recordTransaction(
      type: debitType,
      amount: -amount,
      description: '$reason (incl. ${(protocolFeeRate * 100).toInt()}% treasury fee)',
      referenceId: referenceId,
      isAttested: false,
    );

    notifyListeners();
    return true;
  }

  /// Debits credits into a bounty escrow WITHOUT the treasury fee — this is a
  /// hold, not a spend: the full amount is owed to the future claimant, so
  /// skimming it here would mint unbacked value on payout (ALX-010, Review
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
    _burnForDebit(amount);
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
    );
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
  /// (Review REV4a F2 + RE-B2):
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
  /// Forward-direction double-dip guard (Review REV4a F1): an escrow
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
  /// HYDRATION-WINDOW BOUND (RE-W): the hold scan iterates
  /// [_transactions] — the ~100k-row replay window. A hold row OLDER
  /// than the window is durable but unreadable here (the DAO prefix
  /// listing returns ids only, never amounts), so it cannot be
  /// released. This bound strands a cancel in the worst case — it can
  /// never re-mint: [_paidBountyIds] and [_releasedEscrowIds] are
  /// rebuilt from targeted prefix reads over the FULL table, so a
  /// paid-out or already-released escrow is refused regardless of the
  /// window.
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
    if (db != null) {
      try {
        if (await db.hasCreditTransaction(
            '$_kBountyPayoutTxPrefix$referenceId')) {
          // Durable proof-of-payment this instance never saw (written
          // out-of-band or after hydration) — refunding on top of it
          // double-mints the escrow.
          return 0.0;
        }
      } catch (_) {
        // Fail open: see the docstring — a broken store cannot persist
        // the dedup row, so this refund never becomes canonical.
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
    for (final tx in _transactions) {
      if (_isReleasableHold(tx, referenceId)) {
        found = true;
        refundAmount += -tx.amount;
      }
    }
    if (!found || !refundAmount.isFinite || refundAmount <= 0) {
      return 0.0;
    }

    _releasedEscrowIds.add(referenceId);
    _balance += refundAmount;
    // The hold added to _totalSpent at debit time; a release is the
    // debit unwound, so the session's net-spend stat unwinds with it.
    _totalSpent = (_totalSpent - refundAmount).clamp(0.0, double.infinity);
    _recordTransaction(
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

  /// Consumes [amount] of value for a debit, drawing on the self-certified
  /// (unattested) portion first and attested value only once that is
  /// exhausted. MUST be called before [_balance] is reduced — it reads the
  /// pre-debit balance. Guarantees `_attestedBalance` never goes negative.
  void _burnForDebit(double amount) {
    final unattested = _balance - _attestedBalance;
    final burn = amount - (unattested > 0.0 ? unattested : 0.0);
    if (burn > 0.0) {
      _attestedBalance -= burn;
      if (_attestedBalance < 0.0) _attestedBalance = 0.0;
    }
  }

  void _recordTransaction({
    required CreditType type,
    required double amount,
    required String description,
    String? id,
    String? referenceId,
    bool isAttested = false,
  }) {
    // [id] is normally time-derived; genesis passes the deterministic
    // [_kGenesisTxId] so racing instances collapse onto one ledger row.
    // The suffix is the monotonic [_txSeq] — NOT _transactions.length,
    // which resets per process and let a micros+length collision drop a
    // real ledger row via insertOrIgnore (Safety 6f).
    final txId = id ??
        'tx_${DateTime.now().microsecondsSinceEpoch}_${_txSeq++}';
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

    final tx = CreditTransaction(
      id: txId,
      timestamp: timestamp,
      type: type,
      amount: amount,
      description: description,
      referenceId: referenceId,
      hash: hash,
      isAttested: isAttested,
    );
    _transactions.add(tx);
    if (isAttested && amount > 0) {
      _attestedBalance += amount;
    }

    // Best-effort write-through: a persistence failure must never break
    // an award, so errors are swallowed inside [_persistWrite].
    final db = _db;
    if (db != null) {
      _persistWrite(db.insertCreditTransaction(<String, dynamic>{
        'id': tx.id,
        'timestamp': tx.timestamp,
        'type': tx.type.name,
        'amount': tx.amount,
        'description': tx.description,
        'referenceId': tx.referenceId,
        'hash': tx.hash,
        'isAttested': tx.isAttested,
      }));
    }
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
  bool get _hasGenesisTx => _transactions.any((t) =>
      t.id == _kGenesisTxId || t.description.contains(_kGenesisMarker));

  /// Rebuilds [_balance] and [_attestedBalance] by replaying the
  /// transaction list in chronological order — the ledger (plus any
  /// locally recorded rows) is the source of truth, so a restart can
  /// neither reset the balance to a fresh genesis nor re-grant it.
  /// Debits burn unattested-first, matching [_burnForDebit].
  void _rebuildBalance() {
    var b = 0.0;
    var a = 0.0;
    for (final tx in _transactions) {
      if (tx.amount >= 0) {
        b += tx.amount;
        if (tx.isAttested) a += tx.amount;
      } else {
        final spend = -tx.amount;
        final unattested = b - a;
        final burn = spend - (unattested > 0.0 ? unattested : 0.0);
        if (burn > 0.0) a -= burn;
        b += tx.amount;
      }
    }
    _balance = b.clamp(0.0, double.infinity);
    _attestedBalance = a.clamp(0.0, double.infinity);
  }

  /// Best-effort targeted id-prefix read for hydration (RE-W): a failed
  /// listing resolves to null so the dedup rebuild can degrade to the
  /// windowed scan instead of taking all of hydration down with it.
  static Future<List<String>?> _tryIdsWithPrefix(
          AppDatabase db, String prefix) =>
      db.getCreditTransactionIdsWithPrefix(prefix).then<List<String>?>(
          (ids) => ids,
          onError: (_) => null);

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
      final persisted = rows
          .map(CreditTransaction.fromJson)
          .toList()
          .reversed
          .toList();
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
            _paidBountyIds
                .add(tx.id.substring(_kBountyPayoutTxPrefix.length));
          }
        }
      }
      final releaseIds = await releaseIdsF;
      if (releaseIds != null) {
        for (final id in releaseIds) {
          _releasedEscrowIds
              .add(id.substring(_kEscrowReleaseTxPrefix.length));
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
        _balance = ((ledgerSum ?? 0.0) +
                (grantedGenesis ? initialBalance : 0.0))
            .clamp(0.0, double.infinity);
        _attestedBalance = 0.0;
      } else {
        _rebuildBalance();
      }
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

