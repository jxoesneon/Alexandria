import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../services/identity_service.dart';
import '../services/ledger_service.dart';

final governanceServiceProvider = Provider((ref) {
  final identityService = ref.watch(identityServiceProvider);
  final ledgerService = ref.watch(ledgerServiceProvider);
  return GovernanceService(identityService, ledgerService);
});

/// Types of proposals (Spec §18.1)
enum ProposalType {
  schemaChange, // Modify ContentManifest schema
  gatewayAddition, // Add new gateway to rotation
  priorityChange, // Change endangered threshold
  weightAdjustment, // Modify reputation weights
  emergency, // Emergency protocol changes
}

/// Proposal status
enum ProposalStatus { draft, active, approved, rejected, executed, expired }

/// Governance constants (Spec §18.2, §18.3)
class GovernanceConstants {
  static const int minReputationToVote = 10;
  static const int minAccountAgeDays = 30;
  static const int proposalRateLimitDays = 7;
  static const int minPinsForNewAccount = 10;

  /// Voting periods per proposal type (in days)
  static const Map<ProposalType, int> votingPeriods = {
    ProposalType.schemaChange: 14,
    ProposalType.gatewayAddition: 7,
    ProposalType.priorityChange: 7,
    ProposalType.weightAdjustment: 14,
    ProposalType.emergency: 3,
  };

  /// Quorum (minimum % of active voters required)
  static const Map<ProposalType, double> quorumThresholds = {
    ProposalType.schemaChange: 0.30,
    ProposalType.gatewayAddition: 0.20,
    ProposalType.priorityChange: 0.25,
    ProposalType.weightAdjustment: 0.30,
    ProposalType.emergency: 0.40,
  };

  /// Pass threshold (% of votes needed to approve)
  static const Map<ProposalType, double> passThresholds = {
    ProposalType.schemaChange: 0.67, // 2/3 supermajority
    ProposalType.gatewayAddition: 0.50, // Simple majority
    ProposalType.priorityChange: 0.60,
    ProposalType.weightAdjustment: 0.67,
    ProposalType.emergency: 0.75, // 3/4 supermajority
  };
}

/// A governance vote
class GovernanceVote {
  final String voterId;
  final double weight;
  final bool approve;
  final DateTime timestamp;
  final String signature;

  GovernanceVote({
    required this.voterId,
    required this.weight,
    required this.approve,
    required this.timestamp,
    required this.signature,
  });

  Map<String, dynamic> toJson() => {
    'voterId': voterId,
    'weight': weight,
    'approve': approve,
    'timestamp': timestamp.toIso8601String(),
    'signature': signature,
  };

  factory GovernanceVote.fromJson(Map<String, dynamic> json) {
    return GovernanceVote(
      voterId: json['voterId'] as String,
      weight: (json['weight'] as num).toDouble(),
      approve: json['approve'] as bool,
      timestamp: DateTime.parse(json['timestamp'] as String),
      signature: json['signature'] as String,
    );
  }
}

/// A governance proposal
class Proposal {
  final String id;
  final ProposalType type;
  final String title;
  final String description;
  final Map<String, dynamic> payload;
  final String proposerId;
  final DateTime created;
  final DateTime deadline;
  final List<GovernanceVote> votes;
  ProposalStatus status;
  final String signature;

  Proposal({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.payload,
    required this.proposerId,
    required this.created,
    required this.deadline,
    this.votes = const [],
    this.status = ProposalStatus.draft,
    required this.signature,
  });

  /// Calculate total approval weight
  double get approvalWeight =>
      votes.where((v) => v.approve).fold(0.0, (sum, v) => sum + v.weight);

  /// Calculate total rejection weight
  double get rejectionWeight =>
      votes.where((v) => !v.approve).fold(0.0, (sum, v) => sum + v.weight);

  /// Total weight that voted
  double get totalVoteWeight => approvalWeight + rejectionWeight;

  /// Approval percentage
  double get approvalPercentage =>
      totalVoteWeight > 0 ? approvalWeight / totalVoteWeight : 0;

  /// Check if quorum is met
  bool hasQuorum(double totalEligibleWeight) {
    final quorum = GovernanceConstants.quorumThresholds[type] ?? 0.25;
    return totalVoteWeight / totalEligibleWeight >= quorum;
  }

  /// Check if proposal passes
  bool passes() {
    final threshold = GovernanceConstants.passThresholds[type] ?? 0.50;
    return approvalPercentage >= threshold;
  }

  /// Check if deadline has passed
  bool get isExpired => DateTime.now().isAfter(deadline);

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'description': description,
    'payload': payload,
    'proposerId': proposerId,
    'created': created.toIso8601String(),
    'deadline': deadline.toIso8601String(),
    'votes': votes.map((v) => v.toJson()).toList(),
    'status': status.name,
    'signature': signature,
  };

  factory Proposal.fromJson(Map<String, dynamic> json) {
    return Proposal(
      id: json['id'] as String,
      type: ProposalType.values.firstWhere((t) => t.name == json['type']),
      title: json['title'] as String,
      description: json['description'] as String,
      payload: json['payload'] as Map<String, dynamic>,
      proposerId: json['proposerId'] as String,
      created: DateTime.parse(json['created'] as String),
      deadline: DateTime.parse(json['deadline'] as String),
      votes:
          (json['votes'] as List?)
              ?.map((v) => GovernanceVote.fromJson(v as Map<String, dynamic>))
              .toList() ??
          [],
      status: ProposalStatus.values.firstWhere((s) => s.name == json['status']),
      signature: json['signature'] as String,
    );
  }
}

