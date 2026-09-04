/// A security alert shown on the dashboard.
class SecurityAlert {
  final String severity;
  final String message;
  final DateTime timestamp;

  const SecurityAlert({
    required this.severity,
    required this.message,
    required this.timestamp,
  });

  @override
  String toString() =>
      'SecurityAlert(severity: $severity, message: $message, timestamp: $timestamp)';
}

/// Summary of the current security posture.
class SecurityOverview {
  final int score;
  final bool encryptionEnabled;

  const SecurityOverview({
    required this.score,
    required this.encryptionEnabled,
  });
}

/// The type of cryptographic keypair.
class KeyType {
  final String name;
  final String algorithm;

  const KeyType({required this.name, required this.algorithm});

  static const ed25519 = KeyType(name: 'Ed25519', algorithm: 'Ed25519');
  static const secp256k1 = KeyType(name: 'Secp256k1', algorithm: 'ES256K');

  @override
  bool operator ==(Object other) =>
      other is KeyType && other.name == name && other.algorithm == algorithm;

  @override
  int get hashCode => Object.hash(name, algorithm);

  @override
  String toString() => name;
}

/// A displayed keypair / identity.
class Keypair {
  final String id;
  final KeyType type;
  final DateTime createdAt;
  final String did;

  const Keypair({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.did,
  });
}

/// A resolved DID document.
class DidDocument {
  final String did;
  final List<String> publicKeys;

  const DidDocument({required this.did, required this.publicKeys});
}

/// An access policy granting a peer DID access to a CID.
class AccessPolicy {
  final String cid;
  final String peerDid;
  final DateTime grantedAt;

  const AccessPolicy({
    required this.cid,
    required this.peerDid,
    required this.grantedAt,
  });

  Map<String, dynamic> toJson() => {
        'cid': cid,
        'peerDid': peerDid,
        'grantedAt': grantedAt.toIso8601String(),
      };

  factory AccessPolicy.fromJson(Map<String, dynamic> json) => AccessPolicy(
        cid: json['cid'] as String,
        peerDid: json['peerDid'] as String,
        grantedAt: DateTime.parse(json['grantedAt'] as String),
      );
}

/// An audit log entry.
class AuditLog {
  final String event;
  final String actor;
  final DateTime timestamp;
  final String status;

  const AuditLog({
    required this.event,
    required this.actor,
    required this.timestamp,
    required this.status,
  });
}

/// A Proof-of-Retrievability challenge shown in the UI.
class PorChallenge {
  final String challengeId;
  final String cid;
  final String peerId;
  final DateTime issuedAt;

  const PorChallenge({
    required this.challengeId,
    required this.cid,
    required this.peerId,
    required this.issuedAt,
  });
}

/// A Proof-of-Retrievability proof shown in the UI.
class PorProof {
  final String cid;
  final String peerId;
  final DateTime respondedAt;
  final bool verified;

  const PorProof({
    required this.cid,
    required this.peerId,
    required this.respondedAt,
    required this.verified,
  });
}

/// A selectable document for access control.
class DocumentOption {
  final String cid;
  final String title;

  const DocumentOption({required this.cid, required this.title});
}
