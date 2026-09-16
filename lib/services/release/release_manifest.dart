import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../agent/beacon_models.dart';

/// A single role-slotted manifest signature (ALX-012 §5.1).
///
/// Each signature names the signer quorum `keyId` it was produced under and
/// the TUF-style [role] it belongs to — `'release'` signatures cover the
/// manifest body (threshold quorum), `'timestamp'` signatures cover the
/// freshness record (online-key quorum). The role slot is part of the
/// verification semantics: a signature is only ever evaluated against
/// the key set of its declared role, so a release key can never vouch
/// freshness and a timestamp key can never authorize a floor.
class ManifestSignature {
  static const String roleRelease = 'release';
  static const String roleTimestamp = 'timestamp';

  final String role;
  final String keyId;
  final String sig; // base64 Ed25519 signature

  const ManifestSignature({
    required this.role,
    required this.keyId,
    required this.sig,
  });

  Map<String, dynamic> toJson() => {'role': role, 'keyid': keyId, 'sig': sig};

  static ManifestSignature? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    final role = m['role'] as String?;
    final keyId = m['keyid'] as String?;
    final sig = m['sig'] as String?;
    if (role == null || keyId == null || sig == null) return null;
    if (role != roleRelease && role != roleTimestamp) return null;
    return ManifestSignature(role: role, keyId: keyId, sig: sig);
  }
}

/// The TUF-style quorum-signed release manifest (ALX-012 §5.1): the
/// terminal stage of the wire floor's authority
/// (`constant → verifier policy → threshold-signed manifest`).
///
/// A manifest asserts a claimable wire floor `minWireVersion` under a
/// monotonically increasing [sequence] (rollback resistance — a
/// manifest only ever supersedes strictly-lower sequences) with a hard
/// [expiresAt] staleness bound (an abandoned manifest cannot pin the
/// floor forever).
///
/// CONSTRUCTIBLE FREELY — unlike `EscrowAttestation`/`BountyClaimEvent`
/// the manifest is a data carrier; its authority comes exclusively from
/// `ReleaseManifestAuthority.ingest`, which performs the m-of-n
/// threshold check, the timestamp-role freshness check, the rollback
/// check and the raise-only floor evaluation. Holding a ReleaseManifest
/// object confers nothing until an authority accepts it.
///
/// The canonical signed body (what the release keys sign) is
/// `utf8('alexandria:release-manifest:v1:' + canonicalJson({expires_at,
/// issued_at, min_wire_version, sequence}))` — canonical JSON with
/// sorted keys makes field boundaries structural, and the domain prefix
/// keeps the preimage non-replayable as any other artifact class.
class ReleaseManifest {
  /// Beacon envelope kind carrying a manifest bundle payload.
  static const String envelopeKind = 'release_manifest';

  /// Manifest format version — the `v1` in the preimage domain.
  static const int manifestVersion = 1;

  /// The wire floor this manifest asserts (RFC `min_wire_version`).
  final int minWireVersion;

  /// Monotonic sequence number — rollback resistance: an authority only
  /// accepts a manifest whose sequence is strictly greater than the
  /// last accepted one.
  final int sequence;

  /// Issue time, epoch milliseconds (advisory ordering/metadata; the
  /// freshness guarantee lives in the timestamp record).
  final int issuedAt;

  /// Expiry, epoch milliseconds — after this the manifest is stale and
  /// ignored. Prevents an abandoned manifest pinning the floor
  /// indefinitely (RFC: "expiry … prevents indefinite pinning").
  final int expiresAt;

  /// Role-slotted signatures over [signingPreimage]. Release-role
  /// entries are what the threshold check counts; timestamp-role
  /// entries are ignored here (freshness lives in [ManifestTimestamp]).
  final List<ManifestSignature> signatures;

  const ReleaseManifest({
    required this.minWireVersion,
    required this.sequence,
    required this.issuedAt,
    required this.expiresAt,
    required this.signatures,
  });

  /// The canonical unsigned body — also the hash input for the
  /// timestamp role's `manifest_hash` binding.
  Map<String, dynamic> toSignedBody() => {
        'expires_at': expiresAt,
        'issued_at': issuedAt,
        'min_wire_version': minWireVersion,
        'sequence': sequence,
      };

