import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../models/security_models.dart';
import 'audit_log_service.dart';
import 'biometric_service.dart';
import 'encryption_service.dart';
import 'identity_service.dart';
import 'ipfs_service.dart';
import 'proof_of_retrievability_service.dart' as por;
import 'secure_storage_service.dart';

/// Aggregates data from existing services for the Security screens.
class SecurityOverviewService {
  final Ref _ref;

  static const _accessPoliciesKey = 'alexandria_access_policies';

  SecurityOverviewService(this._ref);

  // ------------------------------------------------------------------
  // Dashboard overview & alerts
  // ------------------------------------------------------------------
  Future<SecurityOverview> getOverview() async {
    final identity = await _ref.read(identityServiceProvider).getIdentity();
    final biometric =
        await _ref.read(biometricServiceProvider).isBiometricsAvailable();
    final secureMode = await _secureModeEnabled();
    final encryptedCount = await _encryptedManifestCount();
    final masterKey =
        await _ref.read(secureStorageServiceProvider).read('master_key_v1');

    var score = 50;
    if (identity != null) score += 25;
    if (biometric) score += 10;
    if (secureMode) score += 10;
    if (encryptedCount > 0 || masterKey != null) score += 5;
    if (score > 100) score = 100;

    return SecurityOverview(
      score: score,
      encryptionEnabled: encryptedCount > 0 || masterKey != null,
    );
  }

  Stream<List<SecurityAlert>> watchSecurityAlerts() {
    return Stream.fromFuture(getCurrentAlerts());
  }

  Future<List<SecurityAlert>> getCurrentAlerts() async {
    final alerts = <SecurityAlert>[];
    final identity = await _ref.read(identityServiceProvider).getIdentity();
    final biometric =
        await _ref.read(biometricServiceProvider).isBiometricsAvailable();
    final secureMode = await _secureModeEnabled();
    final encryptedCount = await _encryptedManifestCount();

    if (identity == null) {
      alerts.add(SecurityAlert(
        severity: 'high',
        message: 'No identity configured; generate a keypair to sign content.',
        timestamp: DateTime.now(),
      ));
    } else {
      // Same key AND same store that MnemonicService.markBackupConfirmed
      // writes (previously this read 'alexandria_mnemonic_backup_hash' —
      // a key that was never written — while the marker lived in a
      // different keychain, so the backup warning could never clear).
      final backup = await _ref
          .read(secureStorageServiceProvider)
          .read(SecureStorageKeys.mnemonicBackup);
      if (backup == null) {
        alerts.add(SecurityAlert(
          severity: 'low',
          message: 'Backup your identity with a mnemonic.',
          timestamp: DateTime.now(),
        ));
      }
    }

    if (biometric && !secureMode) {
      alerts.add(SecurityAlert(
        severity: 'medium',
        message: 'Biometric authentication is available but not enabled.',
        timestamp: DateTime.now(),
      ));
    }

    if (encryptedCount == 0) {
      alerts.add(SecurityAlert(
        severity: 'medium',
        message:
            'No encrypted content found. Consider encrypting sensitive documents.',
        timestamp: DateTime.now(),
      ));
    }

    final logs = await getRecentAuditLogs(50);
    final denied = logs.where((l) {
      final s = l.status.toLowerCase();
      return s.startsWith('den') || s.startsWith('fail');
    }).length;
    if (denied > 0) {
      alerts.add(SecurityAlert(
        severity: 'high',
        message: 'Recent access denials detected ($denied).',
        timestamp: DateTime.now(),
      ));
    }

    return alerts;
  }

  Future<bool> _secureModeEnabled() async {
    final value = await _ref
        .read(secureStorageServiceProvider)
        .read('secure_mode_enabled');
    return value == 'true';
  }

  Future<int> _encryptedManifestCount() async {
    final db = _ref.read(databaseProvider);
    final manifests = await db.getAllManifests();
    return manifests.where((m) => m.isEncrypted).length;
  }

  // ------------------------------------------------------------------
  // Key management
  // ------------------------------------------------------------------
  Future<List<Keypair>> getActiveIdentities() async {
    final identity = await _ref.read(identityServiceProvider).getIdentity();
    if (identity == null) return const [];
    return [
      Keypair(
        id: identity.shortId,
        type: KeyType.ed25519,
        createdAt: identity.createdAt,
        did: 'did:alex:${identity.shortId}',
      ),
    ];
  }

