import 'dart:typed_data';
import 'package:alexandria/services/encryption_service.dart';

void main() async {
  final encryption = EncryptionService();
  final key = await encryption.generateKey();
  final data = Uint8List(1024 * 1024); // 1 MB

  final sw = Stopwatch()..start();
  final encrypted = await encryption.encryptData(data, key);
  sw.stop();
  print('AES-256-GCM Encryption (1MB): ${sw.elapsedMilliseconds} ms');

  sw.reset();
  sw.start();
  final decrypted = await encryption.decryptData(encrypted, key);
  sw.stop();
  print('AES-256-GCM Decryption (1MB): ${sw.elapsedMilliseconds} ms');
}
