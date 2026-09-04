import 'dart:convert';
import 'dart:typed_data';

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
