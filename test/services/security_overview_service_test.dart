import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart';
import 'package:alexandria/models/security_models.dart';
import 'package:alexandria/providers/security_providers.dart';
import 'package:alexandria/services/audit_log_service.dart';
import 'package:alexandria/services/biometric_service.dart';
import 'package:alexandria/services/encryption_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/proof_of_retrievability_service.dart'
    as por;
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:alexandria/services/security_overview_service.dart';

// --- Fakes ---

class FakeIdentityService implements IdentityService {
  AlexandriaIdentity? _identity;
  int _generated = 0;

  void setIdentity(AlexandriaIdentity? value) => _identity = value;

  @override
  Future<AlexandriaIdentity?> getIdentity() async => _identity;

  @override
  Future<AlexandriaIdentity> generateIdentity() async {
    _generated++;
    _identity = AlexandriaIdentity(
      publicKey: Uint8List(32),
      privateKey: Uint8List.fromList(List.generate(32, (i) => i)),
      createdAt: DateTime(2024, 5, 1),
    );
    return _identity!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBiometricService implements BiometricService {
  bool available = false;

  @override
  Future<bool> isBiometricsAvailable() async => available;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeEncryptionService implements EncryptionService {
  @override
  Future<Uint8List> encryptData(Uint8List plaintext, SecretKey key) async {
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<Uint8List> decryptData(Uint8List cipherData, SecretKey key) async {
    return cipherData;
  }

  @override
  Future<SecretKey> generateKey() async => SecretKey(Uint8List(32));

  @override
  Future<List<int>> keyToBytes(SecretKey key) async => await key.extractBytes();

  @override
  Future<SecretKey> keyFromBytes(List<int> bytes) async => SecretKey(bytes);

  @override
  Future<Uint8List> encryptForPeer(Uint8List data, String peerPublicKey) async {
    return Uint8List.fromList([4, 5, 6]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuditLogService implements AuditLogService {
  List<AuditLog> logs = const [];
  String? lastAction;
  String? lastDetails;
  String? lastActor;
  String? lastStatus;

  @override
  Future<List<AuditLog>> getRecentLogs(int limit) async => logs;

  @override
  Future<void> log(
    String action, {
    String? details,
    String? actor,
    String status = 'Success',
  }) async {
    lastAction = action;
    lastDetails = details;
    lastActor = actor;
    lastStatus = status;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSecureStorageService implements SecureStorageService {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> deleteAll() async => _data.clear();

  @override
  Future<bool> containsKey(String key) async => _data.containsKey(key);
}

class FakeIpfsService implements IpfsService {
  final Map<String, Uint8List> _files = {};

  void seedFile(String cid, Uint8List data) => _files[cid] = data;

  @override
  Stream<Uint8List> getFile(String cid) async* {
    if (_files.containsKey(cid)) {
      yield _files[cid]!;
    } else {
      yield Uint8List(0);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeProofOfRetrievabilityService
    implements por.ProofOfRetrievabilityService {
  final Map<String, por.PoRChallenge> _challenges = {};
  bool verifyResult = true;

  @override
  por.PoRChallenge createChallenge({
    required String cid,
    required int totalChunks,
  }) {
    final challenge = por.PoRChallenge(
      challengeId: 'chal-$cid',
      cid: cid,
      chunkIndex: 0,
      nonce: Uint8List.fromList(List.generate(32, (i) => i)),
      timestamp: DateTime(2024, 5, 1),
    );
    _challenges[challenge.challengeId] = challenge;
    return challenge;
  }

  @override
  por.PoRProof generateProof({
    required por.PoRChallenge challenge,
    required Uint8List chunkData,
  }) {
    return por.PoRProof(
      challengeId: challenge.challengeId,
      tag: 'tag',
      timestamp: DateTime(2024, 5, 1),
    );
  }

  @override
  bool verifyProof({
    required por.PoRProof proof,
    required Uint8List expectedChunkData,
    required String proverPeerId,
  }) {
    return verifyResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// --- Helpers ---

AlexandriaIdentity _makeIdentity() => AlexandriaIdentity(
      publicKey: Uint8List(32),
      privateKey: Uint8List.fromList(List.generate(32, (i) => i)),
      createdAt: DateTime(2024, 5, 1),
    );

void main() {
  group('SecurityOverviewService', () {
    late ProviderContainer container;
    late SecurityOverviewService service;
    late FakeIdentityService identity;
    late FakeBiometricService biometric;
    late FakeEncryptionService encryption;
    late FakeAuditLogService auditLog;
    late FakeSecureStorageService storage;
    late FakeIpfsService ipfs;
    late FakeProofOfRetrievabilityService porService;
    late AppDatabase db;

    setUp(() {
      identity = FakeIdentityService();
      biometric = FakeBiometricService();
      encryption = FakeEncryptionService();
      auditLog = FakeAuditLogService();
      storage = FakeSecureStorageService();
      ipfs = FakeIpfsService();
      porService = FakeProofOfRetrievabilityService();
      db = AppDatabase();

      container = ProviderContainer(
        overrides: [
          identityServiceProvider.overrideWithValue(identity),
          biometricServiceProvider.overrideWithValue(biometric),
          encryptionServiceProvider.overrideWithValue(encryption),
          auditLogServiceProvider.overrideWithValue(auditLog),
          secureStorageServiceProvider.overrideWithValue(storage),
          ipfsServiceProvider.overrideWithValue(ipfs),
          por.proofOfRetrievabilityServiceProvider
              .overrideWithValue(porService),
          databaseProvider.overrideWithValue(db),
        ],
      );
      service = container.read(securityOverviewServiceProvider);
      addTearDown(() async {
        await db.close();
        container.dispose();
      });
    });

    test('getOverview returns score 100 when fully secured', () async {
      identity.setIdentity(_makeIdentity());
      biometric.available = true;
      await storage.write('secure_mode_enabled', 'true');
      await db.insertManifest({
        'uuid': 'u1',
        'title': 'Encrypted doc',
        'lastUpdated': DateTime(2024, 5, 1),
        'isEncrypted': true,
      });

      final overview = await service.getOverview();
      expect(overview.score, 100);
      expect(overview.encryptionEnabled, isTrue);
    });

    test('getOverview is 50 baseline with no extras', () async {
      identity.setIdentity(null);
      biometric.available = false;
      final overview = await service.getOverview();
      expect(overview.score, 50);
      expect(overview.encryptionEnabled, isFalse);
    });

    test('getCurrentAlerts lists identity and encryption warnings', () async {
      identity.setIdentity(null);
      biometric.available = false;
      final alerts = await service.getCurrentAlerts();
      final messages = alerts.map((a) => a.message).toList();
      expect(
        messages,
        contains('No identity configured; generate a keypair to sign content.'),
      );
      expect(
        messages,
        contains(
          'No encrypted content found. Consider encrypting sensitive documents.',
        ),
      );
    });

    test('watchSecurityAlerts emits current alerts', () async {
      identity.setIdentity(null);
      final list = await service.watchSecurityAlerts().first;
      expect(list, isA<List<SecurityAlert>>());
      expect(list.isNotEmpty, isTrue);
    });

    test('getActiveIdentities returns one keypair', () async {
      identity.setIdentity(_makeIdentity());
      final identities = await service.getActiveIdentities();
      expect(identities.length, 1);
      expect(identities.first.id, '11111111');
      expect(identities.first.did, 'did:alex:11111111');
    });

    test('generateNewKeypair supports Ed25519 only', () async {
      final keypair = await service.generateNewKeypair(KeyType.ed25519);
      expect(keypair.type, KeyType.ed25519);
      expect(identity._generated, 1);

      expect(
        () async => await service.generateNewKeypair(KeyType.secp256k1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('exportPrivateKey succeeds and validates key id', () async {
      identity.setIdentity(_makeIdentity());
      final exported = await service.exportPrivateKey('11111111', 'p@ss');
      expect(base64Decode(exported), [1, 2, 3]);

      expect(
        () async => await service.exportPrivateKey('wrong-id', 'p@ss'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('resolveDid resolves own did:alex and database profiles', () async {
      identity.setIdentity(_makeIdentity());
      final own = await service.resolveDid('did:alex:11111111');
      expect(own.publicKeys, isNotEmpty);

      await db.into(db.userProfiles).insert(
            UserProfilesCompanion(
              publicKey: const Value('did:other'),
              lastActive: Value(DateTime(2024, 5, 1)),
            ),
          );
      final other = await service.resolveDid('did:other');
      expect(other.publicKeys, ['did:other']);

      final unknown = await service.resolveDid('did:unknown');
      expect(unknown.publicKeys, isEmpty);
    });

    test('getDocuments maps manifests and versions', () async {
      await db.insertManifest({
        'uuid': 'u1',
        'title': 'Test doc',
        'lastUpdated': DateTime(2024, 5, 1),
      });
      final manifests = await db.getAllManifests();
      await db.insertVersion({
        'manifestId': manifests.first.id,
        'cid': 'cid-1',
        'sizeBytes': 100,
        'createdData': DateTime(2024, 5, 1),
      });

      final docs = await service.getDocuments();
      expect(docs.length, 1);
      expect(docs.first.cid, 'cid-1');
      expect(docs.first.title, 'Test doc');
    });

    test('getAccessPolicies / grantAccess / revokeAccess round-trip', () async {
      expect(await service.getAccessPolicies('cid-1'), isEmpty);

      await service.grantAccess('cid-1', 'did:alex:a');
      await service.grantAccess('cid-1', 'did:alex:b');
      await service.grantAccess('cid-1', 'did:alex:a');

      final policies = await service.getAccessPolicies('cid-1');
      expect(policies.length, 2);

      await service.revokeAccess('cid-1', 'did:alex:a');
      final after = await service.getAccessPolicies('cid-1');
      expect(after.length, 1);
      expect(after.first.peerDid, 'did:alex:b');
      expect(auditLog.lastAction, 'revoke_access');
    });

    test('getRecentAuditLogs delegates to audit log service', () async {
      auditLog.logs = [
        AuditLog(
          event: 'grant_access',
          actor: 'a',
          timestamp: DateTime(2024, 5, 1),
          status: 'Success',
        ),
      ];
      final logs = await service.getRecentAuditLogs(5);
      expect(logs, auditLog.logs);
    });

    test('getCurrentAlerts counts recent denied logs', () async {
      identity.setIdentity(_makeIdentity());
      biometric.available = false;
      await storage.write('secure_mode_enabled', 'true');
      auditLog.logs = [
        AuditLog(
          event: 'auth',
          actor: 'x',
          timestamp: DateTime(2024, 5, 1),
          status: 'denied',
        ),
      ];
      final alerts = await service.getCurrentAlerts();
      final messages = alerts.map((a) => a.message).toList();
      expect(messages, contains('Recent access denials detected (1).'));
    });

    test('issueChallenge creates a PoR challenge', () async {
      final challenge = await service.issueChallenge('cid-1', 'peer-1');
      expect(challenge.cid, 'cid-1');
      expect(challenge.peerId, 'peer-1');
    });

    test('verifyChallenge returns PoR verification result', () async {
      final challenge = await service.issueChallenge('cid-1', 'peer-1');
      ipfs.seedFile('cid-1', Uint8List.fromList([0, 1, 2]));
      final verified = await service.verifyChallenge(challenge);
      expect(verified, isTrue);
    });
  });
}
