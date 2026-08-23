import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final encryptionServiceProvider = Provider((ref) => EncryptionService());

class EncryptionService {
  final AesGcm _algorithm = AesGcm.with256Bits();

  Future<SecretKey> generateKey() async {
    return await _algorithm.newSecretKey();
  }

  Future<List<int>> keyToBytes(SecretKey key) async {
    return await key.extractBytes();
  }

  Future<SecretKey> keyFromBytes(List<int> bytes) async {
    return SecretKey(bytes);
  }

  Future<Uint8List> encryptData(Uint8List plaintext, SecretKey key) async {
    final secretBox = await _algorithm.encrypt(plaintext, secretKey: key);
    return Uint8List.fromList(secretBox.concatenation());
  }

  Future<Uint8List> decryptData(Uint8List cipherData, SecretKey key) async {
    final secretBox = SecretBox.fromConcatenation(
      cipherData,
      nonceLength: _algorithm.nonceLength,
      macLength: _algorithm.macAlgorithm.macLength,
    );
    final decrypted = await _algorithm.decrypt(secretBox, secretKey: key);
    return Uint8List.fromList(decrypted);
  }
}
