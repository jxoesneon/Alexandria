/// quorum-key registry abstraction for the TUF-style threshold-signed
/// release manifest (ALX-012 §5.1).
///
/// The registry is the manifest system's TRUST ROOT: it names the
/// quorum Ed25519 keys authorized to sign release manifests (the
/// TUF "release/targets" role) and timestamp metadata (the TUF
/// "timestamp"/freshness role), plus the signature threshold each role
/// requires. It is deliberately an injected abstraction - the same
/// ambient-config rule REV3 review applied to `trustedAttestorPubkeys`:
/// wire data must NEVER populate the signer quorum, so keys arrive through
/// node configuration (today: a compile-time [StaticReleaseKeyRegistry];
/// the seam stays open for a file/remote-pinned registry) and are frozen
/// for the life of the authority that consumes them.
///
/// ROLE SEPARATION (TUF mapping): release keys are the offline threshold
/// quorum (m-of-n, e.g. 3-of-5) that authorizes a floor assertion;
/// timestamp keys are the online freshness quorum - typically a single
/// online key (1-of-1) whose countersignature proves the manifest is
/// current and blocks freeze/replay attacks (an attacker replaying an
/// old valid manifest cannot mint fresh timestamp signatures). A key
/// registered under one role confers ZERO signing weight under the
/// other - a timestamp key cannot sign a release, and a release key
/// cannot vouch freshness.
library;

/// The key registry a `ReleaseManifestAuthority` trusts.
///
/// `keyId` is an opaque identifier chosen by the operator (e.g.
/// `quorum-release-1`); it maps to a lowercase hex Ed25519 pubkey.
/// Threshold counting is per-DISTINCT-keyId - two keyIds aliased to the
/// same pubkey are an operator misconfiguration, not an attack surface
/// (the operator chose the quorum), but a well-formed registry SHOULD
/// map each keyId to distinct key material.
abstract class ReleaseKeyRegistry {
  /// Release-role keys: keyId → hex Ed25519 pubkey. These sign the
  /// manifest body (`alexandria:release-manifest:v1:` preimage).
  Map<String, String> get releaseKeys;

  /// Release threshold `m`: a manifest is release-valid only when at
  /// least this many DISTINCT release keyIds carry a valid signature.
  int get releaseThreshold;

  /// Timestamp-role keys: keyId → hex Ed25519 pubkey. These sign the
  /// freshness record (`alexandria:manifest-timestamp:v1:` preimage).
  /// TUF maps this role to an online key - a 1-of-1 configuration is
  /// the expected production shape.
  Map<String, String> get timestampKeys;

  /// Timestamp threshold: distinct timestamp keyIds that must carry a
  /// valid freshness signature. Usually 1.
  int get timestampThreshold;

  /// Whether [pubkeyHex] is registered under ANY role - used to gate
  /// manifest envelopes to quorum-signed carriers (a relayer without
  /// quorum credentials cannot inject manifest traffic at all).
  bool isReleaseKey(String pubkeyHex);
}

/// Compile-time release registry - the production shape until a
/// configured/pinned registry transport exists (ALX-012 §5.1 trigger
/// condition i: "an attestor quorum of ≥3 independent keys is
/// configured in production").
///
/// The maps are defensively copied at construction so the caller cannot
/// grow the trust root by mutating the maps it handed in (the same
/// freeze rule as `MoltbookService._trustedAttestorPubkeys`).
class StaticReleaseKeyRegistry implements ReleaseKeyRegistry {
  StaticReleaseKeyRegistry({
    required Map<String, String> releaseKeys,
    required this.releaseThreshold,
    Map<String, String> timestampKeys = const {},
    this.timestampThreshold = 1,
  })  : releaseKeys = Map.unmodifiable(releaseKeys),
        timestampKeys = Map.unmodifiable(timestampKeys) {
    // A threshold above the quorum size can never be met - fail LOUD at
    // construction rather than silently refusing every manifest.
    if (releaseThreshold < 1 || releaseThreshold > releaseKeys.length) {
      throw ArgumentError(
          'releaseThreshold $releaseThreshold outside 1..${releaseKeys.length}');
    }
    if (timestampThreshold < 0 || timestampThreshold > timestampKeys.length) {
      throw ArgumentError('timestampThreshold $timestampThreshold outside '
          '0..${timestampKeys.length}');
    }
  }

  @override
  final Map<String, String> releaseKeys;
  @override
  final int releaseThreshold;
  @override
  final Map<String, String> timestampKeys;
  @override
  final int timestampThreshold;

  @override
  bool isReleaseKey(String pubkeyHex) {
    final needle = pubkeyHex.trim().toLowerCase();
    for (final hex in releaseKeys.values) {
      if (hex.toLowerCase() == needle) return true;
    }
    for (final hex in timestampKeys.values) {
      if (hex.toLowerCase() == needle) return true;
    }
    return false;
  }
}

/// An empty registry - the fail-closed default. No key is trusted, no
/// manifest can ever verify, and the effective floor stays at the
/// per-verifier compile-time constant. This is the safe-by-construction
/// state the RFC describes: "no manifest mechanism means no central
/// lever exists to abuse."
class EmptyReleaseKeyRegistry implements ReleaseKeyRegistry {
  const EmptyReleaseKeyRegistry();

  @override
  Map<String, String> get releaseKeys => const {};
  @override
  int get releaseThreshold => 1;
  @override
  Map<String, String> get timestampKeys => const {};
  @override
  int get timestampThreshold => 1;
  @override
  bool isReleaseKey(String pubkeyHex) => false;
}
