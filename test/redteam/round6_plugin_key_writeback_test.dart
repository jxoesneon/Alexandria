// RED TEAM PoC — Round-6: PluginContentRepository's key-projection is
// write-back unsafe. The facade blanks `encryptionKey` on every READ
// (`_withoutKeyMaterial`), but the mutation methods it inherits run
// read-modify-write cycles THROUGH that same projected view:
//
//   ContentRepository.saveNote   (content_repository.dart:396-428)
//     existing = getManifestByUuid(note.id)   // virtual → PROJECTED row
//     db.update.replace(existing.copyWith(…)) // encryptionKey: Value(null)
//   ContentRepository.addAnnotation (:459-481) — identical shape
//   ContentRepository.saveManifest  (:377-380) — replace(manifest)
//     writes whatever projected row the caller hands back.
//
// The schema-v6 design contract (database.dart:238-241) is "a row whose
// DEK could not be rehomed KEEPS its key until the secure-storage write
// succeeds — data preservation beats scrub-once." A contentWrite-capable
// plugin violates it: saveNote/addAnnotation/saveManifest against a
// manifest whose legacy DEK is still pending rehome NULLs the column —
// the ONLY copy of that content's key — without ever seeing it.
// On platforms where flutter_secure_storage is permanently unavailable
// (headless, some Linux desktops without a keyring) EVERY legacy row
// lives in this state, so a routine plugin note edit destroys the DEKs
// and the ciphertext becomes unrecoverable.
//
// Asserts the SECURE expectation: a plugin mutation must never clear a
// key column it cannot even read.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart';
import 'package:alexandria/logic/content_repository.dart';
import 'package:alexandria/models/workspace_models.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// Inserts a manifest the way a pre-round-2 database row exists today:
  /// a plaintext DEK still sitting in content_manifests.encryptionKey
  /// because secure storage was unreachable when rehoming ran.
  Future<void> insertLegacyRow(String uuid, String dek) async {
    await db.into(db.contentManifests).insert(
          ContentManifestsCompanion.insert(
            uuid: uuid,
            title: 'Legacy encrypted note',
            lastUpdated: DateTime.now(),
            encryptionKey: Value(dek),
          ),
        );
  }

  Future<String?> rawKey(String uuid) async {
    final row = await (db.select(db.contentManifests)
          ..where((m) => m.uuid.equals(uuid)))
        .getSingle();
    return row.encryptionKey;
  }

  test('plugin saveNote on a legacy manifest erases the unrehomed DEK',
      () async {
    await insertLegacyRow('victim-note', 'b64-legacy-dek-AAA');

    final repo = container.read(contentRepositoryProvider);
    final plugin = repo.asPluginCapability(canWrite: true);
    await plugin.saveNote(const Note(
      id: 'victim-note',
      title: 'edited by plugin',
      author: '',
      tags: [],
      summary: '',
      content: 'new body',
    ));

    expect(await rawKey('victim-note'), isNotNull,
        reason: 'saveNote fetched the manifest through the projected view '
            '(encryptionKey: null) and wrote it back with replace(), '
            'NULLing the legacy DEK column — the last copy of the key '
            'is gone and the ciphertext is unrecoverable.');
  });

  test('plugin addAnnotation on a legacy manifest erases the unrehomed DEK',
      () async {
    await insertLegacyRow('victim-doc', 'b64-legacy-dek-BBB');

    final repo = container.read(contentRepositoryProvider);
    final plugin = repo.asPluginCapability(canWrite: true);
    await plugin.addAnnotation(
      'victim-doc',
      Annotation(
        id: 'a1',
        docId: 'victim-doc',
        text: 'marginalia',
        author: 'plugin',
        createdAt: DateTime(2024),
      ),
    );

    expect(await rawKey('victim-doc'), isNotNull,
        reason: 'addAnnotation round-trips the projected manifest through '
            'replace() and destroys the pending-rehome DEK column.');
  });

  test('plugin saveManifest write-back erases the unrehomed DEK', () async {
    await insertLegacyRow('victim-manifest', 'b64-legacy-dek-CCC');

    final repo = container.read(contentRepositoryProvider);
    final plugin = repo.asPluginCapability(canWrite: true);
    // The only manifest a plugin can obtain is the projected one.
    final projected = await plugin.getManifestByUuid('victim-manifest');
    expect(projected, isNotNull);
    expect(projected!.encryptionKey, isNull,
        reason: 'projection must hide the key — confirmed');

    await plugin.saveManifest(projected.copyWith(
      title: 'plugin-retitled',
    ));

    expect(await rawKey('victim-manifest'), isNotNull,
        reason: 'saveManifest replace()es the projected row verbatim — the '
            'hidden key column is written back as NULL, destroying the '
            'legacy DEK it was never allowed to read.');
  });
}
