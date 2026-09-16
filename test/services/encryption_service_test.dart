import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/encryption_service.dart';

void main() {
  group('EncryptionService', () {
    late EncryptionService service;

    setUp(() {
      service = EncryptionService();
    });

    test('generateKey returns a 256-bit secret key', () async {
      final key = await service.generateKey();
      final bytes = await service.keyToBytes(key);
      expect(bytes.length, equals(32));
    });

    test('keyFromBytes restores a key', () async {
      final key = await service.generateKey();
      final bytes = await service.keyToBytes(key);
      final restored = await service.keyFromBytes(bytes);
      final restoredBytes = await service.keyToBytes(restored);
      expect(restoredBytes, equals(bytes));
    });

    test('encryptData and decryptData round-trip', () async {
      final key = await service.generateKey();
      final plaintext = Uint8List.fromList('hello world'.codeUnits);
      final cipher = await service.encryptData(plaintext, key);
      expect(cipher, isNot(equals(plaintext)));
      final decrypted = await service.decryptData(cipher, key);
      expect(decrypted, equals(plaintext));
    });

    test('decryptData fails with the wrong key', () async {
      final key1 = await service.generateKey();
      final key2 = await service.generateKey();
      final plaintext = Uint8List.fromList('secret'.codeUnits);
      final cipher = await service.encryptData(plaintext, key1);
      // decryptData now returns null on AEAD authentication failure
      // (wrong key / tampered box) instead of throwing — the security
      // contract is unchanged: a wrong key NEVER yields plaintext.
      expect(await service.decryptData(cipher, key2), isNull);
    });

    test('encryptForPeer produces deterministic key from public key', () async {
      final data = Uint8List.fromList('peer data'.codeUnits);
      final cipher1 = await service.encryptForPeer(data, 'did:alex:peer#1');
      final cipher2 = await service.encryptForPeer(data, 'did:alex:peer#1');
      expect(cipher1, isNot(equals(data)));
      expect(cipher2, isNot(equals(data)));
    });

    test('encryptForPeer produces different ciphertext for different peers',
        () async {
      final data = Uint8List.fromList('same input'.codeUnits);
      final cipherA = await service.encryptForPeer(data, 'did:alex:peerA');
      final cipherB = await service.encryptForPeer(data, 'did:alex:peerB');
      expect(cipherA, isNot(equals(cipherB)));
    });

    test('encryptionServiceProvider is readable', () {
      final container = ProviderContainer();
      final service = container.read(encryptionServiceProvider);
      expect(service, isA<EncryptionService>());
      container.dispose();
    });
  });
}
