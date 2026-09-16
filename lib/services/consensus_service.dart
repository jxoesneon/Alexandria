import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../services/biometric_service.dart';
import '../services/identity_service.dart';
import '../services/ledger_service.dart';

/// Provider for the ConsensusService
final consensusServiceProvider = Provider((ref) {
  final identityService = ref.watch(identityServiceProvider);
  final ledgerService = ref.watch(ledgerServiceProvider);
  // Human attestation is bound to the biometric service's
  // last-real-authentication clock — see [ConsensusService.castVote].
  final biometricService = ref.watch(biometricServiceProvider);
  return ConsensusService(
    identityService,
    ledgerService,
    humanAttestationClock: () => biometricService.lastAuthenticatedAt,
    // The strong human-attestation path: per-vote HMAC tokens minted by
    // BiometricService.attestVoteIntent behind a real device-credential
    // prompt, bound to voterKey‖changeId‖choice and single-use.
    voteAttestationVerifier: biometricService.consumeVoteAttestation,
  );
});

/// Returns the timestamp of the last successful device-credential
/// (biometric/PIN) authentication, or null when none exists. Wired to
/// [BiometricService.lastAuthenticatedAt] in production; injectable so
/// tests and headless embedders can supply their own evidence source.
///
/// TRUST MODEL: the clock must be fed ONLY by genuine authentication
/// events — never by a caller's claim and never by a fail-open bypass.
/// [BiometricService.authenticate] returns true without prompting when
/// biometrics are unavailable or secure mode is off; those paths do
/// NOT update the clock, so "the user was allowed through" is never
/// mistaken for "a human was verified".
typedef HumanAttestationClock = DateTime? Function();

