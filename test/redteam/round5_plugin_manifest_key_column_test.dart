// RED TEAM PoC — Round-5: the round-4 plugin facade narrowed the
// repository's *methods* but not the *row objects* it returns.
//
//   lib/logic/content_repository.dart:583+ (PluginContentRepository)
//   Manifest/metadata reads pass through unchanged — getAllManifests,
//   getManifestByUuid, watchAllManifests all hand the plugin the raw
//   Drift ContentManifest row, whose `encryptionKey` column still
//   exists and is still writable through AppDatabase.insertManifest
//   (lib/data/database.dart:58, :244).
//
// Nothing in the CURRENT tree writes that column — but the round-2 fix
// deliberately left the column in place for schema compatibility, so
// every database upgraded from a pre-fix build still holds plaintext
// DEKs in it. A `contentRead`-scoped plugin reads them straight off the
// manifest object — no storage provider needed. The facade's "every
// path that reaches key material is closed by construction" claim is
// violated by a *field*, not a method.
//
// Asserts the SECURE expectation: a plugin-facing manifest must never
// carry the encryptionKey field — the plugin view must project it away
// (or the column must be wiped on read/migration).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart';
import 'package:alexandria/logic/content_repository.dart';
import 'package:alexandria/services/plugin_service.dart';

void main() {
  test('a contentRead plugin must not read the manifest encryptionKey '
      'column (legacy-row DEK leak)', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final db = container.read(databaseProvider);

    // A manifest row shaped exactly like one written by a pre-round-2
    // build: the DEK sits in the plaintext column.
    await db.insertManifest({
      'uuid': 'legacy-doc',
      'title': 'upgraded content',
      'lastUpdated': DateTime.now(),
      'isEncrypted': true,
      'encryptionKey': 'U0VDUkVULURFSw==', // plaintext DEK, legacy write
    });

    // What registerPlugin issues for a manifest declaring contentRead.
    final ctx = PluginContext(
      container: container,
      pluginId: 'com.evil.read-only',
      permissions: {PluginPermission.contentRead},
    );
    final repo = ctx.read(contentRepositoryProvider);
    expect(repo, isA<PluginContentRepository>());

    final manifests = await repo.getAllManifests();
    final row = manifests.firstWhere((m) => m.uuid == 'legacy-doc');

    expect(row.encryptionKey, isNull,
        reason:
            'the narrowed plugin view returned a manifest row carrying '
            'encryptionKey="${row.encryptionKey}" — the key-material '
            'column survives into the plugin-visible object graph. '
            'PluginContentRepository closed the *methods* '
            '(contentDekBase64, retrieveManifestContent) but manifest '
            'reads pass through the raw Drift row, so any database '
            'upgraded from a pre-round-2 build still hands its stored '
            'DEKs to every contentRead plugin.');

    // Same leak through the single-manifest read path.
    final single = await repo.getManifestByUuid('legacy-doc');
    expect(single?.encryptionKey, isNull,
        reason:
            'getManifestByUuid also returns the raw row — the '
            'encryptionKey field reaches the plugin identically.');
  });
}
