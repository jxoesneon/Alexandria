import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/models/security_models.dart';

void main() {
  group('SecurityAlert', () {
    test('holds values and toString works', () {
      final now = DateTime(2024, 5, 1);
      final alert = SecurityAlert(
        severity: 'high',
        message: 'No identity configured',
        timestamp: now,
      );
      expect(alert.severity, 'high');
      expect(alert.message, 'No identity configured');
      expect(alert.timestamp, now);
      expect(
        alert.toString(),
        'SecurityAlert(severity: high, message: No identity configured, timestamp: 2024-05-01 00:00:00.000)',
      );
    });
  });

  group('SecurityOverview', () {
    test('holds score and encryption flag', () {
      const overview = SecurityOverview(score: 82, encryptionEnabled: true);
      expect(overview.score, 82);
      expect(overview.encryptionEnabled, isTrue);
    });
  });

  group('KeyType', () {
    test('static constants have correct values', () {
      expect(KeyType.ed25519.name, 'Ed25519');
      expect(KeyType.ed25519.algorithm, 'Ed25519');
      expect(KeyType.secp256k1.name, 'Secp256k1');
      expect(KeyType.secp256k1.algorithm, 'ES256K');
    });

    test('equality and hashCode are value-based', () {
      const a = KeyType(name: 'Ed25519', algorithm: 'Ed25519');
      const b = KeyType.ed25519;
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(KeyType.secp256k1));
    });

    test('toString returns name', () {
      expect(KeyType.ed25519.toString(), 'Ed25519');
    });
  });

  group('Keypair', () {
    test('holds all fields', () {
      final created = DateTime(2024, 5, 1);
      final keypair = Keypair(
        id: 'key-001',
        type: KeyType.ed25519,
        createdAt: created,
        did: 'did:alex:key-001',
      );
      expect(keypair.id, 'key-001');
      expect(keypair.type, KeyType.ed25519);
      expect(keypair.createdAt, created);
      expect(keypair.did, 'did:alex:key-001');
    });
  });

  group('DidDocument', () {
    test('holds did and public keys', () {
      const doc = DidDocument(did: 'did:alex:abc', publicKeys: ['pk1']);
      expect(doc.did, 'did:alex:abc');
      expect(doc.publicKeys, ['pk1']);
    });
  });

  group('AccessPolicy', () {
    test('toJson and fromJson round-trip', () {
      final granted = DateTime(2024, 5, 1, 12, 30);
      final policy = AccessPolicy(
        cid: 'cid-123',
        peerDid: 'did:alex:peer',
        grantedAt: granted,
      );
      final json = policy.toJson();
      expect(json['cid'], 'cid-123');
      expect(json['peerDid'], 'did:alex:peer');
      expect(json['grantedAt'], granted.toIso8601String());

      final restored = AccessPolicy.fromJson(json);
      expect(restored.cid, policy.cid);
      expect(restored.peerDid, policy.peerDid);
      expect(restored.grantedAt, policy.grantedAt);
    });

    test('fields are exposed', () {
      final policy = AccessPolicy(
        cid: 'c',
        peerDid: 'p',
        grantedAt: DateTime(2024, 1, 1),
      );
      expect(policy.cid, 'c');
      expect(policy.peerDid, 'p');
    });
  });

  group('AuditLog', () {
    test('holds fields', () {
      final log = AuditLog(
        event: 'grant_access',
        actor: 'did:alex:peer',
        timestamp: DateTime(2024, 5, 1),
        status: 'Success',
      );
      expect(log.event, 'grant_access');
      expect(log.actor, 'did:alex:peer');
      expect(log.timestamp, DateTime(2024, 5, 1));
      expect(log.status, 'Success');
    });
  });

  group('PorChallenge', () {
    test('holds fields', () {
      final challenge = PorChallenge(
        challengeId: 'ch-1',
        cid: 'cid-1',
        peerId: 'peer-1',
        issuedAt: DateTime(2024, 5, 1),
      );
      expect(challenge.challengeId, 'ch-1');
      expect(challenge.cid, 'cid-1');
      expect(challenge.peerId, 'peer-1');
      expect(challenge.issuedAt, DateTime(2024, 5, 1));
    });
  });

  group('PorProof', () {
    test('holds fields', () {
      final proof = PorProof(
        cid: 'cid-1',
        peerId: 'peer-1',
        respondedAt: DateTime(2024, 5, 1),
        verified: true,
      );
      expect(proof.cid, 'cid-1');
      expect(proof.peerId, 'peer-1');
      expect(proof.respondedAt, DateTime(2024, 5, 1));
      expect(proof.verified, isTrue);
    });
  });

  group('DocumentOption', () {
    test('holds cid and title', () {
      const doc = DocumentOption(cid: 'cid-1', title: 'Title');
      expect(doc.cid, 'cid-1');
      expect(doc.title, 'Title');
    });
  });
}
