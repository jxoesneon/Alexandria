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

  /// (round-3 red finding) Whether [weight] was derived from local
  /// ledger state at cast time ([GovernanceService.vote]). A vote
  /// deserialized from the wire carries `weightAttested = false` — its
  /// declared weight and signature are self-asserted and never
  /// load-bearing in resolution tallies.
  ///
  /// (round-4 red finding) Unforgeable by construction: the public
  /// constructor IGNORES any `weightAttested` argument — only the
  /// private [GovernanceVote._attested] constructor, reachable solely
  /// from [GovernanceService.vote] in this library, mints attestation.
  final bool weightAttested;

  GovernanceVote({
    required this.voterId,
    required this.weight,
    required this.approve,
    required this.timestamp,
    required this.signature,
    // Ignored — see field doc. Retained for call-site compatibility.
    bool weightAttested = false,
  }) : weightAttested = false;

  /// Private attested-vote constructor — only [GovernanceService.vote]
  /// may mint attestation, after deriving weight from the ledger
  /// (round-4 red finding, same fix as ConsensusService's attested
  /// vote constructor).
  GovernanceVote._attested({
    required this.voterId,
    required this.weight,
    required this.approve,
    required this.timestamp,
    required this.signature,
  }) : weightAttested = true;

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

  /// (campaign-2 hardening) Was a public mutable field — the same
  /// finding class as `ChangeRequest.status` (round-5): any holder of
  /// a returned reference could write `status = approved`/`executed`
  /// and the [GovernanceService.activeProposals] filter and
  /// [GovernanceService.vote]
  /// gate would honour the forged lifecycle state. Now private; the
  /// only transition paths are [activate] and [resolve], which move
  /// draft → active → {approved, rejected, expired} and
  /// approved → executed — never backward and never terminal →
  /// anything.
  ProposalStatus _status;
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
    List<GovernanceVote>? votes,
    ProposalStatus status = ProposalStatus.draft,
    required this.signature,
  })  : votes = votes != null ? List.from(votes) : [],
        _status = status;

  /// Current lifecycle state (read-only to callers).
  ProposalStatus get status => _status;

  /// draft → active. A no-op from any other state.
  void activate() {
    if (_status == ProposalStatus.draft) _status = ProposalStatus.active;
  }

  /// Lifecycle transition: active may resolve to approved, rejected or
  /// expired; approved may resolve to executed. Every other move —
  /// terminal → anything, draft → terminal, backward transitions — is
  /// a no-op rather than a rewrite of a decided outcome.
  void resolve(ProposalStatus next) {
    final allowed = (_status == ProposalStatus.active &&
            (next == ProposalStatus.approved ||
                next == ProposalStatus.rejected ||
                next == ProposalStatus.expired)) ||
        (_status == ProposalStatus.approved && next == ProposalStatus.executed);
    if (allowed) _status = next;
  }

  /// Calculate total approval weight (raw view of declared weights —
  /// display only; resolution uses the attested getters below).
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

  /// (round-3 red finding) attested tallies — only votes whose weight
  /// was ledger-derived at cast time count toward resolution. A
  /// serialized vote can declare any weight it likes; it tallies zero.
  /// (round-4 red finding) deduplicated by [GovernanceVote.voterId] —
  /// [votes] is a publicly mutable list, so a copied attested ballot
  /// must never double-count.
  double get attestedApprovalWeight => _attestedTally(approve: true);

  double get attestedRejectionWeight => _attestedTally(approve: false);

  double _attestedTally({required bool approve}) {
    final seenVoters = <String>{};
    var sum = 0.0;
    for (final v in votes) {
      if (v.approve != approve || !v.weightAttested) continue;
      if (seenVoters.add(v.voterId)) sum += v.weight;
    }
    return sum;
  }

  double get attestedTotalVoteWeight =>
      attestedApprovalWeight + attestedRejectionWeight;

  /// Check if quorum is met (raw/declared view — display only).
  bool hasQuorum(double totalEligibleWeight) {
    final quorum = GovernanceConstants.quorumThresholds[type] ?? 0.25;
    return totalVoteWeight / totalEligibleWeight >= quorum;
  }

  /// Quorum check over ATTESTED weight only — used by resolution.
  bool hasAttestedQuorum(double totalEligibleWeight) {
    if (totalEligibleWeight <= 0) return false;
    final quorum = GovernanceConstants.quorumThresholds[type] ?? 0.25;
    return attestedTotalVoteWeight / totalEligibleWeight >= quorum;
  }

  /// Check if proposal passes (raw/declared view — display only).
  bool passes() {
    final threshold = GovernanceConstants.passThresholds[type] ?? 0.50;
    return approvalPercentage >= threshold;
  }

  /// Pass check over ATTESTED weight only — used by resolution.
  bool attestedPasses() {
    final threshold = GovernanceConstants.passThresholds[type] ?? 0.50;
    final total = attestedTotalVoteWeight;
    return total > 0 && attestedApprovalWeight / total >= threshold;
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
      votes: (json['votes'] as List?)
              ?.map((v) => GovernanceVote.fromJson(v as Map<String, dynamic>))
              .toList() ??
          [],
      // (round-4 red finding) wire status is unverifiable — the same
      // strip-unverifiable-fields rule as [GovernanceService.addProposal]
      // and ChangeRequest.fromJson: a deserialized proposal re-enters
      // as a draft rather than importing a claimed 'active'/'approved'.
      status: ProposalStatus.draft,
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

  /// Add proposal (from mesh or local).
  ///
  /// TRUST MODEL (strip-unverifiable, same pattern as
  /// `MoltbookService.ingestBountyAnnouncement`): a caller-supplied
  /// proposal's votes and status are CLAIMS, not facts. Until
  /// proposal/vote signature verification lands in the transport layer:
  ///   * `votes` are always stripped — each GovernanceVote carries its
  ///     own signature and there is no vote-verification machinery yet,
  ///     so an announcer could fabricate tallies. Votes may only accrue
  ///     through [vote], which checks eligibility and signs locally.
  ///   * `status` is reset to [ProposalStatus.draft] — a remote
  ///     'active'/'approved' claim is unverifiable, so ingested
  ///     proposals enter the pipeline as drafts until locally activated.
  ///
  /// [signatureVerified] is the seam for future verification: the
  /// transport may set it ONLY after verifying [Proposal.signature]
  /// against the canonical signed payload
  /// (`id|title|payload|created`) out-of-band — it must never be
  /// populated from wire data. When set, the proposer's claimed status
  /// is preserved (votes are still stripped: they are separately
  /// signed and separately unverified).
  ///
  /// Proposals are deduplicated by id: mesh redelivery and echoes of
  /// locally created proposals are ignored.
  void addProposal(Proposal proposal, {bool signatureVerified = false}) {
    if (_proposals.any((p) => p.id == proposal.id)) return;

    // Store a normalized copy so the caller's object can never smuggle
    // unverifiable votes/status into the pipeline.
    final normalized = Proposal(
      id: proposal.id,
      type: proposal.type,
      title: proposal.title,
      description: proposal.description,
      payload: proposal.payload,
      proposerId: proposal.proposerId,
      created: proposal.created,
      deadline: proposal.deadline,
      status: signatureVerified ? proposal.status : ProposalStatus.draft,
      signature: proposal.signature,
    );
    _proposals.add(normalized);
  }

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
    final daysSinceCreation =
        DateTime.now().difference(identity.createdAt).inDays;
    if (daysSinceCreation < GovernanceConstants.minAccountAgeDays) return false;

    return true;
  }

  /// Check if user can create proposals
  Future<bool> canCreateProposal() async {
    if (!await canVote()) return false;

    // Check rate limit
    if (_lastProposalTime != null) {
      final daysSinceLast =
          DateTime.now().difference(_lastProposalTime!).inDays;
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

    // Calculate vote weight from ledger-attested reputation — never
    // from a caller-supplied figure (round-3 red finding).
    final weight = _ledgerService.totalReputation;

    // Sign the vote
    final data =
        '$proposalId|$approve|$weight|${DateTime.now().toIso8601String()}';
    final signature = await _identityService.sign(
      Uint8List.fromList(utf8.encode(data)),
    );

    final vote = GovernanceVote._attested(
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

  /// Check and resolve proposal status.
  ///
  /// (round-3 red finding) the hardcoded `totalEligibleWeight = 1000.0`
  /// is gone: resolution now runs over ATTESTED weight only, with the
  /// eligible base set to the locally-attestable electorate — this
  /// node's own ledger reputation, which must cover at least the
  /// attested votes cast. Residual: the true remote electorate size is
  /// unknowable until cross-signed vote attestations land in the
  /// transport layer; unverifiable remote votes are already stripped at
  /// ingest by [addProposal], so no remote claim can move a tally here.
  void _checkAndResolveProposal(Proposal proposal) {
    if (!proposal.isExpired) return;

    final localReputation = _ledgerService.totalReputation;
    final totalEligibleWeight =
        localReputation > proposal.attestedTotalVoteWeight
            ? localReputation
            : proposal.attestedTotalVoteWeight;

    if (totalEligibleWeight > 0 &&
        proposal.hasAttestedQuorum(totalEligibleWeight) &&
        proposal.attestedPasses()) {
      proposal.resolve(ProposalStatus.approved);
      _executeProposal(proposal);
    } else {
      proposal.resolve(ProposalStatus.rejected);
    }
  }

  /// Execute an approved proposal
  void _executeProposal(Proposal proposal) {
    // Log execution
    proposal.resolve(ProposalStatus.executed);

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
