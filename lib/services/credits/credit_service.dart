import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database.dart' hide CreditTransaction, WorkReceipt;
import 'credit_models.dart';
import 'poch_service.dart';
import 'work_receipt.dart';

/// Provider for CreditService
final creditServiceProvider = ChangeNotifierProvider<CreditService>((ref) {
  final pochService = ref.read(pochServiceProvider);
  final service =
      CreditService(pochService: pochService, db: ref.read(databaseProvider));
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

  /// Description marker identifying genesis rows, including rows written
  /// by older builds that used a random id.
  static const String _kGenesisMarker = 'Genesis Common Heritage';

  /// Outstanding best-effort writes to [_db], tracked so tests and
  /// shutdown paths can await durability via [settled].
  final Set<Future<void>> _pendingWrites = {};

  CreditService({
    PoCHService? pochService,
    AppDatabase? db,
    double initialBalance = 100.0, // Initial welcome grant for new users
  })  : _pochService = pochService,
        _db = db,
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
  double get attestedBalance =>
      _attestedBalance.clamp(0.0, _balance < 0.0 ? 0.0 : _balance);

  /// Self-certified value: spendable inside Alexandria (replication fees,
  /// bounties) but barred from egress. Clamped at zero so a partial ledger
  /// can never report a negative internal balance.
  double get unattestedBalance =>
      (_balance - attestedBalance).clamp(0.0, double.infinity);

  /// Protocol micro-fee rate on spendable transactions (5% - ALX-005 §5.2)
  static const double protocolFeeRate = 0.05;

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
    if (earned <= 0) return 0.0;

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
    if (earned <= 0) return 0.0;

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
    if (amount <= 0) return 0.0;

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
  double awardBountyEscrow({
    required double amount,
    required String bountyId,
    required String cid,
  }) {
    if (_rejectIfUnhydrated('awardBountyEscrow')) return 0.0;
    if (amount <= 0) return 0.0;
    _balance += amount;
    _totalVerificationEarned += amount;
    _recordTransaction(
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
  /// Guards, in order:
  ///  * [WorkReceipt.isVerifierSigned] — an unsigned artifact carries no
  ///    attestation weight;
  ///  * `!receipt.isSelfIssued` — prover == verifier is a self-declaration;
  ///  * `receipt.verifierPubkey != localPubkeyHex` — the caller MUST supply
  ///    the local identity key (same hex encoding the PoR service stamps
  ///    into `verifierPubkey`) so a receipt this node signed itself can
  ///    never mint attested value locally (self-dealing guard);
  ///  * `!receipt.isExpired()` — stale receipts cannot be claimed;
  ///  * the receipt row must exist UNSPENT in the ledger store, and the
  ///    claim itself is a single atomic conditional UPDATE
  ///    ([AppDatabase.claimReceiptAtomically]) — a lost CAS race or a
  ///    replay returns 0.0;
  ///  * the mint is STILL subject to the daily accrual caps (safety
  ///    floor): a claim can never exceed the day's remaining allowance
  ///    for its mapped [CreditType] ('storage'→storageReward,
  ///    'compute'→computeReward, 'verification'→verificationReward,
  ///    other→storageReward). A cap-exhausted claim still consumes the
  ///    receipt — it may only ever mint once (anti-replay).
  ///
  /// Returns the minted amount, or 0.0 on any refusal. Requires
  /// persistent mode: an in-memory service has no CAS primitive to dedup
  /// claims against. Signature VALIDITY is the caller's duty — verify
  /// [WorkReceipt.verifyVerifierSignature] before claiming.
  Future<double> claimVerifiedReceipt(
    WorkReceipt receipt, {
    required String localPubkeyHex,
  }) async {
    // Async path — await hydration so the daily-cap counters and balance
    // are real rather than phantom pre-hydration state.
    await _hydrated;
    final db = _db;
    if (db == null) return 0.0;

    // The receipt must name THIS node as prover — a held artifact naming
    // a foreign prover is that prover's claim instrument, not ours;
    // claiming it would be claim theft (REV1 C3).
    if (!receipt.isVerifierSigned ||
        receipt.isSelfIssued ||
        receipt.proverPubkey != localPubkeyHex ||
        receipt.verifierPubkey == localPubkeyHex ||
        receipt.isExpired() ||
        !(receipt.amount > 0)) {
      return 0.0;
    }

    try {
      // Cheap pre-check for honest failures (missing/known-spent row);
      // the CAS below remains the authoritative dedup primitive.
      final row = await db.getWorkReceipt(receipt.receiptId);
      if (row == null || row['spent'] == true) return 0.0;

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
    if (amount <= 0 || _balance < amount) {
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
  bool debitEscrow({required double amount, required String referenceId}) {
    if (_rejectIfUnhydrated('debitEscrow')) return false;
    if (amount <= 0 || _balance < amount) {
      return false;
    }
    _burnForDebit(amount);
    _balance -= amount;
    _totalSpent += amount;
    _recordTransaction(
      type: CreditType.priorityAccessDebit,
      amount: -amount,
      description: 'Bounty Escrow Hold ($referenceId)',
      referenceId: referenceId,
      isAttested: false,
    );
    notifyListeners();
    return true;
  }

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
    final txId = id ??
        'tx_${DateTime.now().microsecondsSinceEpoch}_${_transactions.length}';
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

      // 1. Restore today's mint-cap counters, keeping the maximum of the
      // persisted and in-memory values so a counter can never be
      // clobbered into under-recording the day's mints (E-T2 #1).
      final minted = await db.getDailyMinted(dayKey);
      for (final entry in minted.entries) {
        final key = '$dayKey:${entry.key}';
        final inMemory = _dailyMinted[key] ?? 0.0;
        _dailyMinted[key] = entry.value > inMemory ? entry.value : inMemory;
      }

      // 2. Warm ledger history (query returns newest-first).
      const hydrationWindow = 100000;
      final rows = await db.getCreditTransactions(limit: hydrationWindow);
      final persisted = rows
          .map(CreditTransaction.fromJson)
          .toList()
          .reversed
          .toList();
      final knownIds = _transactions.map((t) => t.id).toSet();
      _transactions.insertAll(
          0, persisted.where((t) => !knownIds.contains(t.id)));

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
      final genesisExists = _hasGenesisTx || await db.hasGenesisTransaction();
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

