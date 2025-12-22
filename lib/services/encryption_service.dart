import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';

final encryptionServiceProvider = Provider((ref) => EncryptionService());

class EncryptionService {
  final _algorithm = AesGcm.with256bits();

  /// Generates a random 256-bit Key.
  Future<SecretKey> generateKey() async {
    return await _algorithm.newSecretKey();
  }

  /// Encrypts data using AES-256-GCM.
  /// Returns: Nonce (12 bytes) || Ciphertext || MAC (16 bytes)
  Future<Uint8List> encryptData(Uint8List data, SecretKey key) async {
    final secretBox = await _algorithm.encrypt(data, secretKey: key);
    return Uint8List.fromList(secretBox.concatenation());
  }

  /// Decrypts data using AES-256-GCM.
  /// Expects: Nonce (12 bytes) || Ciphertext || MAC (16 bytes)
  Future<Uint8List> decryptData(Uint8List encryptedData, SecretKey key) async {
    final secretBox = SecretBox.fromConcatenation(
      encryptedData,
      nonceLength: 12,
      macLength: 16,
    );

    return Uint8List.fromList(
      await _algorithm.decrypt(secretBox, secretKey: key),
    );
  }

  /// Helper to convert raw bytes to SecretKey
  Future<SecretKey> keyFromBytes(List<int> bytes) async {
    return await _algorithm.newSecretKeyFromBytes(bytes);
  }

  /// Helper to get bytes from SecretKey
  Future<List<int>> keyToBytes(SecretKey key) async {
    return await key.extractBytes();
  }
}
