import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../credits/credit_service.dart';
import 'release_key_registry.dart';
import 'release_manifest_authority.dart';

/// The signer quorum-key trust root for release-manifest verification
/// (ALX-012 §5.1).
///
/// DEFAULT: [EmptyReleaseKeyRegistry] - fail closed by construction.
/// No key is trusted, so no manifest can ever verify and the effective
/// floor stays at the per-verifier compile-time constant. This is the
/// RFC's safe state: "no manifest mechanism means no central lever
/// exists to abuse" - an EMPTY registry cannot mint a quorum, and wire
/// data must never populate it.
///
/// PRODUCTION GRADUATION (RFC §5.1 trigger condition i): when an
/// attestor quorum of ≥3 independent release keys is configured, the
/// operator swaps this provider's value for a
/// [StaticReleaseKeyRegistry] carrying the pinned release/timestamp
/// keyIds and thresholds (e.g. 3-of-5 release, 1-of-1 timestamp). The
/// override must come from node configuration, NEVER from transported
/// data - the registry is the trust root, so letting the network name
/// its own quorum would be the Sybil bootstrapping attack in its
/// purest form.
final releaseKeyRegistryProvider = Provider<ReleaseKeyRegistry>(
  (ref) => const EmptyReleaseKeyRegistry(),
);

/// The threshold-signed release-manifest authority (ALX-012 §5.1):
/// evaluates `release_manifest` Beacon envelopes into the effective
/// claimable wire floor.
///
/// `baselineFloor` is the per-verifier compile-time constant
/// ([CreditService.minClaimableWireVersion]) - a valid manifest can
/// RAISE the effective floor above it but NEVER lower it (raise-only
/// ratchet, no central kill switch and no reverse-direction lever).
///
/// With the default empty registry the authority accepts nothing;
/// wiring it in anyway keeps the production ingest path (envelope →
/// quorum-signer gate → threshold chain) exercised in its real shape,
/// so enabling a quorum later is a pure configuration change.
final releaseManifestAuthorityProvider = Provider<ReleaseManifestAuthority>(
  (ref) => ReleaseManifestAuthority(
    registry: ref.read(releaseKeyRegistryProvider),
    baselineFloor: CreditService.minClaimableWireVersion,
  ),
);
