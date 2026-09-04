import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../data/database.dart';
import '../models/workspace_models.dart';
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
    List<String>? tags,
    String? category,
    String? format,
    Map<String, dynamic>? extraMetadata,
  }) async {
    final uuid = const Uuid().v4();
    await _auditLogger.log('create_content_start',
        details: 'UUID: $uuid, Encrypted: $isEncrypted');

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
    final size = uploadPayload.length;
    final fileFormat = format ?? extraMetadata?['format'] as String? ?? 'bin';
    final fileCategory = category ?? fileFormat;
    final metadataJson = jsonEncode(extraMetadata ?? <String, dynamic>{});

    await _auditLogger.log('create_content_success',
        details: 'UUID: $uuid, CID: $cid');

    final db = _ref.read(databaseProvider);
    await db.insertManifest({
      'uuid': uuid,
      'title': title,
      'lastUpdated': DateTime.now(),
      'author': author,
      'description': description,
      'category': fileCategory,
      'tags': tags?.join(','),
      'metadata': metadataJson,
      'isEncrypted': isEncrypted,
      'encryptionKey': wrappedKey,
    });

    final manifest = await getManifestByUuid(uuid);
    if (manifest != null) {
      await db.insertVersion({
        'manifestId': manifest.id,
        'cid': cid,
        'language': 'en',
        'format': fileFormat,
        'sizeBytes': size,
        'createdData': DateTime.now(),
      });
    }

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

  Future<List<ContentManifest>> getContentPage(
      {required int page, required int pageSize}) async {
    final db = _ref.read(databaseProvider);
    final all = await db.getAllManifests();
    final start = page * pageSize;
    if (start >= all.length) return [];
    final end = start + pageSize;
    return all.sublist(start, end > all.length ? all.length : end);
  }

  Future<Uint8List> downloadContent(String cid, {String? keyBase64}) async {
    return retrieveContent(cid, dekBase64: keyBase64);
  }

  Future<void> addVersion(
      String uuid, String path, String language, String format,
      {int sizeBytes = 0}) async {
    final manifest = await getManifestByUuid(uuid);
    if (manifest == null) return;
    final db = _ref.read(databaseProvider);
    await db.insertVersion({
      'manifestId': manifest.id,
      'cid': path,
      'language': language,
      'format': format,
      'sizeBytes': sizeBytes,
      'createdData': DateTime.now(),
    });
  }

  Future<List<ContentManifest>> getAllManifests() async {
    final db = _ref.read(databaseProvider);
    return db.select(db.contentManifests).get();
  }

  Stream<List<ContentManifest>> watchAllManifests() {
    final db = _ref.read(databaseProvider);
    return db.select(db.contentManifests).watch();
  }

  Future<ContentManifest?> getManifestByUuid(String uuid) async {
    final db = _ref.read(databaseProvider);
    final query = db.select(db.contentManifests)
      ..where((m) => m.uuid.equals(uuid));
    return query.getSingleOrNull();
  }

  Future<void> saveManifest(ContentManifest manifest) async {
    final db = _ref.read(databaseProvider);
    await db.update(db.contentManifests).replace(manifest);
  }

  Future<List<Note>> getAllNotes() async {
    final rows = await getAllManifests();
    return rows
        .where((m) => m.category == 'note')
        .map(_noteFromManifest)
        .toList();
  }

  Future<Note> getNoteByUuid(String uuid) async {
    final manifest = await getManifestByUuid(uuid);
    if (manifest == null) throw Exception('Note not found');
    return _noteFromManifest(manifest);
  }

  Future<void> saveNote(Note note) async {
    final db = _ref.read(databaseProvider);
    final existing = await getManifestByUuid(note.id);
    if (existing == null) {
      final meta = <String, dynamic>{
        'content': note.content,
        'status': note.status.name,
      };
      await db.insertManifest({
        'uuid': note.id,
        'title': note.title,
        'lastUpdated': DateTime.now(),
        'author': note.author.isEmpty ? null : note.author,
        'description': note.summary.isEmpty ? null : note.summary,
        'category': 'note',
        'tags': note.tags.isEmpty ? null : note.tags.join(','),
        'metadata': jsonEncode(meta),
        'isEncrypted': false,
      });
    } else {
      final meta = _decodeMetadata(existing.metadata);
      meta['content'] = note.content;
      meta['status'] = note.status.name;
      final updated = existing.copyWith(
        title: note.title,
        author: Value<String?>(note.author.isEmpty ? null : note.author),
        description: Value<String?>(note.summary.isEmpty ? null : note.summary),
        tags: Value<String?>(note.tags.isEmpty ? null : note.tags.join(',')),
        metadata: Value<String?>(jsonEncode(meta)),
        lastUpdated: DateTime.now(),
      );
      await db.update(db.contentManifests).replace(updated);
    }
  }

  Future<String> commitNote(Note note) async {
    await saveNote(note);
    final bytes = Uint8List.fromList(utf8.encode(note.content));
    final cid = await _ipfs.addFile(bytes);
    final manifest = await getManifestByUuid(note.id);
    if (manifest == null) throw Exception('Manifest not found after save');
    final db = _ref.read(databaseProvider);
    await db.insertVersion({
      'manifestId': manifest.id,
      'cid': cid,
      'language': 'en',
      'format': 'md',
      'sizeBytes': bytes.length,
      'createdData': DateTime.now(),
    });
    return cid;
  }

  Stream<List<Annotation>> watchAnnotations(String docId) {
    return watchAllManifests().map((manifests) {
      final manifest = manifests
          .cast<ContentManifest?>()
          .firstWhere((m) => m?.uuid == docId, orElse: () => null);
      if (manifest == null) return <Annotation>[];
      return _annotationsFromManifest(manifest);
    });
  }

  Future<void> addAnnotation(String docId, Annotation annotation) async {
    final db = _ref.read(databaseProvider);
    final manifest = await getManifestByUuid(docId);
    if (manifest == null) throw Exception('Document not found');
    final meta = _decodeMetadata(manifest.metadata);
    final annotations = ((meta['annotations'] ?? []) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .toList();
    annotations.add({
      'id': annotation.id,
      'docId': annotation.docId,
      'text': annotation.text,
      'quote': annotation.quote,
      'author': annotation.author,
      'createdAt': annotation.createdAt.toIso8601String(),
    });
    meta['annotations'] = annotations;
    final updated = manifest.copyWith(
      metadata: Value<String?>(jsonEncode(meta)),
      lastUpdated: DateTime.now(),
    );
    await db.update(db.contentManifests).replace(updated);
  }

  static Map<String, dynamic> _decodeMetadata(String? raw) {
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Non-JSON metadata is treated as empty.
    }
    return <String, dynamic>{};
  }

  static Note _noteFromManifest(ContentManifest m) {
    final meta = _decodeMetadata(m.metadata);
    final statusName = meta['status'] as String? ?? 'draft';
    final status = NoteStatus.values.byName(statusName);
    final tags = <String>[];
    if (m.tags != null && m.tags!.isNotEmpty) {
      try {
        tags.addAll((jsonDecode(m.tags!) as List<dynamic>).cast<String>());
      } catch (_) {
        tags.addAll(
            m.tags!.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty));
      }
    }
    return Note(
      id: m.uuid,
      title: m.title,
      author: m.author ?? '',
      tags: tags,
      summary: m.description ?? '',
      content: meta['content'] as String? ?? '',
      status: status,
    );
  }

  static List<Annotation> _annotationsFromManifest(ContentManifest m) {
    final meta = _decodeMetadata(m.metadata);
    final list = (meta['annotations'] as List<dynamic>?) ?? [];
    return list.map((e) {
      final map = e as Map<String, dynamic>;
      return Annotation(
        id: map['id'] as String? ?? '',
        docId: map['docId'] as String? ?? m.uuid,
        text: map['text'] as String? ?? '',
        quote: map['quote'] as String?,
        author: map['author'] as String? ?? 'Reader',
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
    }).toList();
  }
}
