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

    if (isEncrypted) {
      final dek = await _encryption.generateKey();
      uploadPayload = await _encryption.encryptData(fileData, dek);
      final wrappedKey = base64Encode(await _encryption.keyToBytes(dek));
      // (round-2 red finding) The DEK lives ONLY in flutter_secure_storage
      // under 'dek_$uuid'. It must NEVER be written into the plaintext
      // content_manifests.encryptionKey column — that row ships through
      // collection-sync metadata paths and sits in unencrypted SQLite, so
      // a copy there voids encryption-at-rest for anyone who can read the
      // database file or a backup export.
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
      // encryptionKey deliberately omitted: the manifest row carries no
      // key material. Callers needing the DEK use [contentDekBase64],
      // which reads it back from secure storage.
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

  /// Returns the base64 data-encryption key for [manifestUuid] from
  /// secure storage ('dek_$uuid'), or null for unencrypted/absent
  /// content. This is the ONLY supported way to recover a content DEK —
  /// the manifest row intentionally carries no key material (round-2 red
  /// finding). NEVER exposed to plugins — see [asPluginCapability]
  /// (round-4 red finding).
  Future<String?> contentDekBase64(String manifestUuid) async {
    return _storage.read('dek_$manifestUuid');
  }

  /// (round-4 red finding) The plugin-facing view of this repository.
  ///
  /// The round-3 facade gated which PROVIDER a plugin could read — but
  /// handed over the full [ContentRepository], whose public surface
  /// reaches the keychain transitively (`contentDekBase64` → every
  /// stored DEK; `retrieveManifestContent` → decrypt-anything). A
  /// `contentRead`-scoped plugin could therefore exfiltrate the very
  /// key material the capability list claims is "NEVER" reachable.
  ///
  /// [asPluginCapability] returns a [PluginContentRepository] — a real
  /// [ContentRepository] sharing this instance's [Ref], but with every
  /// key-material/decrypt path closed and mutation methods gated on the
  /// declared `contentWrite` permission. Manifest/metadata reads pass
  /// through unchanged.
  ContentRepository asPluginCapability({required bool canWrite}) =>
      PluginContentRepository(_ref, canWrite: canWrite);

  /// Convenience wrapper: retrieves and decrypts [cid] using the DEK
  /// stored for [manifestUuid]. Keeps UI call sites working now that
  /// `manifest.encryptionKey` no longer carries usable key material.
  Future<Uint8List> retrieveManifestContent(String manifestUuid, String cid) {
    return contentDekBase64(manifestUuid)
        .then((dek) => retrieveContent(cid, dekBase64: dek));
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
      final plain = await _encryption.decryptData(rawBytes, key);
      if (plain == null) {
        throw StateError(
            'DEK failed the AEAD integrity check for $cid — wrong key or tampered ciphertext');
      }
      return plain;
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
    await _writeManifestPreservingKey(manifest);
  }

  /// Writes [m]'s content columns back to its row WITHOUT touching
  /// `encryptionKey`. (round-6 red finding) `update().replace()` copies
  /// every column — so a manifest fetched through
  /// [PluginContentRepository]'s projected view (`encryptionKey: null`)
  /// wrote the hidden column back as NULL, destroying legacy plaintext
  /// DEKs the schema-v6 migration deliberately keeps until they are
  /// rehomed into secure storage. The column is managed ONLY by
  /// `_rehomeLegacyManifestKeys`; no content mutation may write it.
  Future<void> _writeManifestPreservingKey(ContentManifest m) async {
    final db = _ref.read(databaseProvider);
    await (db.update(db.contentManifests)..where((t) => t.id.equals(m.id)))
        .write(ContentManifestsCompanion(
      uuid: Value(m.uuid),
      title: Value(m.title),
      author: Value(m.author),
      description: Value(m.description),
      category: Value(m.category),
      tags: Value(m.tags),
      metadata: Value(m.metadata),
      isEncrypted: Value(m.isEncrypted),
      lastUpdated: Value(m.lastUpdated),
      // encryptionKey: absent — never a writable column on this path.
    ));
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
      await _writeManifestPreservingKey(updated);
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
    await _writeManifestPreservingKey(updated);
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

/// (round-4 red finding) Narrowed plugin-facing view of
/// [ContentRepository].
///
/// Manifest/metadata reads and integrity probes pass through
/// unchanged; every path that reaches key material is closed by
/// construction:
///   * [contentDekBase64] reads `dek_<uuid>` straight out of secure
///     storage — a plugin holding only `contentRead` used it to pull
///     arbitrary content DEKs through the allowlisted repository. It
///     now reads as absent (`null`), matching the facade's "denied
///     reads as absent" convention.
///   * [retrieveManifestContent] auto-decrypts with the stored DEK —
///     refused outright.
///   * Mutation methods ([createContent], [saveManifest], [saveNote],
///     [commitNote], [addAnnotation], [addVersion],
///     [addContentVersion]) require the plugin's declared
///     `contentWrite` permission ([_canWrite]).
///
/// [retrieveContent]/[downloadContent] remain available: they reach no
/// stored key material — decryption there uses only a caller-supplied
/// DEK the plugin already possesses — and the returned bytes are
/// CID-verified ciphertext for encrypted content.
///
/// (round-5 red finding) The round-4 facade narrowed the METHODS but
/// returned the raw Drift rows — whose `encryptionKey` column still
/// holds plaintext DEKs on databases upgraded from pre-round-2 builds
/// (the schema-v6 migration rehomes then NULLs the column, but a row
/// survives until its rehome succeeds). Every manifest read below is
/// therefore projected through [_withoutKeyMaterial]: a plugin-visible
/// manifest NEVER carries the field.
class PluginContentRepository extends ContentRepository {
  final bool _canWrite;

  PluginContentRepository(super._ref, {required bool canWrite})
      : _canWrite = canWrite;

  /// Returns [m] with the legacy key column blanked. cheap identity
  /// fast-path keeps already-clean rows allocation-free.
  static ContentManifest _withoutKeyMaterial(ContentManifest m) =>
      m.encryptionKey == null
          ? m
          : m.copyWith(encryptionKey: const Value<String?>(null));

  @override
  Future<List<ContentManifest>> getAllManifests() async =>
      (await super.getAllManifests()).map(_withoutKeyMaterial).toList();

  @override
  Stream<List<ContentManifest>> watchAllManifests() => super
      .watchAllManifests()
      .map((rows) => rows.map(_withoutKeyMaterial).toList());

  @override
  Future<ContentManifest?> getManifestByUuid(String uuid) async {
    final manifest = await super.getManifestByUuid(uuid);
    return manifest == null ? null : _withoutKeyMaterial(manifest);
  }

  @override
  Future<List<ContentManifest>> getContentPage(
          {required int page, required int pageSize}) async =>
      (await super.getContentPage(page: page, pageSize: pageSize))
          .map(_withoutKeyMaterial)
          .toList();

  void _requireWrite(String op) {
    if (!_canWrite) {
      throw StateError(
          'Plugin capability "$op" requires the contentWrite permission');
    }
  }

  /// Key material is never a plugin capability — reads as absent.
  @override
  Future<String?> contentDekBase64(String manifestUuid) async => null;

  /// The stored-DEK decrypt path is never a plugin capability.
  @override
  Future<Uint8List> retrieveManifestContent(String manifestUuid, String cid) {
    return Future.error(StateError(
        'retrieveManifestContent is not a plugin capability (decrypts '
        'with stored key material)'));
  }

  @override
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
  }) {
    _requireWrite('createContent');
    return super.createContent(
      title: title,
      author: author,
      description: description,
      fileData: fileData,
      isEncrypted: isEncrypted,
      tags: tags,
      category: category,
      format: format,
      extraMetadata: extraMetadata,
    );
  }

  @override
  Future<void> addVersion(
      String uuid, String path, String language, String format,
      {int sizeBytes = 0}) {
    _requireWrite('addVersion');
    return super.addVersion(uuid, path, language, format, sizeBytes: sizeBytes);
  }

  @override
  Future<String> addContentVersion({
    required String manifestUuid,
    required Uint8List fileData,
    String language = 'en',
    String format = 'bin',
  }) {
    _requireWrite('addContentVersion');
    return super.addContentVersion(
      manifestUuid: manifestUuid,
      fileData: fileData,
      language: language,
      format: format,
    );
  }

  @override
  Future<void> saveManifest(ContentManifest manifest) {
    _requireWrite('saveManifest');
    return super.saveManifest(manifest);
  }

  @override
  Future<void> saveNote(Note note) {
    _requireWrite('saveNote');
    return super.saveNote(note);
  }

  @override
  Future<String> commitNote(Note note) {
    _requireWrite('commitNote');
    return super.commitNote(note);
  }

  @override
  Future<void> addAnnotation(String docId, Annotation annotation) {
    _requireWrite('addAnnotation');
    return super.addAnnotation(docId, annotation);
  }
}
