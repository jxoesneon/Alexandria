import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../services/encryption_service.dart';
import '../services/ipfs_service.dart';
import '../services/secure_storage_service.dart';
import '../services/audit_log_service.dart';

final contentRepositoryProvider = Provider((ref) => ContentRepository(ref));

class ContentRepository {
  final Ref _ref;

  ContentRepository(this._ref);

  EncryptionService get _encryption => _ref.read(encryptionServiceProvider);
  IpfsService get _ipfs => _ref.read(ipfsServiceProvider);
  SecureStorageService get _storage => _ref.read(secureStorageServiceProvider);
  AuditLogService get _auditLogger => _ref.read(auditLogServiceProvider);

  Future<String> createContent({
    required String title,
    String? author,
    String? description,
    required Uint8List fileData,
    bool isEncrypted = false,
  }) async {
    final uuid = const Uuid().v4();
    await _auditLogger.log('create_content_start', details: 'UUID: $uuid, Encrypted: $isEncrypted');

    Uint8List uploadPayload = fileData;
    String? wrappedKey;

    if (isEncrypted) {
      final dek = await _encryption.generateKey();
      uploadPayload = await _encryption.encryptData(fileData, dek);
      final rawKeyBytes = await _encryption.keyToBytes(dek);
      wrappedKey = base64Encode(rawKeyBytes);
      await _storage.write('dek_$uuid', wrappedKey);
    }

    final cid = await _ipfs.addFile(uploadPayload);
    await _auditLogger.log('create_content_success', details: 'UUID: $uuid, CID: $cid');
    return uuid;
  }

  Future<Uint8List> retrieveContent(String cid, {String? dekBase64}) async {
    final chunks = <int>[];
    await for (final chunk in _ipfs.getFile(cid)) {
      chunks.addAll(chunk);
    }
    final rawBytes = Uint8List.fromList(chunks);

    if (dekBase64 != null) {
      final key = await _encryption.keyFromBytes(base64Decode(dekBase64));
      return await _encryption.decryptData(rawBytes, key);
    }
    return rawBytes;
  }
}
