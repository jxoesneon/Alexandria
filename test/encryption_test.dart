import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/encryption_service.dart';
import 'dart:typed_data';

void main() {
  group('EncryptionService', () {
    final service = EncryptionService();

    test('Round trip encrypt/decrypt works', () async {
      final key = await service.generateKey();
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 255, 0, 128]);

      final encrypted = await service.encryptData(data, key);

      // Verify encrypted data is different and includes IV/MAC
      expect(encrypted, isNot(equals(data)));
      expect(
        encrypted.length,
        greaterThan(12 + 16),
      ); // Nonce (12) + MAC (16) at least

      final decrypted = await service.decryptData(encrypted, key);

      expect(decrypted, equals(data));
    });

    test('Decrypting with wrong key fails (authentication error)', () async {
      final key1 = await service.generateKey();
      final key2 = await service.generateKey();
      final data = Uint8List.fromList([10, 20, 30]);

      final encrypted = await service.encryptData(data, key1);

      // AES-GCM uses Poly1305 MAC, so wrong key triggers authentication failure
      expect(
        () async => await service.decryptData(encrypted, key2),
        throwsException,
      );
    });
  });
}
