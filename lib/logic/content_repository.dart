import 'dart:convert';
import 'package:alexandria/data/database.dart';
import 'package:alexandria/main.dart';
import 'package:alexandria/services/encryption_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:alexandria/services/audit_log_service.dart';

final contentRepositoryProvider = Provider((ref) => ContentRepository(ref));

class ContentRepository {
  final Ref _ref;

  ContentRepository(this._ref);

  AppDatabase get _db => _ref.read(databaseProvider);
  EncryptionService get _encryption => _ref.read(encryptionServiceProvider);
  IpfsService get _ipfs => _ref.read(ipfsServiceProvider);
  SecureStorageService get _secureStorage =>
      _ref.read(secureStorageServiceProvider);
  AuditLogService get _auditLogger => _ref.read(auditLogServiceProvider);

  // Lazy-load Master Key
  Future<SecretKey> _getMasterKey() async {
    const keyName = 'master_key_v1';
    var base64Key = await _secureStorage.read(keyName);

    if (base64Key == null) {
      debugPrint('Generating new Master Key...');
      final key = await _encryption.generateKey();
      base64Key = base64Encode(await _encryption.keyToBytes(key));
      await _secureStorage.write(keyName, base64Key);
    }

    return await _encryption.keyFromBytes(base64Decode(base64Key));
  }

  // Create a new content manifest and upload files
  Future<String> createContent(
    String title,
    String? description,
    String author, {
    required List<PlatformFile> files,
    String category = 'other',
    Map<String, dynamic>? metadata,
    bool isEncrypted = false,
  }) async {
    final uuid = const Uuid().v4();

    String? storedKeyBase64;
    List<int>? fileKeyBytes;

    // Log intent
    await _auditLogger.log(
      'create_content_start',
      details: 'Title: $title, Encrypted: $isEncrypted',
    );

    if (isEncrypted) {
      // 1. Generate Data Encryption Key (DEK)
      final dek = await _encryption.generateKey();
      fileKeyBytes = await _encryption.keyToBytes(dek);

      // 2. Encrypt DEK with Master Key (Key Wrapping)
      final masterKey = await _getMasterKey();
      final encryptedDek = await _encryption.encryptData(
        Uint8List.fromList(fileKeyBytes),
        masterKey,
      );

      storedKeyBase64 = base64Encode(encryptedDek);
      await _auditLogger.log('encrypt_dek', details: 'UUID: $uuid');
    }

    // 1. Create Manifest
    await _db.insertManifest(
      ContentManifestsCompanion.insert(
        uuid: uuid,
        title: title,
        author: Value(author),
        description: Value(description),
        category: Value(category),
        metadata: Value(metadata != null ? jsonEncode(metadata) : null),
        isEncrypted: Value(isEncrypted),
        encryptionKey: Value(storedKeyBase64),
        lastUpdated: DateTime.now(),
      ),
    );

    // Get Manifest ID
    final manifest = await (_db.select(
      _db.contentManifests,
    )..where((tbl) => tbl.uuid.equals(uuid))).getSingle();

    // 2. Process Files
    for (final file in files) {
      if (file.bytes == null && file.path == null) continue;

      Uint8List data;
      if (file.bytes != null) {
        data = file.bytes!;
      } else {
        data = await File(file.path!).readAsBytes();
      }

      // Encrypt if needed
      if (isEncrypted && fileKeyBytes != null) {
        final key = await _encryption.keyFromBytes(fileKeyBytes);
        data = await _encryption.encryptData(data, key);
      }

      // Add to IPFS
      final cid = await _ipfs.addFile(data);

      // Create Version
      await _db.insertVersion(
        ContentVersionsCompanion.insert(
          manifestId: manifest.id,
          cid: cid,
          language: 'en',
          format: file.extension ?? 'bin',
          sizeBytes: data.length,
          createdData: DateTime.now(),
        ),
      );
    }

    await _auditLogger.log('create_content_success', details: 'UUID: $uuid');
    return uuid;
  }

  // Add a version to content
  Future<void> addVersion(
    String contentUuid,
    String filePath,
    String language,
    String format,
  ) async {
    final manifest = await _db.getManifestByUuid(contentUuid);
    if (manifest == null) throw Exception('Content not found');

    var fileBytes = Uint8List.fromList(List.generate(1024, (i) => i % 255));

    if (manifest.isEncrypted && manifest.encryptionKey != null) {
      final keyBytes = await _unwrapKey(manifest.encryptionKey!);
      final key = await _encryption.keyFromBytes(keyBytes);
      fileBytes = await _encryption.encryptData(fileBytes, key);
    }

    final cid = 'QmMock${const Uuid().v4()}';

    await _db.insertVersion(
      ContentVersionsCompanion.insert(
        cid: cid,
        manifestId: manifest.id,
        language: language,
        format: format,
        sizeBytes: fileBytes.length,
        createdData: DateTime.now(),
      ),
    );

    await _db.updateManifest(manifest.copyWith(lastUpdated: DateTime.now()));
    await _auditLogger.log('add_version', details: 'UUID: $contentUuid');
  }

  Future<List<ContentManifest>> getAllContent() async {
    return _db.getAllManifests();
  }

  Future<List<ContentManifest>> getContentPage({
    required int page,
    int pageSize = 20,
  }) {
    return _db.getManifestsPaged(limit: pageSize, offset: page * pageSize);
  }

  Future<int> getContentCount() {
    return _db.countManifests();
  }

  Future<List<ContentManifest>> searchContent(String query) {
    return _db.searchManifests(query);
  }

  // Download and decrypt content
  Future<Uint8List> downloadContent(String cid, {String? keyBase64}) async {
    final chunks = <int>[];
    await for (final chunk in _ipfs.getFile(cid)) {
      chunks.addAll(chunk);
    }
    final Uint8List bytes = Uint8List.fromList(chunks);

    if (bytes.isEmpty) {
      // handle empty
    }

    if (keyBase64 != null) {
      try {
        await _auditLogger.log('decrypt_content_start', details: 'CID: $cid');
        final keyBytes = await _unwrapKey(keyBase64);
        final key = await _encryption.keyFromBytes(keyBytes);
        final result = await _encryption.decryptData(bytes, key);
        await _auditLogger.log('decrypt_content_success', details: 'CID: $cid');
        return result;
      } catch (e) {
        await _auditLogger.log(
          'decrypt_content_failure',
          details: 'CID: $cid, Error: $e',
        );
        throw Exception('Decryption failed: $e');
      }
    }

    return bytes;
  }

  // Helper to unwrap key (Forward Compatible)
  Future<Uint8List> _unwrapKey(String storedKeyBase64) async {
    final rawBytes = base64Decode(storedKeyBase64);

    // Legacy Check: If 32 bytes, it's a raw AES-256 key
    if (rawBytes.length == 32) {
      // Warning: Legacy key usage
      return rawBytes;
    }

    // Otherwise, assume it's wrapped with Master Key
    final masterKey = await _getMasterKey();
    return await _encryption.decryptData(rawBytes, masterKey);
  }
}
