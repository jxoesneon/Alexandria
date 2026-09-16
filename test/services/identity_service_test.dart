import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSecureStorage implements SecureStorageService {
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

/// Storage that silently drops the next N writes to chosen keys —
/// simulates the partial-write failure that produced a persisted
/// priv(B)+pub(A) "Franken" keypair.
class _DroppingSecureStorage extends _FakeSecureStorage {
  final Map<String, int> droppedWrites = {};

  void dropNextWrites(String key, int count) => droppedWrites[key] = count;

  @override
  Future<void> write(String key, String value) async {
    final remaining = droppedWrites[key] ?? 0;
    if (remaining > 0) {
      droppedWrites[key] = remaining - 1;
      return; // silently lost
    }
    return super.write(key, value);
  }
}

/// Storage that throws on chosen keys — simulates a write failing
/// mid-sequence (e.g. OS-level keychain error).
class _ThrowingSecureStorage extends _FakeSecureStorage {
  final Map<String, int> failedWrites = {};

  void failNextWrites(String key, int count) => failedWrites[key] = count;

  @override
  Future<void> write(String key, String value) async {
    final remaining = failedWrites[key] ?? 0;
    if (remaining > 0) {
      failedWrites[key] = remaining - 1;
      throw StateError('injected storage failure for $key');
    }
    return super.write(key, value);
  }
}

/// The public key that a stored private key derives to — the invariant
/// that must NEVER be violated in storage.
Future<Uint8List> _derivePublic(Uint8List privateKey) async {
  final keyPair = await Ed25519().newKeyPairFromSeed(privateKey);
  final publicKey = await keyPair.extractPublicKey();
  return Uint8List.fromList(publicKey.bytes);
}

Uint8List _hexDecode(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < hex.length; i += 2) {
    result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }
  return result;
}

