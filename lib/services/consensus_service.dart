import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../services/identity_service.dart';
import '../services/ledger_service.dart';

/// Provider for the ConsensusService
final consensusServiceProvider = Provider((ref) {
  final identityService = ref.watch(identityServiceProvider);
  final ledgerService = ref.watch(ledgerServiceProvider);
  return ConsensusService(identityService, ledgerService);
});

/// Constants for consensus (Spec §5.2, §5.3)
class ConsensusConstants {
  static const double defaultThreshold = 10.0;
  static const double aiWeight = 5.0;
  static const int humanThreshold = 2;
}

/// Status of a change request
enum ChangeRequestStatus { pending, approved, rejected, vetoed }

/// A single vote on a change request
class Vote {
  final Uint8List voterKey;
  final double weight;
  final bool approve;
  final Uint8List signature;
  final DateTime timestamp;
  final bool isHuman;

  Vote({
    required this.voterKey,
    required this.weight,
    required this.approve,
    required this.signature,
    required this.timestamp,
    this.isHuman = true,
  });

  Map<String, dynamic> toJson() => {
        'voterKey': base64Encode(voterKey),
        'weight': weight,
        'approve': approve,
        'signature': base64Encode(signature),
        'timestamp': timestamp.toIso8601String(),
        'isHuman': isHuman,
      };

  factory Vote.fromJson(Map<String, dynamic> json) {
    return Vote(
      voterKey: base64Decode(json['voterKey'] as String),
      weight: (json['weight'] as num).toDouble(),
      approve: json['approve'] as bool,
      signature: base64Decode(json['signature'] as String),
      timestamp: DateTime.parse(json['timestamp'] as String),
      isHuman: json['isHuman'] as bool? ?? true,
    );
  }
}

/// A change request for metadata
class ChangeRequest {
  final String id;
  final String targetCid;
  final String field;
  final dynamic currentValue;
  final dynamic proposedValue;
  final Uint8List proposerKey;
  final Uint8List proposerSignature;
  final DateTime timestamp;
  final List<Vote> votes;
  ChangeRequestStatus status;
  final Uint8List? uploaderKey; // Original uploader for veto/fast-track
  final bool isAiProposal;

  ChangeRequest({
    required this.id,
    required this.targetCid,
    required this.field,
    required this.currentValue,
    required this.proposedValue,
    required this.proposerKey,
    required this.proposerSignature,
    required this.timestamp,
    this.votes = const [],
    this.status = ChangeRequestStatus.pending,
    this.uploaderKey,
    this.isAiProposal = false,
  });

  /// Calculate total approval weight
  double get approvalWeight =>
      votes.where((v) => v.approve).fold(0.0, (sum, v) => sum + v.weight);

  /// Calculate total rejection weight
  double get rejectionWeight =>
      votes.where((v) => !v.approve).fold(0.0, (sum, v) => sum + v.weight);

  /// Count human approvals (for AI proposals)
  int get humanApprovalCount =>
      votes.where((v) => v.approve && v.isHuman).length;

  /// Check if approved based on consensus rules
  bool get isApproved {
    if (status != ChangeRequestStatus.pending) {
      return status == ChangeRequestStatus.approved;
    }

    // Standard approval rules
    if (approvalWeight >= ConsensusConstants.defaultThreshold &&
        approvalWeight > rejectionWeight) {
      // For AI proposals, also require human threshold
      if (isAiProposal) {
        return humanApprovalCount >= ConsensusConstants.humanThreshold;
      }
      return true;
    }
    return false;
  }

  /// Check if rejected based on consensus rules
  bool get isRejected {
    return rejectionWeight >= ConsensusConstants.defaultThreshold &&
        rejectionWeight > approvalWeight;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'targetCid': targetCid,
        'field': field,
        'currentValue': currentValue,
        'proposedValue': proposedValue,
        'proposerKey': base64Encode(proposerKey),
        'proposerSignature': base64Encode(proposerSignature),
        'timestamp': timestamp.toIso8601String(),
        'votes': votes.map((v) => v.toJson()).toList(),
        'status': status.name,
        'uploaderKey': uploaderKey != null ? base64Encode(uploaderKey!) : null,
        'isAiProposal': isAiProposal,
      };

  factory ChangeRequest.fromJson(Map<String, dynamic> json) {
    return ChangeRequest(
      id: json['id'] as String,
      targetCid: json['targetCid'] as String,
      field: json['field'] as String,
      currentValue: json['currentValue'],
      proposedValue: json['proposedValue'],
      proposerKey: base64Decode(json['proposerKey'] as String),
      proposerSignature: base64Decode(json['proposerSignature'] as String),
      timestamp: DateTime.parse(json['timestamp'] as String),
      votes: (json['votes'] as List?)
              ?.map((v) => Vote.fromJson(v as Map<String, dynamic>))
              .toList() ??
          [],
      status: ChangeRequestStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => ChangeRequestStatus.pending,
      ),
      uploaderKey: json['uploaderKey'] != null
          ? base64Decode(json['uploaderKey'] as String)
          : null,
      isAiProposal: json['isAiProposal'] as bool? ?? false,
    );
  }
}

