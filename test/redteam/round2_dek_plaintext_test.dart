// RED TEAM PoC — ContentRepository.createContent persists the raw AES
// data-encryption key in the PLAINTEXT manifest row.
//
// lib/logic/content_repository.dart:52-81 — when isEncrypted=true the
// DEK is base64'd into `wrappedKey` and written BOTH to secure storage
// ('dek_$uuid', line 57) AND into the content_manifests.encryptionKey
// column (line 80). The database is unencrypted SQLite: anyone who
// reads the manifests table — backup export, sync leak, DB file
// compromise, or the collection-sync metadata path — recovers the key
// and decrypts the "encrypted" CID payload with it. The UI itself does
// exactly this (content_detail_screen.dart:763 passes
// manifest.encryptionKey to downloadContent), so this is the
// functional decryption path, not dead data.
//
// Asserts the SECURE expectation: a plaintext copy of the DEK must
// never sit in the manifests table. Failure marks encryption-at-rest
// theater.
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart';
import 'package:alexandria/logic/content_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('encrypted-content DEK must not be stored in the manifest row',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final repo = container.read(contentRepositoryProvider);
    final db = container.read(databaseProvider);

    final plaintext =
        Uint8List.fromList(utf8.encode('classified scroll contents'));
    final uuid = await repo.createContent(
      title: 'Secret Scroll',
      fileData: plaintext,
      isEncrypted: true,
    );

    final manifest = await repo.getManifestByUuid(uuid);
    expect(manifest, isNotNull);
    expect(manifest!.isEncrypted, isTrue);

    // Attempt the full kill-chain FIRST: take whatever key material the
    // plaintext row carries and use it to decrypt the stored payload.
    final leakedKey = manifest.encryptionKey;
    Uint8List? recovered;
    if (leakedKey != null) {
      final versions = await db.getVersionsForManifest(manifest.id);
      final cid = versions.first.cid;
      recovered = await repo.retrieveContent(cid, dekBase64: leakedKey);
    }

    // SECURE expectation 1: the manifest row must not carry usable key
    // material — the DEK belongs ONLY in secure storage ('dek_$uuid').
    expect(leakedKey, isNull,
        reason:
            'manifest.encryptionKey = "$leakedKey" — a raw base64 DEK '
            'sitting in the unencrypted SQLite manifest row (the same '
            'row metadata sync ships around)');

    // SECURE expectation 2: manifest data alone must not decrypt the
    // payload. Reaching this line means the row DID carry a key.
    expect(recovered, isNull,
        reason:
            'the manifest-row key decrypted the payload end-to-end: '
            '"${recovered == null ? null : utf8.decode(recovered)}" — '
            'encryption-at-rest provides ZERO protection against '
            'anyone who can read the database');
  });
}