/// Governance service for The Parliament
class GovernanceService {
  final IdentityService _identityService;
  final LedgerService _ledgerService;
  final List<Proposal> _proposals = [];
  final _uuid = const Uuid();
  DateTime? _lastProposalTime;

  GovernanceService(this._identityService, this._ledgerService);

  /// Get all proposals
  List<Proposal> get proposals => List.unmodifiable(_proposals);

  /// Get active proposals
  List<Proposal> get activeProposals =>
      _proposals.where((p) => p.status == ProposalStatus.active).toList();

  /// Check if user can vote
  Future<bool> canVote() async {
    final identity = await _identityService.getIdentity();
    if (identity == null) return false;

    final reputation = _ledgerService.totalReputation;
    if (reputation < GovernanceConstants.minReputationToVote) return false;

    // Check account age
    final daysSinceCreation = DateTime.now()
        .difference(identity.createdAt)
        .inDays;
    if (daysSinceCreation < GovernanceConstants.minAccountAgeDays) return false;

    return true;
  }

  /// Check if user can create proposals
  Future<bool> canCreateProposal() async {
    if (!await canVote()) return false;

    // Check rate limit
    if (_lastProposalTime != null) {
      final daysSinceLast = DateTime.now()
          .difference(_lastProposalTime!)
          .inDays;
      if (daysSinceLast < GovernanceConstants.proposalRateLimitDays) {
        return false;
      }
    }

    return true;
  }

  /// Create a new proposal
  Future<Proposal?> createProposal({
    required ProposalType type,
    required String title,
    required String description,
    required Map<String, dynamic> payload,
  }) async {
    if (!await canCreateProposal()) return null;

    final identity = await _identityService.getIdentity();
    if (identity == null) return null;

    final id = _uuid.v4();
    final created = DateTime.now();
    final votingDays = GovernanceConstants.votingPeriods[type] ?? 7;
    final deadline = created.add(Duration(days: votingDays));

    // Sign the proposal
    final data =
        '$id|$title|${jsonEncode(payload)}|${created.toIso8601String()}';
    final signature = await _identityService.sign(
      Uint8List.fromList(utf8.encode(data)),
    );

    final proposal = Proposal(
      id: id,
      type: type,
      title: title,
      description: description,
      payload: payload,
      proposerId: identity.publicKeyBase58,
      created: created,
      deadline: deadline,
      status: ProposalStatus.active,
      signature: base64Encode(signature),
    );

    _proposals.add(proposal);
    _lastProposalTime = created;

    return proposal;
  }

  /// Cast a vote on a proposal
  Future<bool> vote({required String proposalId, required bool approve}) async {
    if (!await canVote()) return false;

    final proposal = _proposals.firstWhere(
      (p) => p.id == proposalId,
      orElse: () => throw StateError('Proposal not found'),
    );

    if (proposal.status != ProposalStatus.active) return false;
    if (proposal.isExpired) return false;

    final identity = await _identityService.getIdentity();
    if (identity == null) return false;

    // Check if already voted
    if (proposal.votes.any((v) => v.voterId == identity.publicKeyBase58)) {
      return false;
    }

    // Calculate vote weight based on reputation
    final weight = _ledgerService.totalReputation;

    // Sign the vote
    final data =
        '$proposalId|$approve|$weight|${DateTime.now().toIso8601String()}';
    final signature = await _identityService.sign(
      Uint8List.fromList(utf8.encode(data)),
    );

    final vote = GovernanceVote(
      voterId: identity.publicKeyBase58,
      weight: weight,
      approve: approve,
      timestamp: DateTime.now(),
      signature: base64Encode(signature),
    );

    proposal.votes.add(vote);

    // Check if proposal should be resolved
    _checkAndResolveProposal(proposal);

    return true;
  }

  /// Check and resolve proposal status
  void _checkAndResolveProposal(Proposal proposal) {
    // For now use a simplified total weight calculation
    final totalEligibleWeight = 1000.0; // Would be sum of all eligible voters

    if (proposal.isExpired) {
      if (proposal.hasQuorum(totalEligibleWeight) && proposal.passes()) {
        proposal.status = ProposalStatus.approved;
        _executeProposal(proposal);
      } else {
        proposal.status = ProposalStatus.rejected;
      }
    }
  }

  /// Execute an approved proposal
  void _executeProposal(Proposal proposal) {
    // Log execution
    proposal.status = ProposalStatus.executed;

    // Proposal-type specific execution would go here
    switch (proposal.type) {
      case ProposalType.gatewayAddition:
        // Would add gateway to IPFS service
        break;
      case ProposalType.priorityChange:
        // Would update endangered thresholds
        break;
      default:
        break;
    }
  }
}
