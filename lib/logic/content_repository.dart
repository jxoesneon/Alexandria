import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../data/database.dart';
import '../models/workspace_models.dart';
import '../services/cid_service.dart';
import '../services/encryption_service.dart';
import '../services/identity_service.dart';
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
  CidService get _cidService => _ref.read(cidServiceProvider);
  IdentityService get _identity => _ref.read(identityServiceProvider);

  /// Maximum versions (editions) allowed per manifest — anti-fragmentation cap.
  static const int maxVersionsPerManifest = 20;

  /// Minimum payload size for a standalone version row.
  static const int minVersionBytes = 64;

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
      final (pubkey, sig) = await _signVersion(uuid, cid);
      await db.insertVersion({
        'manifestId': manifest.id,
        'cid': cid,
        'language': 'en',
        'format': fileFormat,
        'sizeBytes': size,
        'createdData': DateTime.now(),
        'publisherPubkey': pubkey,
        'signature': sig,
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

    // Integrity anchor: the CID *is* the SHA-256 of the payload. Any peer
    // serving altered bytes produces a different digest and is rejected here,
    // before decryption or rendering.
    if (rawBytes.isEmpty || !_cidService.verifyContent(cid, rawBytes)) {
      throw StateError(
          'CID integrity check failed for $cid: payload hash mismatch or content unavailable');
    }

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

  /// Canonical signing payload binding a version CID to its parent manifest.
  static Uint8List versionSigningPayload(String manifestUuid, String cid) {
    return Uint8List.fromList(
        utf8.encode('alexandria:version:v1:$manifestUuid:$cid'));
  }

  /// Adds a new content-addressed file payload as an edition/version to an
  /// existing manifest. The version record is signed with the local node's
  /// Ed25519 identity so authenticity is verifiable offline.
  ///
  /// Anti-gaming gates (ALX-010):
  ///  - [maxVersionsPerManifest] cap blocks fragmentation attacks.
  ///  - [minVersionBytes] floor blocks dust/empty edition rows.
  ///  - Payloads that are byte-fragments of an existing version are flagged
  ///    (not rejected — visibility is a display concern, never a gate).
  Future<String> addContentVersion({
    required String manifestUuid,
    required Uint8List fileData,
    String language = 'en',
    String format = 'bin',
  }) async {
    if (fileData.length < minVersionBytes) {
      throw ArgumentError(
          'Version payload below minimum size ($minVersionBytes bytes)');
    }
    final manifest = await getManifestByUuid(manifestUuid);
    if (manifest == null) {
      throw ArgumentError('Manifest not found for UUID: $manifestUuid');
    }
    final db = _ref.read(databaseProvider);
    final existing = await db.getVersionsForManifest(manifest.id);
    if (existing.length >= maxVersionsPerManifest) {
      throw StateError(
          'Manifest $manifestUuid already has $maxVersionsPerManifest versions (fragmentation cap)');
    }

    // Fragment detection: a payload that is a verbatim substring of an
    // existing edition is a split-attack artifact, not a new edition.
    String? flaggedReason;
    for (final v in existing) {
      final bytes = <int>[];
      await for (final chunk in _ipfs.getFile(v.cid)) {
        bytes.addAll(chunk);
      }
      if (_isSubsequence(fileData, bytes)) {
        flaggedReason = 'suspect-fragment-of:${v.cid}';
        break;
      }
    }

    final cid = await _ipfs.addFile(fileData);
    final (publisherPubkey, signature) = await _signVersion(manifestUuid, cid);

    await db.insertVersion({
      'manifestId': manifest.id,
      'cid': cid,
      'language': language,
      'format': format,
      'sizeBytes': fileData.length,
      'createdData': DateTime.now(),
      'publisherPubkey': publisherPubkey,
      'signature': signature,
      'flaggedReason': flaggedReason,
    });
    return cid;
  }

  /// Computed integrity probe for the Safe Harbor panel (ALX-010): re-hashes
  /// the stored payload against its CID digest and verifies the edition's
  /// Ed25519 signature. Reports only checks that actually ran — never asserts.
  Future<ContentIntegrityReport> probeContentIntegrity(String cid) async {
    final chunks = <int>[];
    await for (final chunk in _ipfs.getFile(cid)) {
      chunks.addAll(chunk);
    }
    final hashOk = chunks.isNotEmpty &&
        _cidService.verifyContent(cid, Uint8List.fromList(chunks));

    bool? signatureOk;
    String? flagged;
    String? publisher;
    final db = _ref.read(databaseProvider);
    final versionMap = await db.getVersionByCid(cid);
    if (versionMap != null) {
      flagged = versionMap['flaggedReason'] as String?;
      publisher = versionMap['publisherPubkey'] as String?;
      final signature = versionMap['signature'] as String?;
      if (publisher != null && signature != null) {
        final manifestId = versionMap['manifestId'] as int?;
        final manifests = await db.getAllManifests();
        final manifestUuid = manifests
            .where((m) => m.id == manifestId)
            .map((m) => m.uuid)
            .firstOrNull;
        if (manifestUuid != null) {
          signatureOk = await verifyVersionSignature(
            manifestUuid: manifestUuid,
            cid: cid,
            publisherPubkey: publisher,
            signature: signature,
          );
        }
      }
    }

    return ContentIntegrityReport(
      cid: cid,
      payloadHashOk: hashOk,
      signatureValid: signatureOk,
      flaggedReason: flagged,
      publisherPubkey: publisher,
    );
  }

  /// Signs the manifest∥CID binding with the local Ed25519 identity.
  /// Returns (null, null) when no identity exists (legacy/unsigned).
  Future<(String?, String?)> _signVersion(
      String manifestUuid, String cid) async {
    final identity = await _identity.getIdentity();
    if (identity == null) return (null, null);
    final sig = base64Encode(
        await _identity.sign(versionSigningPayload(manifestUuid, cid)));
    return (identity.publicKeyBase58, sig);
  }

  /// Verifies a version record's Ed25519 signature against the manifest/CID
  /// binding. Returns false for unsigned or tampered records.
  Future<bool> verifyVersionSignature({
    required String manifestUuid,
    required String cid,
    required String? publisherPubkey,
    required String? signature,
  }) async {
    if (publisherPubkey == null || signature == null) return false;
    try {
      final pubkeyBytes =
          AlexandriaIdentity.decodePublicKeyBase58(publisherPubkey);
      return await _identity.verifySignature(
        versionSigningPayload(manifestUuid, cid),
        base64Decode(signature),
        pubkeyBytes,
      );
    } catch (_) {
      return false;
    }
  }

  static bool _isSubsequence(Uint8List needle, List<int> haystack) {
    if (needle.isEmpty || needle.length > haystack.length) return false;
    final first = needle[0];
    for (var i = 0; i <= haystack.length - needle.length; i++) {
      if (haystack[i] != first) continue;
      var j = 1;
      while (j < needle.length && haystack[i + j] == needle[j]) {
        j++;
      }
      if (j == needle.length) return true;
    }
    return false;
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

/// Result of [ContentRepository.probeContentIntegrity] — the computed state
/// behind the Safe Harbor panel. Every field reflects a check that ran;
/// [signatureValid] is null for legacy unsigned version records.
class ContentIntegrityReport {
  final String cid;

  /// True iff the stored payload's SHA-256 equals the digest embedded in [cid].
  final bool payloadHashOk;

  /// Ed25519 signature check over the manifest∥CID binding.
  /// `true` = verified, `false` = signature present but invalid,
  /// `null` = unsigned (legacy record).
  final bool? signatureValid;

  /// Non-null when the version was flagged (e.g. `suspect-fragment-of:<cid>`).
  final String? flaggedReason;

  /// Base58 publisher public key, when the record is signed.
  final String? publisherPubkey;

  const ContentIntegrityReport({
    required this.cid,
    required this.payloadHashOk,
    required this.signatureValid,
    this.flaggedReason,
    this.publisherPubkey,
  });
}