  /// Canonical bytes the release-role release keys sign and verifiers
  /// recompute.
  static Uint8List signingPreimage({
    required int minWireVersion,
    required int sequence,
    required int issuedAt,
    required int expiresAt,
  }) =>
      Uint8List.fromList(
        utf8.encode(
          'alexandria:release-manifest:v1:'
          '${toCanonicalJson(<String, dynamic>{
                'expires_at': expiresAt,
                'issued_at': issuedAt,
                'min_wire_version': minWireVersion,
                'sequence': sequence,
              })}',
        ),
      );

  Uint8List get preimage => signingPreimage(
      minWireVersion: minWireVersion,
      sequence: sequence,
      issuedAt: issuedAt,
      expiresAt: expiresAt);

  /// SHA-256 hex of the canonical body — the value the timestamp
  /// record's `manifest_hash` must equal to bind this manifest.
  String get contentHash =>
      sha256.convert(utf8.encode(toCanonicalJson(toSignedBody()))).toString();

  bool isExpired([DateTime? now]) =>
      (now ?? DateTime.now()).millisecondsSinceEpoch > expiresAt;

  Map<String, dynamic> toJson() => {
        'v': manifestVersion,
        'min_wire_version': minWireVersion,
        'sequence': sequence,
        'issued_at': issuedAt,
        'expires_at': expiresAt,
        'signatures': signatures.map((s) => s.toJson()).toList(),
      };

  /// Parses a manifest map (e.g. out of an envelope payload). Returns
  /// null on any malformed field — transports drop, never throw.
  static ReleaseManifest? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    final minWire = (m['min_wire_version'] as num?)?.toInt();
    final seq = (m['sequence'] as num?)?.toInt();
    final issued = (m['issued_at'] as num?)?.toInt();
    final expires = (m['expires_at'] as num?)?.toInt();
    final sigsRaw = m['signatures'];
    if (minWire == null ||
        seq == null ||
        issued == null ||
        expires == null ||
        sigsRaw is! List) {
      return null;
    }
    final sigs = <ManifestSignature>[];
    for (final s in sigsRaw) {
      final parsed = ManifestSignature.fromJson(s);
      if (parsed == null) return null;
      sigs.add(parsed);
    }
    return ReleaseManifest(
      minWireVersion: minWire,
      sequence: seq,
      issuedAt: issued,
      expiresAt: expires,
      signatures: List.unmodifiable(sigs),
    );
  }

  /// quorum-side issuance helper: signs the manifest under every
  /// release-role [releaseSigners] keypair (keyId → keypair). The
  /// authority counts DISTINCT keyIds, so the caller supplies the
  /// registry keyIds it controls. Not part of the verification path —
  /// exists so quorum tooling/tests produce well-formed manifests.
  static Future<ReleaseManifest> issue({
    required int minWireVersion,
    required int sequence,
    required int issuedAt,
    required int expiresAt,
    required Map<String, SimpleKeyPair> releaseSigners,
  }) async {
    final preimage = signingPreimage(
        minWireVersion: minWireVersion,
        sequence: sequence,
        issuedAt: issuedAt,
        expiresAt: expiresAt);
    final ed = Ed25519();
    final sigs = <ManifestSignature>[];
    for (final entry in releaseSigners.entries) {
      final sig = await ed.sign(preimage, keyPair: entry.value);
      sigs.add(ManifestSignature(
          role: ManifestSignature.roleRelease,
          keyId: entry.key,
          sig: base64Encode(sig.bytes)));
    }
    return ReleaseManifest(
      minWireVersion: minWireVersion,
      sequence: sequence,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      signatures: List.unmodifiable(sigs),
    );
  }
}

/// The TUF "timestamp" role: a freshness record signed by the online
/// timestamp quorum binding a manifest's content hash and sequence at
/// a point in time. This is the anti-freeze/anti-replay half of the
/// design — an attacker (or a stale mirror) replaying an old, still-
/// unexpired manifest cannot mint a fresh timestamp signature, so
/// manifest freshness is enforced through the timestamp role rather
/// than the manifest's own (longer) expiry alone.
class ManifestTimestamp {
  static const int timestampVersion = 1;

  /// Sequence of the manifest this record covers — must equal the
  /// manifest's own `sequence`.
  final int sequence;

  /// SHA-256 hex of the manifest's canonical signed body
  /// ([ReleaseManifest.contentHash]).
  final String manifestHash;

  /// When the timestamp quorum signed, epoch milliseconds.
  final int timestamp;

  /// Freshness expiry, epoch milliseconds — after this the record is
  /// stale (TUF timestamps are deliberately short-lived).
  final int expiresAt;

  /// Timestamp-role signatures over [signingPreimage].
  final List<ManifestSignature> signatures;

  const ManifestTimestamp({
    required this.sequence,
    required this.manifestHash,
    required this.timestamp,
    required this.expiresAt,
    required this.signatures,
  });

