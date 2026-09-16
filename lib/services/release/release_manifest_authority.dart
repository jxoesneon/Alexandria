import 'dart:convert';
import 'dart:typed_data';

import '../agent/beacon_models.dart';
import '../agent/escrow_attestation.dart';
import 'release_key_registry.dart';
import 'release_manifest.dart';

/// Evaluation outcome of [ReleaseManifestAuthority.ingest]. Kept as a
/// rich enum rather than a bool so callers (and tests) can distinguish
/// refusal causes - every refusal fails closed identically, but the
/// reason matters for operator diagnostics.
enum ManifestIngestResult {
  /// Accepted: threshold met, freshness proven, sequence advanced, and
  /// the floor ratcheted (or held) upward.
  accepted,

  /// Structural failure: malformed fields, non-positive values, a
  /// timestamp record that does not bind the manifest (hash or
  /// sequence mismatch).
  malformed,

  /// Fewer than `releaseThreshold` DISTINCT release-key signatures
  /// verified - includes forged signatures and signatures from keys not
  /// in the release role.
  insufficientReleaseSignatures,

  /// Fewer than `timestampThreshold` DISTINCT timestamp-key signatures
  /// verified - includes release-role signatures presented in the
  /// timestamp slot (wrong-role signatures never count).
  insufficientTimestampSignatures,

  /// The manifest's own `expires_at` has passed - the signer quorum let it
  /// lapse; it can no longer pin the floor.
  expiredManifest,

  /// The timestamp record's `expires_at` has passed - the manifest is
  /// not proven current (freeze/replay protection).
  staleTimestamp,

  /// `sequence` is not strictly greater than the last accepted one -
  /// a rollback attempt (replayed or regressed manifest).
  rollback,

  /// `min_wire_version` is below the current effective floor - the
  /// raise-only rule: a manifest can RAISE the floor, NEVER lower it
  /// (no central kill switch, RFC §3.3/§5.1).
  floorLower,
}

/// The TUF-style threshold-signed release manifest evaluator
/// (ALX-012 §5.1): the machinery that graduates the claimable wire
/// floor from a compile-time constant to quorum-asserted policy.
///
/// Semantics implemented (each is a load-bearing security property):
///
///  * **m-of-n threshold verification** - the manifest body
///    (`alexandria:release-manifest:v1:` preimage) must carry at least
///    `registry.releaseThreshold` DISTINCT release-keyId signatures that
///    verify under the registry's release keys. Forged, malformed or
///    wrong-role signatures never count.
///  * **Timestamp-role freshness** - a bundle additionally needs a
///    [ManifestTimestamp] binding `manifest_hash`/`sequence`, signed by
///    `timestampThreshold` distinct timestamp keyIds, and unexpired at
///    evaluation time. The timestamp role maps to the online quorum
///    key (TUF): replaying an old manifest cannot mint freshness.
///  * **Rollback resistance** - `sequence` must strictly exceed the
///    last accepted sequence. The cursor survives restarts when the
///    caller wires the `persistedSequence`/`onSequenceAccepted`
///    constructor arguments to durable storage (injection seam;
///    in-memory by default).
///  * **Raise-only floor** - `min_wire_version < effectiveFloor`
///    refuses outright. A valid manifest can raise the effective
///    claimable wire floor above the per-verifier compile-time
///    [baselineFloor] but NEVER lower it: a release manifest can retire
///    a wire epoch at this verifier but can never resurrect one -
///    retirement stays a per-verifier, socially coordinated act (Safety
///    B4: no central kill switch, and no reverse-direction lever that
///    would be one).
///  * **Staleness** - both `manifest.expires_at` (the signer quorum-set bound
///    keeping an abandoned manifest from pinning forever) and
///    `timestamp.expires_at` (the freshness bound) are enforced against
///    an injectable clock.
///
/// NOTE ON AUTHORITY: an accepted manifest only changes this node's
/// [effectiveFloor] - it governs nothing remotely, matching the RFC's
/// "each verifier's floor is its own" model. Consumers read
/// [effectiveFloor] instead of the compile-time constant; the
/// CreditService claim path keeps its constant until the orchestrator
/// wires this authority in (documented seam - the production trigger
/// conditions of RFC §5.1 are not yet met).
class ReleaseManifestAuthority {
  ReleaseManifestAuthority({
    required ReleaseKeyRegistry registry,
    required this.baselineFloor,
    int persistedSequence = -1,
    void Function(int sequence)? onSequenceAccepted,
    DateTime Function()? clock,
    EscrowAttestationVerifier verifyFn = EscrowAttestation.verifyEd25519,
  })  : _registry = registry,
        _acceptedSequence = persistedSequence,
        _onSequenceAccepted = onSequenceAccepted,
        _clock = clock ?? DateTime.now,
        _verifyFn = verifyFn {
    if (baselineFloor < 1) {
      throw ArgumentError('baselineFloor must be >= 1');
    }
  }