/// Audit trail entry for change tracking
class AuditEntry {
  final String id;
  final String changeRequestId;
  final String eventType; // proposed, voted, approved, rejected, vetoed
  final Uint8List actorKey;
  final DateTime timestamp;
  final dynamic previousValue;
  final dynamic newValue;
  final Uint8List signature;

  AuditEntry({
    required this.id,
    required this.changeRequestId,
    required this.eventType,
    required this.actorKey,
    required this.timestamp,
    this.previousValue,
    this.newValue,
    required this.signature,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'changeRequestId': changeRequestId,
        'eventType': eventType,
        'actorKey': base64Encode(actorKey),
        'timestamp': timestamp.toIso8601String(),
        'previousValue': previousValue,
        'newValue': newValue,
        'signature': base64Encode(signature),
      };

  factory AuditEntry.fromJson(Map<String, dynamic> json) {
    return AuditEntry(
      id: json['id'] as String,
      changeRequestId: json['changeRequestId'] as String,
      eventType: json['eventType'] as String,
      actorKey: base64Decode(json['actorKey'] as String),
      timestamp: DateTime.parse(json['timestamp'] as String),
      previousValue: json['previousValue'],
      newValue: json['newValue'],
      signature: base64Decode(json['signature'] as String),
    );
  }
}

/// Vote weight calculator (Spec §14.2)
class VoteWeightCalculator {
  /// Calculate vote weight: W = R(voter) × T(voter) × A(voter)
  /// R = log2(1 + reputation_score)
  /// T = min(1.0, days_active / 365)
  /// A = 1.0 if human, 0.5 if AI (unless specifically AI proposal)
  static double calculateWeight({
    required double reputationScore,
    required int daysActive,
    required bool isHuman,
  }) {
    // Logarithmic scaling for reputation
    final r = _log2(1 + reputationScore);

    // Time factor (caps at 1 year)
    final t = (daysActive / 365.0).clamp(0.0, 1.0);

    // Human/AI factor
    final a = isHuman ? 1.0 : 0.5;

    return r * t * a;
  }

  static double _log2(double x) {
    // log2(x) = ln(x) / ln(2)
    return _ln(x) / _ln(2);
  }

  static double _ln(double x) {
    // Taylor series approximation for natural log
    if (x <= 0) return 0;
    if (x == 1) return 0;

    // For x > 2, reduce to ln(x) = ln(x/2) + ln(2)
    var result = 0.0;
    while (x > 2) {
      x /= 2;
      result += 0.6931471805599453; // ln(2)
    }

    // For 1 < x <= 2, use series expansion
    final y = (x - 1) / (x + 1);
    var term = y;
    for (var i = 1; i <= 20; i += 2) {
      result += 2 * term / i;
      term *= y * y;
    }

    return result;
  }
}

/// Service for managing metadata consensus
class ConsensusService {
  final IdentityService _identityService;
  final LedgerService _ledgerService;
  final List<ChangeRequest> _changeRequests = [];
  final List<AuditEntry> _auditLog = [];
  final _uuid = const Uuid();

  ConsensusService(this._identityService, this._ledgerService);

  /// Get all pending change requests
  List<ChangeRequest> get pendingRequests => _changeRequests
      .where((r) => r.status == ChangeRequestStatus.pending)
      .toList();