  static Uint8List signingPreimage({
    required int sequence,
    required String manifestHash,
    required int timestamp,
    required int expiresAt,
  }) =>
      Uint8List.fromList(
        utf8.encode(
          'alexandria:manifest-timestamp:v1:'
          '${toCanonicalJson(<String, dynamic>{
                'expires_at': expiresAt,
                'manifest_hash': manifestHash,
                'sequence': sequence,
                'timestamp': timestamp,
              })}',
        ),
      );

  Uint8List get preimage => signingPreimage(
      sequence: sequence,
      manifestHash: manifestHash,
      timestamp: timestamp,
      expiresAt: expiresAt);

  bool isExpired([DateTime? now]) =>
      (now ?? DateTime.now()).millisecondsSinceEpoch > expiresAt;

  Map<String, dynamic> toJson() => {
        'v': timestampVersion,
        'sequence': sequence,
        'manifest_hash': manifestHash,
        'timestamp': timestamp,
        'expires_at': expiresAt,
        'signatures': signatures.map((s) => s.toJson()).toList(),
      };

  static ManifestTimestamp? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    final seq = (m['sequence'] as num?)?.toInt();
    final hash = m['manifest_hash'] as String?;
    final ts = (m['timestamp'] as num?)?.toInt();
    final expires = (m['expires_at'] as num?)?.toInt();
    final sigsRaw = m['signatures'];
    if (seq == null ||
        hash == null ||
        ts == null ||
        expires == null ||
        sigsRaw is! List) {
      return null;
    }
    final sigs = <ManifestSignature>[];
    for (final s in sigsRaw) {
      final parsed = ManifestSignature.fromJson(s);
      if (parsed == null) return null;
      sigs.add(parsed);
    }
    return ManifestTimestamp(
      sequence: seq,
      manifestHash: hash,
      timestamp: ts,
      expiresAt: expires,
      signatures: List.unmodifiable(sigs),
    );
  }

  /// quorum-side issuance helper: signs the freshness record for
  /// [manifest] under every timestamp-role [timestampSigners] keypair.
  static Future<ManifestTimestamp> issue(
    ReleaseManifest manifest, {
    required Map<String, SimpleKeyPair> timestampSigners,
    required int timestamp,
    required int expiresAt,
  }) async {
    final preimage = signingPreimage(
        sequence: manifest.sequence,
        manifestHash: manifest.contentHash,
        timestamp: timestamp,
        expiresAt: expiresAt);
    final ed = Ed25519();
    final sigs = <ManifestSignature>[];
    for (final entry in timestampSigners.entries) {
      final sig = await ed.sign(preimage, keyPair: entry.value);
      sigs.add(ManifestSignature(
          role: ManifestSignature.roleTimestamp,
          keyId: entry.key,
          sig: base64Encode(sig.bytes)));
    }
    return ManifestTimestamp(
      sequence: manifest.sequence,
      manifestHash: manifest.contentHash,
      timestamp: timestamp,
      expiresAt: expiresAt,
      signatures: List.unmodifiable(sigs),
    );
  }
}

/// The ingest/transport unit: a manifest plus the timestamp-role
/// freshness record that binds it. Verification is meaningless on an
/// unbundled manifest — freshness is a property of the pair.
class SignedManifestBundle {
  final ReleaseManifest manifest;
  final ManifestTimestamp timestamp;

  const SignedManifestBundle({required this.manifest, required this.timestamp});

  /// Payload block carried inside a `release_manifest` Beacon envelope.
  Map<String, dynamic> toPayloadBlock() => {
        'manifest': manifest.toJson(),
        'timestamp': timestamp.toJson(),
      };

  /// Parses the bundle out of an envelope payload (`manifest` /
  /// `timestamp` blocks). Returns null on malformed input.
  static SignedManifestBundle? fromPayload(Map<String, dynamic> payload) {
    final manifest = ReleaseManifest.fromJson(payload['manifest']);
    final ts = ManifestTimestamp.fromJson(payload['timestamp']);
    if (manifest == null || ts == null) return null;
    return SignedManifestBundle(manifest: manifest, timestamp: ts);
  }

  /// Wraps this bundle in a signed Beacon v2 envelope of kind
  /// [ReleaseManifest.envelopeKind]. The authority requires the envelope
  /// signer to be a release key — [keyPair] should belong to a
  /// registered quorum member (either role).
  Future<BeaconEnvelope> toEnvelope(SimpleKeyPair keyPair) =>
      BeaconEnvelope.create(
        kind: ReleaseManifest.envelopeKind,
        keyPair: keyPair,
        payload: toPayloadBlock(),
      );
}
