import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart';

void main() {
  group('AppDatabase public API', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    test('schemaVersion is 2', () {
      expect(db.schemaVersion, equals(2));
    });

    test('insert and retrieve a manifest by uuid', () async {
      final now = DateTime.now();
      await db.insertManifest({
        'uuid': 'uuid-1',
        'title': 'The Republic',
        'author': 'Plato',
        'description': 'A philosophical work',
        'category': 'Philosophy',
        'tags': 'politics',
        'metadata': '{}',
        'isEncrypted': false,
        'lastUpdated': now,
      });

      final manifest = await db.getManifestByUuid('uuid-1');
      expect(manifest, isNotNull);
      expect(manifest!['title'], equals('The Republic'));
      expect(manifest['author'], equals('Plato'));
      expect(manifest['category'], equals('Philosophy'));
      expect(manifest['lastUpdated'], isA<DateTime>());
      expect(manifest['isEncrypted'], isFalse);
      expect(manifest['uuid'], equals('uuid-1'));
      expect(manifest['id'], isA<int>());
    });

    test('getManifestByUuid returns null for missing uuid', () async {
      final manifest = await db.getManifestByUuid('missing');
      expect(manifest, isNull);
    });

    test('getAllManifests returns all inserted manifests', () async {
      await db.insertManifest({
        'uuid': 'all-1',
        'title': 'A',
        'lastUpdated': DateTime.now(),
      });
      await db.insertManifest({
        'uuid': 'all-2',
        'title': 'B',
        'lastUpdated': DateTime.now(),
      });

      final manifests = await db.getAllManifests();
      expect(manifests.length, equals(2));
      expect(manifests.map((m) => m.title), containsAll(['A', 'B']));
    });

    test('insert and retrieve a version by cid', () async {
      await db.insertManifest({
        'uuid': 'ver-1',
        'title': 'Versioned Content',
        'lastUpdated': DateTime.now(),
      });
      final manifest = await db.getManifestByUuid('ver-1');
      final manifestId = manifest!['id'] as int;

      final created = DateTime.now();
      await db.insertVersion({
        'manifestId': manifestId,
        'cid': 'cid-123',
        'sizeBytes': 1024,
        'createdData': created,
        'language': 'en',
        'format': 'pdf',
        'peerCount': 2,
        'isPinned': true,
        'lastHealthCheck': null,
      });

      final version = await db.getVersionByCid('cid-123');
      expect(version, isNotNull);
      expect(version!['cid'], equals('cid-123'));
      expect(version['manifestId'], equals(manifestId));
      expect(version['sizeBytes'], equals(1024));
      expect(version['format'], equals('pdf'));
      expect(version['createdData'], isA<DateTime>());
    });

    test('getVersionByCid returns null for missing cid', () async {
      final version = await db.getVersionByCid('missing-cid');
      expect(version, isNull);
    });

    test('getEndangeredVersions returns versions below threshold', () async {
      await db.insertManifest({
        'uuid': 'end-1',
        'title': 'Endangered',
        'lastUpdated': DateTime.now(),
      });
      final manifest = await db.getManifestByUuid('end-1');
      final manifestId = manifest!['id'] as int;

      await db.insertVersion({
        'manifestId': manifestId,
        'cid': 'cid-low',
        'sizeBytes': 100,
        'createdData': DateTime.now(),
        'peerCount': 1,
      });
      await db.insertVersion({
        'manifestId': manifestId,
        'cid': 'cid-ok',
        'sizeBytes': 100,
        'createdData': DateTime.now(),
        'peerCount': 5,
      });

      final endangered = await db.getEndangeredVersions(2);
      expect(endangered.length, equals(1));
      expect(endangered.single.cid, equals('cid-low'));
    });

    test('getVersionsForManifest returns only matching versions', () async {
      await db.insertManifest({
        'uuid': 'for-1',
        'title': 'Manifest Versions',
        'lastUpdated': DateTime.now(),
      });
      final manifest = await db.getManifestByUuid('for-1');
      final manifestId = manifest!['id'] as int;

      await db.insertVersion({
        'manifestId': manifestId,
        'cid': 'cid-a',
        'sizeBytes': 1,
        'createdData': DateTime.now(),
      });
      await db.insertVersion({
        'manifestId': 9999,
        'cid': 'cid-other',
        'sizeBytes': 1,
        'createdData': DateTime.now(),
      });

      final versions = await db.getVersionsForManifest(manifestId);
      expect(versions.length, equals(1));
      expect(versions.single.cid, equals('cid-a'));
    });

    test('getUserActivityDates returns empty list', () async {
      final dates = await db.getUserActivityDates('did:alex:alice');
      expect(dates, isEmpty);
    });

    test('getProfileByPublicKey returns null when absent', () async {
      final profile = await db.getProfileByPublicKey('did:alex:bob');
      expect(profile, isNull);
    });

    test('databaseProvider provides an in-memory AppDatabase', () async {
      final container = ProviderContainer();
      final database = container.read(databaseProvider);
      expect(database, isA<AppDatabase>());
      await database.close();
      container.dispose();
    });

    test('insert and retrieve a user profile', () async {
      await db.into(db.userProfiles).insert(
            UserProfilesCompanion.insert(
              publicKey: 'did:alex:alice',
              lastActive: DateTime(2026, 1, 15),
            ),
          );

      final profile = await db.getProfileByPublicKey('did:alex:alice');
      expect(profile, isNotNull);
      expect(profile!.publicKey, 'did:alex:alice');
      expect(profile.reputation, 10);
    });

    test('insertVersion uses default values when omitted', () async {
      await db.insertManifest({
        'uuid': 'ver-defaults',
        'title': 'Version Defaults',
        'lastUpdated': DateTime.now(),
      });
      final manifest = await db.getManifestByUuid('ver-defaults');
      final manifestId = manifest!['id'] as int;

      await db.insertVersion({
        'manifestId': manifestId,
        'cid': 'cid-defaults',
        'sizeBytes': 100,
      });

      final version = await db.getVersionByCid('cid-defaults');
      expect(version, isNotNull);
      expect(version!['manifestId'], manifestId);
      expect(version['sizeBytes'], 100);
      expect(version['language'], 'en');
      expect(version['format'], 'bin');
      expect(version['peerCount'], 0);
      expect(version['isPinned'], isTrue);
      expect(version['createdData'], isA<DateTime>());
    });

    test('insertManifest uses default values when optional fields are omitted',
        () async {
      await db.insertManifest({
        'uuid': 'manifest-defaults',
        'title': 'Minimal',
        'lastUpdated': DateTime(2026, 1, 20),
      });

      final manifest = await db.getManifestByUuid('manifest-defaults');
      expect(manifest, isNotNull);
      expect(manifest!['category'], 'other');
      expect(manifest['isEncrypted'], isFalse);
      expect(manifest['author'], isNull);
    });

    test('getAllManifests maps nullable fields correctly', () async {
      await db.insertManifest({
        'uuid': 'map-fields',
        'title': 'Map Fields',
        'author': 'Author',
        'description': 'Description',
        'category': 'cat',
        'tags': 'a,b',
        'metadata': '{}',
        'isEncrypted': true,
        'encryptionKey': 'key',
        'lastUpdated': DateTime(2026, 1, 1),
      });

      final manifests = await db.getAllManifests();
      final match = manifests.firstWhere((m) => m.uuid == 'map-fields');
      expect(match.author, 'Author');
      expect(match.description, 'Description');
      expect(match.category, 'cat');
      expect(match.tags, 'a,b');
      expect(match.metadata, '{}');
      expect(match.isEncrypted, isTrue);
      expect(match.encryptionKey, 'key');
    });

    test('getVersionsForManifest returns empty for unknown manifest', () async {
      final versions = await db.getVersionsForManifest(999999);
      expect(versions, isEmpty);
    });
  });
}