String _hexEncode(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Asserts the stored private key actually derives the stored public
/// key — the invariant the "Franken keypair" bug violated.
Future<void> _expectCoherentStoredPair(Map<String, String> data) async {
  final privHex = data['alexandria_identity_private_key'];
  final pubHex = data['alexandria_identity_public_key'];
  expect(privHex, isNotNull, reason: 'private key missing from storage');
  expect(pubHex, isNotNull, reason: 'public key missing from storage');
  final derived = await _derivePublic(_hexDecode(privHex!));
  expect(
    derived,
    equals(_hexDecode(pubHex!)),
    reason: 'stored private key does not derive the stored public key',
  );
}

void main() {
  group('IdentityService', () {
    late _FakeSecureStorage storage;
    late IdentityService service;

    setUp(() {
      storage = _FakeSecureStorage();
      service = IdentityService(storage);
    });

    test('hasIdentity returns false when no keys exist', () async {
      expect(await service.hasIdentity(), isFalse);
    });

    test('getIdentity returns null when no keys exist', () async {
      expect(await service.getIdentity(), isNull);
    });

    test('generateIdentity stores and returns an identity', () async {
      final identity = await service.generateIdentity();

      expect(identity.publicKey, isNotEmpty);
      expect(identity.privateKey, isNotEmpty);
      expect(identity.publicKeyBase58, isNotEmpty);
      expect(identity.shortId, hasLength(8));
      expect(await service.hasIdentity(), isTrue);
    });

    test('getIdentity returns cached identity', () async {
      final first = await service.generateIdentity();
      final second = await service.getIdentity();
      expect(second, same(first));
    });

    test('createIdentityProof signs a timestamped message', () async {
      await service.generateIdentity();
      final proof = await service.createIdentityProof();

      expect(proof.message, startsWith('Alexandria Identity Proof:'));
      expect(proof.signature, isNotEmpty);
      expect(proof.publicKey, isNotEmpty);
      expect(
          proof.timestamp
              .isBefore(DateTime.now().add(const Duration(seconds: 1))),
          isTrue);
      expect(proof.toJson(), containsPair('message', proof.message));
    });

    test('verifyIdentityProof accepts a valid proof', () async {
      await service.generateIdentity();
      final proof = await service.createIdentityProof();
      expect(await service.verifyIdentityProof(proof), isTrue);
    });

    test('verifyIdentityProof rejects a tampered proof', () async {
      await service.generateIdentity();
      final proof = await service.createIdentityProof();
      final tampered = IdentityProof(
        message: proof.message,
        signature: Uint8List.fromList(List.filled(proof.signature.length, 0)),
        publicKey: proof.publicKey,
        timestamp: proof.timestamp,
      );
      expect(await service.verifyIdentityProof(tampered), isFalse);
    });

    test('sign and verifySignature round-trip', () async {
      await service.generateIdentity();
      final data = Uint8List.fromList(utf8.encode('hello'));
      final signature = await service.sign(data);
      final identity = await service.getIdentity();
      expect(
          await service.verifySignature(data, signature, identity!.publicKey),
          isTrue);
    });

    test('importIdentity stores, caches, and returns the imported keypair',
        () async {
      final keyPair = await Ed25519().newKeyPair();
      final publicKey = await keyPair.extractPublicKey();
      final seed = Uint8List.fromList(await keyPair.extractPrivateKeyBytes());

      final imported = await service.importIdentity(seed);
      expect(imported.privateKey, equals(seed));
      expect(imported.publicKey, equals(Uint8List.fromList(publicKey.bytes)));

      // The cache is refreshed atomically — no stale identity.
      expect(await service.getIdentity(), same(imported));
      expect(await service.hasIdentity(), isTrue);
    });

    test('importIdentity replaces a previously cached identity', () async {
      final first = await service.generateIdentity();

      final keyPair = await Ed25519().newKeyPair();
      final publicKey = await keyPair.extractPublicKey();
      final seed = Uint8List.fromList(await keyPair.extractPrivateKeyBytes());

      final imported = await service.importIdentity(seed);
      expect(imported.publicKey, isNot(equals(first.publicKey)));

      final current = await service.getIdentity();
      expect(current!.publicKey, equals(Uint8List.fromList(publicKey.bytes)));
      expect(current.privateKey, equals(seed));
    });

    test('reloadIdentity clears the cache and re-reads storage', () async {
      final identity = await service.generateIdentity();
      expect(await service.getIdentity(), same(identity));

      await service.reloadIdentity();
      final reloaded = await service.getIdentity();
      expect(reloaded, isNot(same(identity)));
      expect(reloaded!.publicKey, equals(identity.publicKey));
      expect(reloaded.privateKey, equals(identity.privateKey));
    });

    test('importIdentity defensively copies the caller\'s seed buffer',
        () async {
      final keyPair = await Ed25519().newKeyPair();
      final publicKey = await keyPair.extractPublicKey();
      final seed = Uint8List.fromList(await keyPair.extractPrivateKeyBytes());
      final seedSnapshot = Uint8List.fromList(seed);

      final imported = await service.importIdentity(seed);
      expect(imported.privateKey, equals(seedSnapshot));

      // Mutating the caller's buffer afterwards must not corrupt the
      // stored or cached identity.
      seed.fillRange(0, seed.length, 0xAA);
      final current = await service.getIdentity();
      expect(current!.privateKey, equals(seedSnapshot));
      expect(current.publicKey, equals(Uint8List.fromList(publicKey.bytes)));
    });

    test(
        'concurrent importIdentity + getIdentity never observe a '
        'mixed keypair', () async {
      final identityA = await service.generateIdentity();
      expect(
        await _derivePublic(identityA.privateKey),
        equals(identityA.publicKey),
      );

      final keyPairB = await Ed25519().newKeyPair();
      final publicKeyB =
          Uint8List.fromList((await keyPairB.extractPublicKey()).bytes);
      final seedB = Uint8List.fromList(await keyPairB.extractPrivateKeyBytes());

      // Fire a cold-ish read in the middle of the import — every
      // result must be a coherent pair (A before, B after), never a
      // priv/pub mix.
      final results = await Future.wait([
        service.importIdentity(seedB),
        for (var i = 0; i < 8; i++) service.getIdentity(),
      ]);

      final imported = results.first as AlexandriaIdentity;
      expect(imported.publicKey, equals(publicKeyB));

      for (final identity in results.skip(1)) {
        if (identity == null) continue;
        expect(
          await _derivePublic(identity.privateKey),
          equals(identity.publicKey),
          reason: 'observed a private key that does not derive the '
              'reported public key',
        );
      }

      final current = await service.getIdentity();
      expect(current!.publicKey, equals(publicKeyB));
    });

    test(
        'a dropped key write is retried and never persists a mixed '
        'pair', () async {
      final faulty = _DroppingSecureStorage();
      final svc = IdentityService(faulty);
      final identityA = await svc.generateIdentity();

      final keyPairB = await Ed25519().newKeyPair();
      final publicKeyB =
          Uint8List.fromList((await keyPairB.extractPublicKey()).bytes);
      final seedB = Uint8List.fromList(await keyPairB.extractPrivateKeyBytes());

      // Drop the public-key write once: the first write lands
      // priv(B)+pub(A); post-write verification must catch it and the
      // retry must converge on a coherent B pair.
      faulty.dropNextWrites('alexandria_identity_public_key', 1);
      final imported = await svc.importIdentity(seedB);
      expect(imported.publicKey, equals(publicKeyB));

      await _expectCoherentStoredPair(faulty._data);
      final current = await svc.getIdentity();
      expect(current!.publicKey, equals(publicKeyB));
      expect(
        await _derivePublic(current.privateKey),
        equals(current.publicKey),
      );
      expect(current.publicKey, isNot(equals(identityA.publicKey)));
    });

    test('a throwing mid-sequence write is retried via verification', () async {
      final faulty = _ThrowingSecureStorage();
      final svc = IdentityService(faulty);
      await svc.generateIdentity();

      final keyPairB = await Ed25519().newKeyPair();
      final publicKeyB =
          Uint8List.fromList((await keyPairB.extractPublicKey()).bytes);
      final seedB = Uint8List.fromList(await keyPairB.extractPrivateKeyBytes());

      faulty.failNextWrites('alexandria_identity_private_key', 1);
      final imported = await svc.importIdentity(seedB);
      expect(imported.publicKey, equals(publicKeyB));
      await _expectCoherentStoredPair(faulty._data);
    });

    test(
        'persistent write failure restores the previous identity and '
        'throws', () async {
      final faulty = _DroppingSecureStorage();
      final svc = IdentityService(faulty);
      final identityA = await svc.generateIdentity();

      final keyPairB = await Ed25519().newKeyPair();
      final seedB = Uint8List.fromList(await keyPairB.extractPrivateKeyBytes());

      // Public-key writes can never land: both import attempts fail
      // verification, so the previous coherent pair must be restored.
      faulty.dropNextWrites('alexandria_identity_public_key', 999);
      await expectLater(
        svc.importIdentity(seedB),
        throwsA(isA<StateError>()),
      );

      await _expectCoherentStoredPair(faulty._data);
      final current = await svc.getIdentity();
      expect(current, isNotNull);
      expect(current!.publicKey, equals(identityA.publicKey));
      expect(current.privateKey, equals(identityA.privateKey));
    });

    test(
        'persistent write failure with no prior identity leaves no '
        'partial keys', () async {
      final faulty = _DroppingSecureStorage();
      final svc = IdentityService(faulty);

      final keyPair = await Ed25519().newKeyPair();
      final seed = Uint8List.fromList(await keyPair.extractPrivateKeyBytes());

      faulty.dropNextWrites('alexandria_identity_public_key', 999);
      await expectLater(
        svc.importIdentity(seed),
        throwsA(isA<StateError>()),
      );

      expect(await svc.hasIdentity(), isFalse);
      expect(await svc.getIdentity(), isNull);
      expect(
        faulty._data.containsKey('alexandria_identity_private_key'),
        isFalse,
        reason: 'a private key without its public pair must not persist',
      );
    });

    test(
        'a throwing rollback write still drops the cache and bumps '
        'revision', () async {
      final faulty = _ThrowingSecureStorage();
      final svc = IdentityService(faulty);
      final identityA = await svc.generateIdentity();
      // Prime the cache so the test proves it was dropped.
      expect(await svc.getIdentity(), same(identityA));
      final revisionBefore = svc.revision;

      final keyPairB = await Ed25519().newKeyPair();
      final seedB = Uint8List.fromList(await keyPairB.extractPrivateKeyBytes());

      // Every public-key write throws: both import attempts fail
      // verification AND the rollback restore writes throw too. The
      // StateError must still surface — and the cache must be dropped
      // and the revision bumped even though the rollback never
      // completed.
      faulty.failNextWrites('alexandria_identity_public_key', 999);
      await expectLater(
        svc.importIdentity(seedB),
        throwsA(isA<StateError>()),
      );

      expect(svc.revision, greaterThan(revisionBefore));

      // The cache was dropped: the next read re-resolves from storage
      // and returns a NEW instance of the surviving identity — never
      // the stale cached object. (The throwing pub write aborts each
      // write sequence before the private key lands, so storage still
      // holds the coherent A pair.)
      final reread = await svc.getIdentity();
      expect(reread, isNot(same(identityA)));
      expect(reread!.publicKey, equals(identityA.publicKey));
      expect(reread.privateKey, equals(identityA.privateKey));
      await _expectCoherentStoredPair(faulty._data);
    });

    test(
        'a stored Franken pair is self-healed on read — the private '
        'key is authoritative', () async {
      final identityA = await service.generateIdentity();
      final expectedPublicKey = await _derivePublic(identityA.privateKey);

      // Simulate a legacy corrupt install: the stored public key does
      // NOT match what the stored private key derives (a pre-fix
      // partial write persisted priv(A)+pub(B)).
      final otherKeyPair = await Ed25519().newKeyPair();
      final otherPublicKey =
          Uint8List.fromList((await otherKeyPair.extractPublicKey()).bytes);
      storage._data['alexandria_identity_public_key'] =
          _hexEncode(otherPublicKey);

      // A cold read (fresh service == app restart on a legacy install)
      // must heal storage and serve the derived public key.
      final healedService = IdentityService(storage);
      final healed = await healedService.getIdentity();
      expect(healed, isNotNull);
      expect(healed!.privateKey, equals(identityA.privateKey));
      expect(healed.publicKey, equals(expectedPublicKey));

      // Storage itself was repaired — the derived public key was
      // rewritten over the corrupt value.
      expect(
        storage._data['alexandria_identity_public_key'],
        equals(_hexEncode(expectedPublicKey)),
      );

      // And signatures verify against the reported public key again.
      final data = Uint8List.fromList(utf8.encode('heal me'));
      final signature = await healedService.sign(data);
      expect(
        await healedService.verifySignature(
          data,
          signature,
          healed.publicKey,
        ),
        isTrue,
      );
    });

    test('unhealable stored material reads as no identity', () async {
      await service.generateIdentity();
      // Garbage hex for the private key — cannot decode or derive.
      storage._data['alexandria_identity_private_key'] = 'zz-not-hex';

      final cold = IdentityService(storage);
      expect(await cold.getIdentity(), isNull);
    });

    test('hasIdentity is false on a partially-written store', () async {
      // Private key only — previously reported true while
      // getIdentity() returned null.
      await storage.write('alexandria_identity_private_key', 'abcd');
      expect(await service.hasIdentity(), isFalse);
      expect(await service.getIdentity(), isNull);

      // Public key only.
      await storage.delete('alexandria_identity_private_key');
      await storage.write('alexandria_identity_public_key', 'abcd');
      expect(await service.hasIdentity(), isFalse);

      // priv + pub without the creation stamp is still partial.
      await storage.write('alexandria_identity_private_key', 'abcd');
      expect(await service.hasIdentity(), isFalse);
      expect(await service.getIdentity(), isNull);
    });

    test(
        'importIdentity preserves createdAt when re-importing the same '
        'key', () async {
      final keyPair = await Ed25519().newKeyPair();
      final seed = Uint8List.fromList(await keyPair.extractPrivateKeyBytes());

      final first = await service.importIdentity(seed);

      // Simulate an aged account (governance minAccountAgeDays): roll
      // the stored creation time back, then re-import the same seed —
      // recovery must NOT reset it to now.
      final aged = DateTime(2024, 1, 1);
      storage._data['alexandria_identity_created'] = aged.toIso8601String();
      await service.reloadIdentity();

      final reimported = await service.importIdentity(seed);
      expect(reimported.createdAt, equals(aged));
      expect(
        (await service.getIdentity())!.createdAt,
        equals(aged),
      );
      expect(first.createdAt.isAfter(aged), isTrue);
    });

    test('importIdentity of a DIFFERENT key stamps a fresh createdAt',
        () async {
      final old = DateTime(2020, 1, 1);
      await service.generateIdentity();
      storage._data['alexandria_identity_created'] = old.toIso8601String();
      await service.reloadIdentity();

      final keyPairB = await Ed25519().newKeyPair();
      final seedB = Uint8List.fromList(await keyPairB.extractPrivateKeyBytes());
      final imported = await service.importIdentity(seedB);
      expect(imported.createdAt.isAfter(old), isTrue);
    });

    test(
        'identity replacement clears the mnemonic backup marker; '
        'same-key re-import keeps it', () async {
      const markerKey = SecureStorageKeys.mnemonicBackup;
      final identityA = await service.generateIdentity();
      await storage.write(markerKey, 'hash-of-phrase');

      // Same key re-import: the old phrase still recovers this
      // identity, so the marker survives.
      await service.importIdentity(Uint8List.fromList(identityA.privateKey));
      expect(await storage.containsKey(markerKey), isTrue);

      // Different key: the marker must be cleared.
      final keyPairB = await Ed25519().newKeyPair();
      await service.importIdentity(
        Uint8List.fromList(await keyPairB.extractPrivateKeyBytes()),
      );
      expect(await storage.containsKey(markerKey), isFalse);

      // Rotation also clears it.
      await storage.write(markerKey, 'hash-of-phrase');
      await service.generateIdentity();
      expect(await storage.containsKey(markerKey), isFalse);

      // Deletion too.
      await storage.write(markerKey, 'hash-of-phrase');
      await service.deleteIdentity();
      expect(await storage.containsKey(markerKey), isFalse);
    });

    test('revisionStream emits on every identity mutation', () async {
      final emissions = <int>[];
      final sub = service.revisionStream.listen(emissions.add);
      addTearDown(sub.cancel);

      await service.generateIdentity();
      final keyPair = await Ed25519().newKeyPair();
      await service.importIdentity(
        Uint8List.fromList(await keyPair.extractPrivateKeyBytes()),
      );
      await service.deleteIdentity();

      expect(emissions, equals([1, 2, 3]));
      expect(service.revision, equals(3));
    });

    test('deleteIdentity removes keys and cache', () async {
      await service.generateIdentity();
      expect(await service.hasIdentity(), isTrue);
      await service.deleteIdentity();
      expect(await service.hasIdentity(), isFalse);
      expect(await service.getIdentity(), isNull);
    });

    test('sha256 returns deterministic 32-byte digest', () {
      final data = Uint8List.fromList(utf8.encode('abc'));
      final digest1 = service.sha256(data);
      final digest2 = service.sha256(data);
      expect(digest1, digest2);
      expect(digest1, hasLength(32));
    });

    test('AlexandriaIdentity encodes leading zero bytes correctly', () {
      final key = Uint8List.fromList([0, 0, 1]);
      final identity = AlexandriaIdentity(
        publicKey: key,
        privateKey: key,
        createdAt: DateTime(2024),
      );
      expect(identity.publicKeyBase58.startsWith('11'), isTrue);
    });
  });
}
