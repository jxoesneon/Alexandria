import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/encryption_service.dart';

void main() {
  group('EncryptionService (AES-256-GCM) Tests', () {
    late EncryptionService encryption;

    setUp(() {
      encryption = EncryptionService();
    });

    test('generates secret key and serializes to/from bytes', () async {
      final key = await encryption.generateKey();
      final bytes = await encryption.keyToBytes(key);

      expect(bytes.length, 32); // 256 bits

      final restoredKey = await encryption.keyFromBytes(bytes);
      final restoredBytes = await encryption.keyToBytes(restoredKey);
      expect(restoredBytes, equals(bytes));
    });

    test('encrypts and decrypts payload correctly (round-trip)', () async {
      final key = await encryption.generateKey();
      final plaintext = Uint8List.fromList(
          'Censorship-Resistant Preserved Knowledge'.codeUnits);

      final ciphertext = await encryption.encryptData(plaintext, key);
      expect(ciphertext, isNot(equals(plaintext)));

      final decrypted = await encryption.decryptData(ciphertext, key);
      expect(decrypted, equals(plaintext));
    });

    test('fails decryption with mismatched secret key', () async {
      final key1 = await encryption.generateKey();
      final key2 = await encryption.generateKey();
      final plaintext = Uint8List.fromList('Secret Data'.codeUnits);

      final ciphertext = await encryption.encryptData(plaintext, key1);
      expect(() async => await encryption.decryptData(ciphertext, key2),
          throwsA(anything));
    });
  });
}