  final ReleaseKeyRegistry _registry;

  /// The per-verifier compile-time floor this authority wraps (e.g.
  /// `CreditService.minClaimableWireVersion`, injected by the caller -
  /// the authority never reaches across domain boundaries itself).
  final int baselineFloor;

  /// Highest `min_wire_version` ever accepted - the floor ratchet.
  /// Because ingest refuses `minWireVersion < effectiveFloor`, this is
  /// monotone non-decreasing for the life of the authority. Starts at 0
  /// (no manifest accepted) so [effectiveFloor] is `max(baselineFloor,
  /// _acceptedFloor)`.
  int _acceptedFloor = 0;

  /// The last accepted manifest sequence (-1 = none accepted yet).
  /// Restored via the `persistedSequence` constructor argument and
  /// pushed back out through `_onSequenceAccepted` - the rollback
  /// cursor's durability is the caller's storage seam.
  int _acceptedSequence;
  int get acceptedSequence => _acceptedSequence;

  final void Function(int sequence)? _onSequenceAccepted;
  final DateTime Function() _clock;
  final EscrowAttestationVerifier _verifyFn;

  /// The effective claimable wire floor: `max(baselineFloor, highest
  /// accepted manifest floor)`. Monotone - manifests raise, never lower.
  int get effectiveFloor =>
      _acceptedFloor > baselineFloor ? _acceptedFloor : baselineFloor;

  /// The currently governing manifest, if any was accepted.
  ReleaseManifest? get current => _current;
  ReleaseManifest? _current;

  /// Evaluates a manifest bundle: the full verification chain.
  /// On [ManifestIngestResult.accepted] the floor has ratcheted and the
  /// sequence cursor advanced (and been pushed to the persistence seam
  /// if wired). Every other result leaves all state untouched.
  Future<ManifestIngestResult> ingest(SignedManifestBundle bundle) async {
    final manifest = bundle.manifest;
    final ts = bundle.timestamp;
    final now = _clock().millisecondsSinceEpoch;

    // Structural sanity - a manifest asserting a non-positive floor or
    // carrying non-positive times can never be meaningful.
    if (manifest.minWireVersion < 1 ||
        manifest.sequence < 1 ||
        manifest.issuedAt <= 0 ||
        manifest.expiresAt <= 0 ||
        ts.timestamp <= 0 ||
        ts.expiresAt <= 0) {
      return ManifestIngestResult.malformed;
    }

    // Timestamp binding: the record must cover THIS manifest - same
    // sequence and the canonical body hash. A mismatch is a record for
    // a different manifest entirely.
    if (ts.sequence != manifest.sequence ||
        ts.manifestHash != manifest.contentHash) {
      return ManifestIngestResult.malformed;
    }

    // Staleness via the timestamp role (both bounds enforced): the
    // manifest's own expiry bounds its total lifetime; the timestamp
    // expiry bounds its proven freshness.
    if (now > manifest.expiresAt) {
      return ManifestIngestResult.expiredManifest;
    }
    if (now > ts.expiresAt) {
      return ManifestIngestResult.staleTimestamp;
    }

    // Rollback resistance: strictly-greater sequence or refuse.
    if (manifest.sequence <= _acceptedSequence) {
      return ManifestIngestResult.rollback;
    }

    // Raise-only floor (no central kill switch, and no reverse lever):
    // a manifest asserting a floor below the current effective floor -
    // whether below the compile-time baseline or below a previously
    // accepted manifest - is refused, so the floor ratchets upward only.
    if (manifest.minWireVersion < effectiveFloor) {
      return ManifestIngestResult.floorLower;
    }

    // Release-role threshold: count DISTINCT keyIds in the release
    // registry whose signatures verify over the manifest preimage.
    // A keyId absent from releaseKeys (unknown, or a timestamp-role key
    // presented in the release slot) contributes nothing.
    final releaseOk = await _countValidSignatures(
      manifest.signatures,
      ManifestSignature.roleRelease,
      _registry.releaseKeys,
      manifest.preimage,
    );
    if (releaseOk < _registry.releaseThreshold) {
      return ManifestIngestResult.insufficientReleaseSignatures;
    }

    // Timestamp-role threshold: same check against the timestamp
    // registry over the freshness preimage.
    final tsOk = await _countValidSignatures(
      ts.signatures,
      ManifestSignature.roleTimestamp,
      _registry.timestampKeys,
      ts.preimage,
    );
    if (tsOk < _registry.timestampThreshold) {
      return ManifestIngestResult.insufficientTimestampSignatures;
    }

    // Accept: ratchet the floor and advance the rollback cursor.
    _acceptedSequence = manifest.sequence;
    if (manifest.minWireVersion > _acceptedFloor) {
      _acceptedFloor = manifest.minWireVersion;
    }
    _current = manifest;
    _onSequenceAccepted?.call(manifest.sequence);
    return ManifestIngestResult.accepted;
  }