  Future<Keypair> generateNewKeypair(KeyType type) async {
    if (type != KeyType.ed25519) {
      throw ArgumentError('Only Ed25519 keypairs are currently supported.');
    }
    // Rotation MUST go through IdentityService — the single owner of the
    // identity keys/cache — so the stored and cached identities can
    // never diverge (split-brain).
    final identity =
        await _ref.read(identityServiceProvider).generateIdentity();
    // The active keypair changed out-of-band of the UI. Dependents that
    // watch identityRevisionProvider (identityStateProvider,
    // activeIdentitiesProvider, securityOverviewProvider,
    // securityAlertsProvider) rebuild automatically; this explicit
    // invalidation is belt-and-suspenders for the same path.
    _ref.invalidate(identityStateProvider);
    return Keypair(
      id: identity.shortId,
      type: KeyType.ed25519,
      createdAt: identity.createdAt,
      did: 'did:alex:${identity.shortId}',
    );
  }

  // ------------------------------------------------------------------
  // Password-protected key export (KDF parameters)
  // ------------------------------------------------------------------
  //
  // (security-round finding) The export previously keyed AES with
  // sha256(utf8(password)) — a SINGLE-ROUND UNSALTED hash. Anyone
  // holding an exported blob could brute-force the password at GPU
  // hashcat rates, and identical passwords produced identical keys
  // (cross-blob correlation). The wrapping key is now derived with
  // Argon2id (memory-hard; params below are the OWASP minimum:
  // m=19 MiB, t=2, p=1) over a random 16-byte salt, and the export is
  // a versioned JSON envelope carrying salt + KDF parameters so a
  // future importer can re-derive without guessing.
  //
  // FORMAT BREAK (documented, deliberate): exports produced before
  // this change are raw base64 AES-GCM ciphertexts keyed by
  // SHA-256(password); v2 exports are base64(JSON envelope). There is
  // no in-app importer — the blob is written out for the user — so no
  // in-tree reader needs compat; any external consumer must detect
  // the envelope ('v': 2) and apply the stated KDF.

  /// Version tag for the export envelope format.
  static const int exportFormatVersion = 2;

  /// Argon2id parameters used for export key derivation (OWASP minimum:
  /// 19 MiB memory, 2 iterations, parallelism 1, 32-byte output).
  static const int _exportKdfMemoryKiB = 19 * 1024;
  static const int _exportKdfIterations = 2;
  static const int _exportKdfParallelism = 1;
  static const int _exportKdfHashLength = 32;
  static const int _exportSaltLength = 16;

  Future<String> exportPrivateKey(String keyId, String password) async {
    final identity = await _ref.read(identityServiceProvider).getIdentity();
    if (identity == null) throw StateError('No identity exists.');
    if (identity.shortId != keyId) {
      throw ArgumentError('Key id does not match the active identity.');
    }
    final salt =
        List<int>.generate(_exportSaltLength, (_) => _secureRandom.nextInt(256));
    final kdf = Argon2id(
      parallelism: _exportKdfParallelism,
      memory: _exportKdfMemoryKiB,
      iterations: _exportKdfIterations,
      hashLength: _exportKdfHashLength,
    );
    final key = await kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    final encrypted = await _ref
        .read(encryptionServiceProvider)
        .encryptData(identity.privateKey, key);
    final envelope = jsonEncode({
      'v': exportFormatVersion,
      'kdf': 'argon2id',
      'parallelism': _exportKdfParallelism,
      'memory': _exportKdfMemoryKiB,
      'iterations': _exportKdfIterations,
      'hashLength': _exportKdfHashLength,
      'salt': base64Encode(salt),
      'blob': base64Encode(encrypted),
    });
    return base64Encode(utf8.encode(envelope));
  }

  static final _secureRandom = Random.secure();

  Future<DidDocument> resolveDid(String did) async {
    final identity = await _ref.read(identityServiceProvider).getIdentity();
    if (did.startsWith('did:alex:')) {
      final suffix = did.substring('did:alex:'.length);
      if (identity != null && suffix == identity.shortId) {
        return DidDocument(did: did, publicKeys: [identity.publicKeyBase58]);
      }
    }

    final db = _ref.read(databaseProvider);
    final profile = await db.getProfileByPublicKey(did);
    if (profile != null) {
      return DidDocument(did: did, publicKeys: [profile.publicKey]);
    }

    return DidDocument(did: did, publicKeys: const []);
  }

  // ------------------------------------------------------------------
  // Access control
  // ------------------------------------------------------------------
  Future<List<DocumentOption>> getDocuments() async {
    final db = _ref.read(databaseProvider);
    final manifests = await db.getAllManifests();
    final options = <DocumentOption>[];
    for (final manifest in manifests) {
      final versions = await db.getVersionsForManifest(manifest.id);
      if (versions.isEmpty) continue;
      for (final version in versions) {
        options.add(DocumentOption(cid: version.cid, title: manifest.title));
      }
    }
    return options;
  }

  /// Validates a peer DID claim before it is written into an access
  /// grant. The DID is stored verbatim and echoed into the audit log
  /// (a `|` or newline would forge log columns upstream of the audit
  /// service's escaping), so accept only well-formed `did:` strings
  /// of bounded length with no whitespace or control characters.
  static const int maxPeerDidLength = 256;

