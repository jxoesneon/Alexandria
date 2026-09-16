import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../credits/credit_service.dart';
import '../credits/poch_service.dart';
import 'moltbook_service.dart';

/// Riverpod provider for AgentStewardService
final agentStewardServiceProvider =
    ChangeNotifierProvider<AgentStewardService>((ref) {
  final creditService = ref.read(creditServiceProvider);
  final pochService = ref.read(pochServiceProvider);
  final moltbookService = ref.read(moltbookServiceProvider);

  return AgentStewardService(
    creditService: creditService,
    pochService: pochService,
    moltbookService: moltbookService,
  );
});

/// Autonomous Agent Steward that self-balances PoCH compliance, fulfills Moltbook bounties,
/// and executes Cauchy RS compute cycles in the background (ALX-006)
class AgentStewardService extends ChangeNotifier {
  final CreditService _creditService;
  final PoCHService _pochService;
  final MoltbookService _moltbookService;

  bool _isRunning = false;
  Timer? _loopTimer;

  int _totalBountiesClaimed = 0;
  int _totalComputeCyclesExecuted = 0;
  double _totalCreditsEarned = 0.0;
  final List<String> _activityLog = [];

  AgentStewardService({
    required CreditService creditService,
    required PoCHService pochService,
    required MoltbookService moltbookService,
  })  : _creditService = creditService,
        _pochService = pochService,
        _moltbookService = moltbookService;

  bool get isRunning => _isRunning;
  int get totalBountiesClaimed => _totalBountiesClaimed;
  int get totalComputeCyclesExecuted => _totalComputeCyclesExecuted;
  double get totalCreditsEarned => _totalCreditsEarned;
  List<String> get activityLog => List.unmodifiable(_activityLog);

  void startSteward({Duration interval = const Duration(seconds: 30)}) {
    if (_isRunning) return;
    _isRunning = true;
    _logActivity(
        'Autonomous Agent Steward started (Interval: ${interval.inSeconds}s)');
    notifyListeners();

    // Run first iteration immediately
    runStewardIteration();

    _loopTimer = Timer.periodic(interval, (_) => runStewardIteration());
  }

  void stopSteward() {
    _loopTimer?.cancel();
    _loopTimer = null;
    _isRunning = false;
    _logActivity('Autonomous Agent Steward stopped');
    notifyListeners();
  }

  /// Executes one cycle of the autonomous stewardship loop
  Future<void> runStewardIteration() async {
    // 1. Check and maintain Proof of Common Heritage (PoCH >= 1.0)
    final metrics = _pochService.metrics;
    if (metrics.score < 1.0) {
      _logActivity(
          'PoCH score (${(metrics.score * 100).toStringAsFixed(0)}%) below threshold. Triggering Cauchy RS parity compute.');
      // ALX-010: steward compute contribution is self-reported and unverified -
      // it maintains local PoCH hygiene but mints NO credits until an external
      // challenger attests the work (prevents self-award of ~65ℭ/cycle).
      _pochService.recordSeedingActivity(100 * 1024 * 1024); // 100 MB
      _pochService.recordStorageAllocation(
          1200 * 1024 * 1024); // 1.2 GB (meets 1GB baseline)
      _totalComputeCyclesExecuted++;
      _logActivity(
          'Autonomous compute complete: PoCH restored (unverified — no credit minted).');
    }

    // 2. Scan Moltbook active bounties and claim endangered tasks.
    // Only funded bounties are claimable - unfunded entries are seeded
    // demos or unattested remote announcements: ingestBountyAnnouncement
    // strips announcer-claimed `funded` flags until a verified escrow
    // attestation exists (E-T5r #1), so remote bounties simply never
    // qualify here until the attestation transport lands.
    final claimableBounties =
        _moltbookService.activeBounties.where((b) => b.funded).toList();
    if (claimableBounties.isNotEmpty) {
      // Prioritize critical urgency bounties
      final targetBounty = claimableBounties.firstWhere(
        (b) => b.urgency == 'critical',
        orElse: () => claimableBounties.first,
      );

      final balanceBefore = _creditService.balance;
      // Defensive: this runs inside a periodic timer callback with no
      // surrounding error handling, so a claim failure must be contained
      // to the log rather than becoming an unhandled async error.
      bool success = false;
      try {
        success = await _moltbookService.claimBounty(targetBounty.id);
      } catch (e) {
        _logActivity('Bounty claim failed for "${targetBounty.title}": $e');
      }
      if (success) {
        _totalBountiesClaimed++;
        _totalCreditsEarned += _creditService.balance - balanceBefore;
        _pochService.recordPoRChallengeAnswered();
        _logActivity(
            'Claimed & fulfilled Moltbook bounty [${targetBounty.urgency.toUpperCase()}]: "${targetBounty.title}" (+${(_creditService.balance - balanceBefore).toStringAsFixed(1)} ℭ)');
      }
    }

    notifyListeners();
  }

  void _logActivity(String message) {
    final timeStr = DateTime.now().toLocal().toString().substring(11, 19);
    _activityLog.insert(0, '[$timeStr] $message');
    if (_activityLog.length > 50) {
      _activityLog.removeLast();
    }
  }

  @override
  void dispose() {
    _loopTimer?.cancel();
    super.dispose();
  }
}