  /// Envelope ingest path - the signed-manifest transport the RFC's
  /// trigger condition (ii) names: manifests ride the same Beacon
  /// envelope channel as bounty announcements. Fail-closed chain:
  ///  * `envelope.kind` must be [ReleaseManifest.envelopeKind];
  ///  * [BeaconEnvelope.verify] must pass (signature + key-derived
  ///    agent id);
  ///  * the envelope signer must be a REGISTERED release key (either
  ///    role) - a manifest channel open to arbitrary agents would let
  ///    any Sybil flood the evaluator with structurally-valid junk;
  ///    quorum-signed envelopes additionally attribute the carrier;
  ///  * the payload must parse as a bundle, then the full [ingest]
  ///    verification chain applies unchanged.
  /// Returns the [ManifestIngestResult]; [ManifestIngestResult.malformed]
  /// covers every transport-level drop (wrong kind, bad envelope,
  /// non-quorum signer, unparseable payload).
  Future<ManifestIngestResult> ingestEnvelope(BeaconEnvelope envelope) async {
    if (envelope.kind != ReleaseManifest.envelopeKind) {
      return ManifestIngestResult.malformed;
    }
    if (!await envelope.verify()) {
      return ManifestIngestResult.malformed;
    }
    if (!_registry.isReleaseKey(envelope.pubkey)) {
      return ManifestIngestResult.malformed;
    }
    final bundle = SignedManifestBundle.fromPayload(envelope.payload);
    if (bundle == null) return ManifestIngestResult.malformed;
    return ingest(bundle);
  }

  /// Counts DISTINCT keyIds in [keySet] that carry a verifying
  /// signature of role [role] over [preimage]. Duplicated keyIds count
  /// once (a signature flood from one key is still one vote); entries
  /// naming keyIds outside the set are ignored; any verifier exception
  /// counts as invalid (fail closed).
  Future<int> _countValidSignatures(
    List<ManifestSignature> signatures,
    String role,
    Map<String, String> keySet,
    List<int> preimage,
  ) async {
    final counted = <String>{};
    var valid = 0;
    for (final s in signatures) {
      if (s.role != role) continue;
      if (!counted.add(s.keyId)) continue; // same keyId never counts twice
      final pubkeyHex = keySet[s.keyId];
      if (pubkeyHex == null) continue; // not in this role
      Uint8List sigBytes;
      try {
        sigBytes = Uint8List.fromList(base64Decode(s.sig));
        if (sigBytes.length != 64) continue;
      } catch (_) {
        continue;
      }
      bool ok;
      try {
        ok = await _verifyFn(Uint8List.fromList(preimage), sigBytes, pubkeyHex);
      } catch (_) {
        ok = false;
      }
      if (ok) valid++;
    }
    return valid;
  }
}