  static void _requirePeerDid(String peerDid) {
    if (peerDid.isEmpty ||
        peerDid.length > maxPeerDidLength ||
        !peerDid.startsWith('did:') ||
        // Whitespace/controls are not valid in a DID; '|' and '\' are
        // rejected too — neither is legal DID syntax, and both are the
        // audit log's column delimiter and escape lead-in.
        peerDid.codeUnits.any(
            (c) => c <= 0x20 || c == 0x7F || c == 0x7C || c == 0x5C)) {
      throw ArgumentError('Invalid peer DID');
    }
  }

  /// Reads the access-policy store; a corrupt or non-map payload is
  /// treated as EMPTY — fail-closed, because policies are grants:
  /// dropping unreadable grants denies access rather than trusting
  /// malformed data (previously a corrupted store threw
  /// FormatException/CastError up through every ACL read).
  static Map<String, dynamic> _readPolicyMap(String? raw) {
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, dynamic>{};
      return Map<String, dynamic>.from(decoded);
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  Future<List<AccessPolicy>> getAccessPolicies(String cid) async {
    final storage = _ref.read(secureStorageServiceProvider);
    final map = _readPolicyMap(await storage.read(_accessPoliciesKey));
    final list = (map[cid] as List<dynamic>?) ?? [];
    // Per-entry decode guard: one malformed policy entry must not throw
    // away or crash the whole ACL read — it is simply not a grant.
    return list
        .whereType<Map>()
        .map((e) {
          try {
            return AccessPolicy.fromJson(Map<String, dynamic>.from(e));
          } catch (_) {
            return null;
          }
        })
        .whereType<AccessPolicy>()
        .toList();
  }

  Future<void> grantAccess(String cid, String peerDid) async {
    _requirePeerDid(peerDid);
    final policies = await getAccessPolicies(cid);
    if (policies.any((p) => p.peerDid == peerDid)) return;
    final updated = [
      ...policies,
      AccessPolicy(cid: cid, peerDid: peerDid, grantedAt: DateTime.now()),
    ];
    await _saveAccessPolicies(cid, updated);
    await _ref.read(auditLogServiceProvider).log(
          'grant_access',
          details: 'CID: $cid, Peer: $peerDid',
          actor: peerDid,
          status: 'Success',
        );
  }

  Future<void> revokeAccess(String cid, String peerDid) async {
    _requirePeerDid(peerDid);
    final policies = await getAccessPolicies(cid);
    final updated = policies.where((p) => p.peerDid != peerDid).toList();
    await _saveAccessPolicies(cid, updated);
    await _ref.read(auditLogServiceProvider).log(
          'revoke_access',
          details: 'CID: $cid, Peer: $peerDid',
          actor: peerDid,
          status: 'Success',
        );
  }

  Future<void> _saveAccessPolicies(
      String cid, List<AccessPolicy> policies) async {
    final storage = _ref.read(secureStorageServiceProvider);
    final map = _readPolicyMap(await storage.read(_accessPoliciesKey));
    map[cid] = policies.map((p) => p.toJson()).toList();
    await storage.write(_accessPoliciesKey, jsonEncode(map));
  }

  // ------------------------------------------------------------------
  // Audit logs
  // ------------------------------------------------------------------
  Future<List<AuditLog>> getRecentAuditLogs(int limit) async {
    return _ref.read(auditLogServiceProvider).getRecentLogs(limit);
  }

  // ------------------------------------------------------------------
  // Proof of retrievability
  // ------------------------------------------------------------------
  Future<PorChallenge> issueChallenge(String cid, String peerId) async {
    final porService = _ref.read(por.proofOfRetrievabilityServiceProvider);
    final challenge = porService.createChallenge(cid: cid, totalChunks: 1);
    // The PoR service's own (bounded, TTL'd) pending-challenge map is the
    // single source of truth — the duplicate map this service used to
    // keep was written but never cleaned (REV4 review / Efficiency 7a).
    return PorChallenge(
      challengeId: challenge.challengeId,
      cid: challenge.cid,
      peerId: peerId,
      issuedAt: challenge.timestamp,
    );
  }

  Future<bool> verifyChallenge(PorChallenge challenge) async {
    final porService = _ref.read(por.proofOfRetrievabilityServiceProvider);
    final original = porService.pendingChallenge(challenge.challengeId);
    if (original == null) return false;

    final chunks = <int>[];
    await for (final chunk
        in _ref.read(ipfsServiceProvider).getFile(challenge.cid)) {
      chunks.addAll(chunk);
    }
    final chunkData = Uint8List.fromList(chunks);
    final proof =
        porService.generateProof(challenge: original, chunkData: chunkData);
    return porService.verifyProof(
      proof: proof,
      expectedChunkData: chunkData,
      proverPeerId: challenge.peerId,
    );
  }
}