/// Verifies (and consumes) a per-vote human attestation token — the
/// STRONG human-binding path that supersedes the temporal
/// [HumanAttestationClock] window (campaign-2 hardening).
///
/// A token is a short-lived HMAC minted by
/// [BiometricService.attestVoteIntent] only after a genuine
/// device-credential prompt, committing to the exact ballot fields
/// (voterKey ‖ changeId ‖ choice ‖ issuedAt ‖ nonce). The verifier
/// returns true only when the token's MAC covers THESE fields, it is
/// inside its TTL, and it has never been consumed — a token minted
/// for another change, another choice, or another voter attests
/// nothing, and a replayed token refuses.
///
/// TRUST MODEL: same as [HumanAttestationClock] — the source must be
/// fed only by genuine authentication events, and every failure mode
/// (throw, malformed, stale) attests nothing. Wired to
/// [BiometricService.consumeVoteAttestation] in production; injectable
/// so tests/headless embedders can supply their own evidence source.
typedef VoteAttestationVerifier = Future<bool> Function(
  String token, {
  required Uint8List voterKey,
  required String changeId,
  required bool approve,
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

  /// Whether this ballot is an ATTESTED human vote.
  ///
  /// (WORKING_ON residual, closed this round) `isHuman` used to be a
  /// caller-declared flag even on `weightAttested` ballots — the tally
  /// trusted the signature's weight but took humanity on faith. Now,
  /// on a service-minted attested ballot, `isHuman` is DERIVED, not
  /// declared: [ConsensusService.castVote] sets it only when a
  /// [HumanAttestationClock] reports a real device-credential
  /// authentication within the attestation window. A caller asking for
  /// `isHuman: true` without biometric evidence produces a ballot with
  /// `isHuman == false` — fail-closed.
  ///
  /// Wire-deserialized votes still carry whatever flag their author
  /// claimed, but they are `weightAttested == false` and therefore
  /// already excluded from [ChangeRequest.humanApprovalCount].
  final bool isHuman;

  /// (campaign-2 hardening) The consumed per-vote attestation token
  /// this human ballot was minted against, when the STRONG binding
  /// path was used ([ConsensusService.castVote] with
  /// `humanAttestationToken`). Non-null only on attested ballots whose
  /// `isHuman` was derived from a field-bound token rather than the
  /// recency window — a human ballot carrying this pin is bound to
  /// THAT vote, not just to a recent unlock. The token is single-use
  /// and already consumed, so persisting it here leaks no replayable
  /// credential.
  final String? humanAttestation;

  /// (round-3 red finding) Whether [weight] was derived locally from
  /// ledger state at cast time. Votes deserialized from the wire carry
  /// `weightAttested = false` — a serialized `weight` is a self-declared
  /// claim and is NEVER load-bearing in [ChangeRequest.approvalWeight] /
  /// [ChangeRequest.rejectionWeight] tallies.
  ///
  /// (round-4 red finding) The marker is UNFORGEABLE BY CONSTRUCTION:
  /// the public constructor accepts — and IGNORES — a `weightAttested`
  /// argument, always producing an unattested vote. Only the private
  /// [Vote._attested] constructor, reachable solely from
  /// [ConsensusService.castVote] inside this library, can mint an
  /// attested ballot. A caller pushing `Vote(weightAttested: true)`
  /// onto [ChangeRequest.votes] fabricates nothing.
  final bool weightAttested;

  Vote({
    required this.voterKey,
    required this.weight,
    required this.approve,
    required this.signature,
    required this.timestamp,
    this.isHuman = true,
    this.humanAttestation,
    // Ignored — see field doc. Retained only for call-site compatibility.
    bool weightAttested = false,
  }) : weightAttested = false;

  /// The only attested-vote constructor — private to this library so
  /// attestation can be minted exclusively by [ConsensusService.castVote]
  /// after deriving the weight from ledger state (round-4 red finding).
  Vote._attested({
    required this.voterKey,
    required this.weight,
    required this.approve,
    required this.signature,
    required this.timestamp,
    this.isHuman = true,
    this.humanAttestation,
  }) : weightAttested = true;

  Map<String, dynamic> toJson() => {
        'voterKey': base64Encode(voterKey),
        'weight': weight,
        'approve': approve,
        'signature': base64Encode(signature),
        'timestamp': timestamp.toIso8601String(),
        'isHuman': isHuman,
        'humanAttestation': humanAttestation,
      };

  factory Vote.fromJson(Map<String, dynamic> json) {
    return Vote(
      voterKey: base64Decode(json['voterKey'] as String),
      weight: (json['weight'] as num).toDouble(),
      approve: json['approve'] as bool,
      signature: base64Decode(json['signature'] as String),
      timestamp: DateTime.parse(json['timestamp'] as String),
      isHuman: json['isHuman'] as bool? ?? true,
      humanAttestation: json['humanAttestation'] as String?,
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

  /// (round-5 red finding) Was a public mutable field — any holder of a
  /// returned reference could write `status = approved`/`vetoed` and
  /// [isApproved] would honour the forged terminal state. Now private;
  /// the only transition path is [resolve], which moves pending → a
  /// terminal state and never back.
  ChangeRequestStatus _status;
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
    List<Vote>? votes,
    ChangeRequestStatus status = ChangeRequestStatus.pending,
    this.uploaderKey,
    this.isAiProposal = false,
  })  : votes = votes != null ? List.from(votes) : [],
        _status = status;

  /// Current lifecycle state (read-only to callers).
  ChangeRequestStatus get status => _status;

  /// Service-internal state transition: pending → terminal, never
  /// terminal → anything and never pending → pending. A call that
  /// violates the lifecycle is a no-op rather than a rewrite of a
  /// decided outcome.
  void resolve(ChangeRequestStatus next) {
    if (_status != ChangeRequestStatus.pending ||
        next == ChangeRequestStatus.pending) {
      return;
    }
    _status = next;
  }

  /// Calculate total approval weight. (round-3 red finding) Only votes
  /// whose weight was attested at cast time count — wire-deserialized
  /// votes declare whatever weight their author wanted and are tallied
  /// as zero. (round-4 red finding) Tallies are deduplicated by
  /// [Vote.voterKey]: [votes] is a publicly mutable list, so a copied
  /// attested ballot must never double-count.
  double get approvalWeight => _tallyWeight(approve: true);

  /// Calculate total rejection weight (same attestation rule as
  /// [approvalWeight]).
  double get rejectionWeight => _tallyWeight(approve: false);

  /// Attested, voterKey-deduplicated weight for one side of the tally.
  double _tallyWeight({required bool approve}) {
    final seenKeys = <String>{};
    var sum = 0.0;
    for (final v in votes) {
      if (v.approve != approve || !v.weightAttested) continue;
      if (seenKeys.add(base64Encode(v.voterKey))) sum += v.weight;
    }
    return sum;
  }

  /// Count human approvals (for AI proposals).
  ///
  /// (round-4 red finding) The human quorum counts only ATTESTED human
  /// approvals — the same trust class as the weight tally. Previously
  /// any wire ballot could self-assert `isHuman` (weightAttested=false)
  /// and satisfy `humanThreshold` without a single ledger-derived vote;
  /// and the count is deduplicated by [Vote.voterKey] so a duplicated
  /// ballot is still one human.
  ///
  /// (WORKING_ON residual, closed this round) On top of weight
  /// attestation, `isHuman` on a counted ballot is now itself derived:
  /// [ConsensusService.castVote] sets it only when a biometric-bound
  /// [HumanAttestationClock] attests a human presence within the
  /// attestation window — a self-asserted flag can no longer satisfy
  /// the human quorum even through the real cast path.
  int get humanApprovalCount {
    final seenKeys = <String>{};
    var count = 0;
    for (final v in votes) {
      if (!v.approve || !v.isHuman || !v.weightAttested) continue;
      if (seenKeys.add(base64Encode(v.voterKey))) count++;
    }
    return count;
  }

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
      // (round-4 red finding) wire status is unverifiable — a
      // deserialized request claiming 'approved'/'vetoed' would enter
      // pre-resolved with zero votes. Always re-enter as pending,
      // mirroring GovernanceService.addProposal's
      // strip-unverifiable-fields rule. Resolution is re-derivable
      // locally via _checkAndResolve once attested votes accrue.
      status: ChangeRequestStatus.pending,
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

  /// Resolves the authenticated uploader of a target CID from trusted
  /// content metadata. Injectable for tests / future content-registry
  /// integration; the default resolves only LOCALLY-ATTESTED uploads —
  /// content this node created itself (a `createContent` ledger entry
  /// under the local identity). Anything else yields null, which makes
  /// veto/fast-track authority unprovable rather than claimable
  /// (round-3 red finding).
  final Future<Uint8List?> Function(String targetCid)? _uploaderResolver;

  /// (WORKING_ON residual, closed this round) Evidence source for
  /// human-attested ballots: returns the timestamp of the last REAL
  /// device-credential authentication on this node (wired to
  /// [BiometricService.lastAuthenticatedAt] by the provider). When
  /// null — or when the clock reports nothing recent — every ballot
  /// minted by [castVote] carries `isHuman == false` regardless of
  /// the caller's claim: unattested means not counted.
  final HumanAttestationClock? _humanAttestationClock;

  /// (campaign-2 hardening) Verifier for per-vote attestation tokens —
  /// the STRONG human-binding path in [castVote]. Wired to
  /// [BiometricService.consumeVoteAttestation] by the provider. When a
  /// caller supplies `humanAttestationToken` it is checked against the
  /// actual ballot fields and consumed; when absent, the temporal
  /// [HumanAttestationClock] window remains as the compat/fallback
  /// evidence source.
  final VoteAttestationVerifier? _voteAttestationVerifier;

  /// How long a device-credential authentication stays fresh enough to
  /// attest a human vote. The binding is temporal and deliberately
  /// narrow: a human ballot requires a biometric-authenticated vote
  /// EVENT, so an authentication older than this window does not carry
  /// forward into later votes.
  final Duration humanAttestationWindow;

  ConsensusService(
    this._identityService,
    this._ledgerService, {
    Future<Uint8List?> Function(String targetCid)? uploaderResolver,
    HumanAttestationClock? humanAttestationClock,
    VoteAttestationVerifier? voteAttestationVerifier,
    this.humanAttestationWindow = const Duration(minutes: 5),
  })  : _uploaderResolver = uploaderResolver,
        _humanAttestationClock = humanAttestationClock,
        _voteAttestationVerifier = voteAttestationVerifier;

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

  /// Create a new change request.
  ///
  /// (round-3 red finding) [uploaderKey] is retained for API
  /// compatibility but is IGNORED — uploader authority is resolved from
  /// attested content metadata (see [_resolveUploaderKey]), never from a
  /// caller claim. A proposer can no longer name themself uploader of
  /// someone else's content to self-mint veto/fast-track power.
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

    final resolvedUploaderKey = await _resolveUploaderKey(targetCid);

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
      uploaderKey: resolvedUploaderKey,
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

  /// Resolves the uploader of [targetCid] from attested metadata.
  /// Default: only content this node itself created (a `createContent`
  /// ledger entry under the local identity) has a provable uploader.
  /// Residual limitation: for remote content there is no signed
  /// uploader attestation format yet, so veto/fast-track is simply
  /// unavailable — unprovable is safer than self-minted.
  Future<Uint8List?> _resolveUploaderKey(String targetCid) async {
    final resolver = _uploaderResolver;
    if (resolver != null) return resolver(targetCid);
    final createdLocally = _ledgerService.entries.any((e) =>
        e.action == LedgerActionType.createContent &&
        e.contentCid == targetCid);
    if (!createdLocally) return null;
    final identity = await _identityService.getIdentity();
    return identity?.publicKey;
  }

  /// Cast a vote on a change request.
  ///
  /// (round-3 red finding) [reputation] and [daysActive] are retained
  /// for API compatibility but are IGNORED — a caller cannot declare
  /// its own weight. Weight is derived from the local ledger
  /// ([LedgerService.totalReputation]) and the identity's real account
  /// age, and the resulting vote is marked `weightAttested` so it — and
  /// only it — counts in the tally.
  ///
  /// (WORKING_ON residual, closed this round) [isHuman] is likewise a
  /// caller CLAIM, not a fact. The stored ballot's `isHuman` is true
  /// only when the claim is made AND the [_humanAttestationClock]
  /// reports a real device-credential authentication within
  /// [humanAttestationWindow] of the cast — a biometric-authenticated
  /// vote event, bound by recency. Without that evidence the claim
  /// fails closed: the ballot is minted `isHuman == false`, which both
  /// keeps it out of [ChangeRequest.humanApprovalCount] and prices its
  /// weight at the AI factor (an unproven human claim must not even
  /// double its own weight). A clock that throws attests nothing.
  ///
  /// (campaign-2 hardening — per-vote binding) [humanAttestationToken]
  /// is the STRONG path: a short-lived token minted by
  /// [BiometricService.attestVoteIntent] behind a real device-credential
  /// prompt, committing to exactly (voterKey, requestId, approve). When
  /// supplied it must verify — a forged, stale, replayed, or
  /// wrong-field token REFUSES THE CAST entirely (returns null): a
  /// caller presenting attestation evidence that fails must not get a
  /// silent downgrade to an AI-priced ballot, which would hide the
  /// forgery attempt inside an apparently ordinary vote. When no token
  /// is supplied, [isHuman] falls back to the temporal
  /// [_humanAttestationClock] window (compat path — one recent unlock
  /// covers every vote in the window, which is why the token path
  /// dominates when available). A verified token is pinned onto the
  /// minted ballot as [Vote.humanAttestation] and folded into the
  /// signed ballot data, so the ballot itself carries its human
  /// binding.
  Future<Vote?> castVote({
    required String requestId,
    required bool approve,
    required double reputation,
    required int daysActive,
    bool isHuman = true,
    String? humanAttestationToken,
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

    // Calculate weight from ATTESTED inputs (round-3 red finding):
    // reputation comes from the honor ledger, not the caller's claim;
    // account age comes from the identity record, not a parameter.
    //
    // Human attestation (WORKING_ON residual, closed): the caller's
    // `isHuman` claim is honoured ONLY when the attestation clock
    // reports a device-credential authentication inside the window —
    // and a clock reading in the FUTURE attests nothing either (a
    // skewed/fake source cannot pre-mint human ballots). The derived
    // flag feeds BOTH the stored ballot and the weight factor, so an
    // unattested human claim never earns the 1.0 human multiplier.
    //
    // (campaign-2 hardening) STRONG path first: a supplied token must
    // verify against THIS ballot's fields (this voter's key, this
    // request, this choice) — binding the biometric event to this
    // exact vote, not merely to a recent unlock. Verification also
    // CONSUMES the token (single-use), so it is deliberately run only
    // after the pending/identity/duplicate checks above: a rejected
    // cast must not burn an honest token. A presented-but-invalid
    // token refuses the cast outright.
    bool attestedIsHuman;
    if (isHuman && humanAttestationToken != null) {
      final verifier = _voteAttestationVerifier;
      var tokenOk = false;
      if (verifier != null) {
        try {
          tokenOk = await verifier(
            humanAttestationToken,
            voterKey: identity.publicKey,
            changeId: requestId,
            approve: approve,
          );
        } catch (_) {
          tokenOk = false; // a throwing verifier attests nothing
        }
      }
      if (!tokenOk) return null; // forged/stale/replayed token → refuse
      attestedIsHuman = true;
    } else {
      // Compat path: temporal recency window only.
      attestedIsHuman = isHuman && _hasRecentHumanAttestation();
    }
    final attestedReputation = _ledgerService.totalReputation;
    final attestedDaysActive =
        DateTime.now().difference(identity.createdAt).inDays;
    final weight = VoteWeightCalculator.calculateWeight(
      reputationScore: attestedReputation,
      daysActive: attestedDaysActive,
      isHuman: attestedIsHuman,
    );

    // Create vote data to sign. (campaign-2 hardening) the signed
    // payload folds in the attestation binding — 'att:<token>' when a
    // per-vote token verified, 'att:window' for the temporal-fallback
    // human path, 'att:none' otherwise — so the ballot signature
    // commits to WHICH kind of human evidence authorized it.
    final attBinding = attestedIsHuman
        ? (humanAttestationToken != null
            ? 'att:$humanAttestationToken'
            : 'att:window')
        : 'att:none';
    final data =
        '$requestId|$approve|$weight|${DateTime.now().toIso8601String()}|$attBinding';
    final signature = await _identityService.sign(
      Uint8List.fromList(utf8.encode(data)),
    );

    // (round-4 red finding) attestation is minted ONLY through the
    // private constructor — the weight above was derived from ledger
    // state, so this is the one place an attested ballot may exist.
    // The consumed token is pinned onto the ballot (it is single-use
    // and burned, so persisting it leaks nothing replayable).
    final vote = Vote._attested(
      voterKey: identity.publicKey,
      weight: weight,
      approve: approve,
      signature: signature,
      timestamp: DateTime.now(),
      isHuman: attestedIsHuman,
      humanAttestation:
          attestedIsHuman && humanAttestationToken != null
              ? humanAttestationToken
              : null,
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

  /// Whether the attestation clock reports a real device-credential
  /// authentication inside [humanAttestationWindow]. Every failure
  /// mode — no clock wired, clock throws, no authentication yet,
  /// stale authentication, or a timestamp in the future — returns
  /// false. Fail-closed by construction.
  bool _hasRecentHumanAttestation() {
    final clock = _humanAttestationClock;
    if (clock == null) return false;
    final DateTime lastAuth;
    try {
      final t = clock();
      if (t == null) return false;
      lastAuth = t;
    } catch (_) {
      return false;
    }
    final now = DateTime.now();
    if (lastAuth.isAfter(now)) return false;
    return now.difference(lastAuth) <= humanAttestationWindow;
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

    request.resolve(ChangeRequestStatus.vetoed);

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

    request.resolve(ChangeRequestStatus.approved);

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
      request.resolve(ChangeRequestStatus.approved);
    } else if (request.isRejected) {
      request.resolve(ChangeRequestStatus.rejected);
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
