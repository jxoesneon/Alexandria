import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'credit_models.dart';
import 'poch_service.dart';

/// Provider for CreditService
final creditServiceProvider = ChangeNotifierProvider<CreditService>((ref) {
  final pochService = ref.read(pochServiceProvider);
  return CreditService(pochService: pochService);
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

  double _balance;
  double _archivalCommonsPool;
  double _protocolTreasury;

  double _totalStorageEarned = 0.0;
  double _totalComputeEarned = 0.0;
  double _totalVerificationEarned = 0.0;
  double _totalSponsorshipKickbacks = 0.0;
  double _totalSpent = 0.0;
  double _totalFeesContributed = 0.0;

  final List<CreditTransaction> _transactions = [];

  CreditService({
    PoCHService? pochService,
    double initialBalance = 100.0, // Initial welcome grant for new users
  })  : _pochService = pochService,
        _balance = initialBalance,
        _archivalCommonsPool = 250.0,
        _protocolTreasury = 50.0 {
    // Record genesis grant if balance > 0
    if (initialBalance > 0) {
      _recordTransaction(
        type: CreditType.verificationReward,
        amount: initialBalance,
        description: 'Genesis Common Heritage Welcome Allocation',
      );
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
  double _capDailyMint(CreditType type, double requested) {
    final cap = dailyMintCaps[type];
    if (cap == null) return requested;
    final key = '${_dayKey()}:${type.name}';
    final remaining = (cap - (_dailyMinted[key] ?? 0.0)).clamp(0.0, cap);
    final granted = requested.clamp(0.0, remaining);
    _dailyMinted[key] = (_dailyMinted[key] ?? 0.0) + granted;
    return granted;
  }

  /// Dynamic Rarity Weight Function (ALX-005 §4.1). Multipliers above 1.0
  /// require [rarityAttested]: an independent peer's attestation that the
  /// content is genuinely under-replicated. A claimant's own self-reported
  /// peer count can never unlock rarity rewards (self-dealing guard).
  static double rarityWeightFor(int peerCount, {bool rarityAttested = false}) {
    if (!rarityAttested) return 1.0;
    if (peerCount <= 1) return 5.0; // Critically Endangered
    if (peerCount == 2) return 3.0; // Vulnerable
    if (peerCount < 5) return 1.5; // Near-Safe
    return 1.0; // Healthy
  }

  /// Award credits for Proof of Retrievability (PoR) storage retention (Pillar 1)
  double awardStorageCredits({
    required int sizeBytes,
    required int peerCount,
    required bool porPassed,
    String? cid,
    bool rarityAttested = false,
  }) {
    if (!porPassed) {
      // Slashing penalty for failed PoR challenge
      const penalty = 5.0;
      _balance = (_balance - penalty).clamp(0.0, double.infinity);
      _recordTransaction(
        type: CreditType.storageReward,
        amount: -penalty,
        description: 'PoR Challenge Failure Penalty (CID: ${cid ?? "unknown"})',
        referenceId: cid,
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
    if (amount <= 0) return 0.0;
    _balance += amount;
    _totalVerificationEarned += amount;
    _recordTransaction(
      type: CreditType.verificationReward,
      amount: amount,
      description: 'Bounty Escrow Payout ($bountyId, CID: $cid)',
      referenceId: cid,
    );
    notifyListeners();
    return amount;
  }

  /// Award credits from an ethical, opt-in institutional sponsorship impression (ALX-005 §5.2)
  /// Splits gross: 85% to client, 10% to endangered seeders, 5% to protocol treasury
  ImpressionReceipt awardSponsorshipKickback({
    required String campaignId,
    required double grossCredits,
    required double dwellTimeSeconds,
  }) {
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
    if (amount <= 0 || _balance < amount) {
      return false;
    }

    final fee = amount * protocolFeeRate;
    _balance -= amount;
    _protocolTreasury += fee;
    _totalSpent += amount;
    _totalFeesContributed += fee;

    _recordTransaction(
      type: debitType,
      amount: -amount,
      description: '$reason (incl. ${(protocolFeeRate * 100).toInt()}% treasury fee)',
      referenceId: referenceId,
    );

    notifyListeners();
    return true;
  }

  void _recordTransaction({
    required CreditType type,
    required double amount,
    required String description,
    String? referenceId,
  }) {
    final id = 'tx_${DateTime.now().microsecondsSinceEpoch}_${_transactions.length}';
    final timestamp = DateTime.now();
    final hash = CreditTransaction.computeHash(
      id: id,
      timestamp: timestamp,
      type: type,
      amount: amount,
      description: description,
      referenceId: referenceId,
    );

    _transactions.add(CreditTransaction(
      id: id,
      timestamp: timestamp,
      type: type,
      amount: amount,
      description: description,
      referenceId: referenceId,
      hash: hash,
    ));
  }
}