  /// Get audit log for a CID
  List<AuditEntry> getAuditLog(String targetCid) {
    return _auditLog
        .where(
          (e) => _changeRequests.any(
            (r) => r.id == e.changeRequestId && r.targetCid == targetCid,
          ),
        )
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  /// Create a new change request
  Future<ChangeRequest> proposeChange({
    required String targetCid,
    required String field,
    required dynamic currentValue,
    required dynamic proposedValue,
    Uint8List? uploaderKey,
    bool isAiProposal = false,
  }) async {
    final identity = await _identityService.getIdentity();
    if (identity == null) throw StateError('No identity found');

    final id = _uuid.v4();
    final timestamp = DateTime.now();

    // Create data to sign
    final data =
        '$id|$targetCid|$field|$currentValue|$proposedValue|${timestamp.toIso8601String()}';
    final signature = await _identityService.sign(
      Uint8List.fromList(utf8.encode(data)),
    );

    final request = ChangeRequest(
      id: id,
      targetCid: targetCid,
      field: field,
      currentValue: currentValue,
      proposedValue: proposedValue,
      proposerKey: identity.publicKey,
      proposerSignature: signature,
      timestamp: timestamp,
      uploaderKey: uploaderKey,
      isAiProposal: isAiProposal,
    );

    _changeRequests.add(request);

    // Record audit entry
    await _recordAuditEntry(
      changeRequestId: id,
      eventType: 'proposed',
      actorKey: identity.publicKey,
      previousValue: currentValue,
      newValue: proposedValue,
    );

    // Record in ledger
    await _ledgerService.recordAction(
      action: LedgerActionType.proposeMetadataFix,
      contentCid: targetCid,
    );

    return request;
  }

  /// Cast a vote on a change request
  Future<Vote?> castVote({
    required String requestId,
    required bool approve,
    required double reputation,
    required int daysActive,
    bool isHuman = true,
  }) async {
    final request = _changeRequests.firstWhere(
      (r) => r.id == requestId,
      orElse: () => throw StateError('Change request not found'),
    );

    if (request.status != ChangeRequestStatus.pending) {
      return null; // Can't vote on resolved requests
    }

    final identity = await _identityService.getIdentity();
    if (identity == null) throw StateError('No identity found');

    // Check if already voted
    if (request.votes.any((v) => _bytesEqual(v.voterKey, identity.publicKey))) {
      return null; // Already voted
    }

    // Calculate weight
    final weight = VoteWeightCalculator.calculateWeight(
      reputationScore: reputation,
      daysActive: daysActive,
      isHuman: isHuman,
    );

    // Create vote data to sign
    final data =
        '$requestId|$approve|$weight|${DateTime.now().toIso8601String()}';
    final signature = await _identityService.sign(
      Uint8List.fromList(utf8.encode(data)),
    );

    final vote = Vote(
      voterKey: identity.publicKey,
      weight: weight,
      approve: approve,
      signature: signature,
      timestamp: DateTime.now(),
      isHuman: isHuman,
    );

    request.votes.add(vote);

    // Record audit entry
    await _recordAuditEntry(
      changeRequestId: requestId,
      eventType: 'voted',
      actorKey: identity.publicKey,
      newValue: {'approve': approve, 'weight': weight},
    );

    // Check if request should be resolved
    _checkAndResolve(request);

    return vote;
  }

  /// Uploader veto (immediately rejects)
  Future<bool> vetoChange(String requestId) async {
    final request = _changeRequests.firstWhere(
      (r) => r.id == requestId,
      orElse: () => throw StateError('Change request not found'),
    );

    if (request.status != ChangeRequestStatus.pending) return false;

    final identity = await _identityService.getIdentity();
    if (identity == null) return false;

    // Verify caller is the uploader
    if (request.uploaderKey == null ||
        !_bytesEqual(identity.publicKey, request.uploaderKey!)) {
      return false;
    }

    request.status = ChangeRequestStatus.vetoed;

    await _recordAuditEntry(
      changeRequestId: requestId,
      eventType: 'vetoed',
      actorKey: identity.publicKey,
    );

    return true;
  }

  /// Uploader fast-track (immediately approves if any support)
  Future<bool> fastTrackChange(String requestId) async {
    final request = _changeRequests.firstWhere(
      (r) => r.id == requestId,
      orElse: () => throw StateError('Change request not found'),
    );

    if (request.status != ChangeRequestStatus.pending) return false;
    if (request.approvalWeight <= 0) return false; // Need at least one approval

    final identity = await _identityService.getIdentity();
    if (identity == null) return false;

    // Verify caller is the uploader
    if (request.uploaderKey == null ||
        !_bytesEqual(identity.publicKey, request.uploaderKey!)) {
      return false;
    }

    request.status = ChangeRequestStatus.approved;

    await _recordAuditEntry(
      changeRequestId: requestId,
      eventType: 'approved',
      actorKey: identity.publicKey,
      newValue: 'fast-tracked',
    );

    // Record successful merge in ledger
    await _ledgerService.recordAction(
      action: LedgerActionType.mergeAccepted,
      contentCid: request.targetCid,
    );

    return true;
  }

  /// Check if request should be resolved and update status
  void _checkAndResolve(ChangeRequest request) {
    if (request.isApproved) {
      request.status = ChangeRequestStatus.approved;
    } else if (request.isRejected) {
      request.status = ChangeRequestStatus.rejected;
    }
  }

  /// Record an audit entry
  Future<void> _recordAuditEntry({
    required String changeRequestId,
    required String eventType,
    required Uint8List actorKey,
    dynamic previousValue,
    dynamic newValue,
  }) async {
    final id = _uuid.v4();
    final timestamp = DateTime.now();

    final data =
        '$id|$changeRequestId|$eventType|${timestamp.toIso8601String()}';
    final signature = await _identityService.sign(
      Uint8List.fromList(utf8.encode(data)),
    );

    final entry = AuditEntry(
      id: id,
      changeRequestId: changeRequestId,
      eventType: eventType,
      actorKey: actorKey,
      timestamp: timestamp,
      previousValue: previousValue,
      newValue: newValue,
      signature: signature,
    );

    _auditLog.add(entry);
  }

  /// Compare two byte arrays
  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
