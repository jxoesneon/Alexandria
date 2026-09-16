import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart';
import 'package:alexandria/logic/content_repository.dart';
import 'package:alexandria/models/workspace_models.dart';
import 'package:alexandria/services/cid_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/metadata_scrubbing_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:alexandria/services/sync_service.dart';

class _FakeSecureStorage implements SecureStorageService {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);

  @override
  Future<void> deleteAll() async => data.clear();

  @override
  Future<bool> containsKey(String key) async => data.containsKey(key);
}

class _IpfsStub extends IpfsService {
  _IpfsStub(super.ref, {this.publishResult = true});

  bool publishResult;
  bool throwOnPublish = false;

  @override
  Future<bool> publishToPubsub(String topic, String data) async {
    if (throwOnPublish) throw StateError('pubsub exploded');
    return publishResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncService queue persistence & retry', () {
    test('QueuedOperation json round-trip', () {
      final op = QueuedOperation(
        id: 'q1',
        collectionId: 'col_a',
        operation: 'insert',
        data: const {'k': 1},
        timestamp: DateTime(2026, 1, 1),
        retries: 2,
      );
      final restored = QueuedOperation.fromJson(op.toJson());
      expect(restored.id, 'q1');
      expect(restored.collectionId, 'col_a');
      expect(restored.operation, 'insert');
      expect(restored.retries, 2);
      expect(restored.data['k'], 1);
      // Missing retries defaults to 0.
      final noRetries = QueuedOperation.fromJson({
        'id': 'q2',
        'collectionId': 'c',
        'operation': 'o',
        'data': <String, dynamic>{},
        'timestamp': DateTime(2026, 1, 1).toIso8601String(),
      });
      expect(noRetries.retries, 0);
    });

    test('failed publish ages the op instead of wedging the queue', () async {
      final storage = _FakeSecureStorage();
      late _IpfsStub ipfs;
      final container = ProviderContainer(overrides: [
        secureStorageServiceProvider.overrideWithValue(storage),
        ipfsServiceProvider.overrideWith((ref) {
          ipfs = _IpfsStub(ref, publishResult: false);
          return ipfs;
        }),
      ]);
      addTearDown(container.dispose);
      final sync = container.read(syncServiceProvider);
      addTearDown(sync.dispose);

      await sync.init();
      await sync.queueOperation(
        collectionId: 'col_fail',
        operation: 'insert',
        data: const {'a': 1},
      );
      // Publish returned false → op stays queued with retries++.
      expect(sync.offlineQueue.length, 1);
      expect(sync.offlineQueue.first.retries, 1);

      ipfs.throwOnPublish = true;
      await sync.processQueue();
      expect(sync.offlineQueue.first.retries, 2);
    });

    test('_loadQueue survives corrupt payloads and malformed entries',
        () async {
      final storage = _FakeSecureStorage();
      final container = ProviderContainer(overrides: [
        secureStorageServiceProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);
      final sync = container.read(syncServiceProvider);
      addTearDown(sync.dispose);

      // Not JSON at all → early return.
      storage.data['sync_queue'] = 'this is not json';
      await sync.init();
      expect(sync.offlineQueue, isEmpty);
    });

    test('_loadQueue ignores non-List JSON', () async {
      final storage = _FakeSecureStorage();
      final container = ProviderContainer(overrides: [
        secureStorageServiceProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);
      final sync = container.read(syncServiceProvider);
      addTearDown(sync.dispose);

      storage.data['sync_queue'] = '{"a": 1}';
      await sync.init();
      expect(sync.offlineQueue, isEmpty);
    });

    test('_loadQueue skips malformed and unsafe-field entries', () async {
      final storage = _FakeSecureStorage();
      final container = ProviderContainer(overrides: [
        secureStorageServiceProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);
      final sync = container.read(syncServiceProvider);
      addTearDown(sync.dispose);

      storage.data['sync_queue'] = jsonEncode([
        'not-a-map',
        {
          'id': 'bad-field',
          'collectionId': 'evil/escape',
          'operation': 'insert',
          'data': <String, dynamic>{},
          'timestamp': DateTime(2026, 1, 1).toIso8601String(),
        },
        {
          'id': 'good',
          'collectionId': 'col_ok',
          'operation': 'insert',
          'data': <String, dynamic>{'x': 1},
          'timestamp': DateTime(2026, 1, 1).toIso8601String(),
          'retries': 1,
        },
      ]);
      await sync.init();
      expect(sync.offlineQueue.length, 1);
      expect(sync.offlineQueue.first.id, 'good');
    });
  });

  group('ContentRepository coverage extras', () {
    late ProviderContainer container;
    late ContentRepository repo;

    setUp(() {
      final store = <String, String>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async {
          final key = call.arguments['key'] as String?;
          switch (call.method) {
            case 'read':
              return store[key];
            case 'write':
              store[key!] = call.arguments['value'] as String;
              return null;
            case 'delete':
              store.remove(key);
              return null;
            case 'containsKey':
              return store.containsKey(key);
            default:
              return null;
          }
        },
      );
      container = ProviderContainer();
      repo = container.read(contentRepositoryProvider);
    });

    tearDown(() => container.dispose());

    test(
        'createContent defaults format to bin and downloadContent '
        'delegates to retrieveContent', () async {
      final data = utf8.encode('binary blob');
      final uuid = await repo.createContent(
        title: 'Blob',
        fileData: data,
        // no format, no extraMetadata['format'] → 'bin' fallback
      );
      final manifest = await repo.getManifestByUuid(uuid);
      expect(manifest, isNotNull);

      final db = container.read(databaseProvider);
      final versions = await db.getVersionsForManifest(manifest!.id);
      final fetched = await repo.downloadContent(versions.first.cid);
      expect(utf8.decode(fetched), 'binary blob');
    });

    test('_decodeMetadata treats non-JSON metadata as empty', () async {
      final db = container.read(databaseProvider);
      await db.insertManifest({
        'uuid': 'badmeta',
        'title': 'Note',
        'category': 'note',
        'metadata': 'this is not json',
        'lastUpdated': DateTime.now(),
      });
      final note = await repo.getNoteByUuid('badmeta');
      expect(note.id, 'badmeta');
      expect(note.content, '');
    });

    test('annotation with unparseable createdAt falls back to now', () async {
      final db = container.read(databaseProvider);
      await db.insertManifest({
        'uuid': 'doc1',
        'title': 'Doc',
        'category': 'docs',
        'metadata': jsonEncode({
          'annotations': [
            {'id': 'a1', 'text': 'hi', 'createdAt': 'not-a-date'},
          ],
        }),
        'lastUpdated': DateTime.now(),
      });
      final annotations = await repo.watchAnnotations('doc1').first;
      expect(annotations.length, 1);
      expect(annotations.first.text, 'hi');
    });

    test('PluginContentRepository write paths and watchAllManifests', () async {
      final plugin = repo.asPluginCapability(canWrite: true);

      // watchAllManifests projection (lines 635-638).
      final first = await plugin.watchAllManifests().first;
      expect(first, isA<List<ContentManifest>>());

      final uuid = await plugin.createContent(
        title: 'plugin doc',
        fileData: utf8.encode('via plugin'),
      );
      final manifest = await plugin.getManifestByUuid(uuid);
      expect(manifest, isNotNull);
      expect(manifest!.encryptionKey, isNull);

      await plugin.addVersion(uuid, 'cid-x', 'en', 'txt', sizeBytes: 3);
      await plugin.addContentVersion(
        manifestUuid: uuid,
        // Version payloads have a 64-byte minimum.
        fileData: Uint8List.fromList(List.filled(80, 0x61)),
        language: 'en',
        format: 'txt',
      );
      await plugin.saveManifest(manifest);
      await plugin.saveNote(const Note(
        id: 'note-1',
        title: 'n',
        author: 'a',
        tags: [],
        summary: '',
        content: 'body',
        status: NoteStatus.draft,
      ));
      final cid = await plugin.commitNote(const Note(
        id: 'note-2',
        title: 'n2',
        author: 'a',
        tags: [],
        summary: '',
        content: 'body2',
        status: NoteStatus.committed,
      ));
      expect(cid, isNotEmpty);
    });
  });

  group('MetadataScrubbingService JPEG marker-walk edges', () {
    late MetadataScrubbingService scrubber;

    setUp(() {
      scrubber = MetadataScrubbingService(CidService());
    });

    Uint8List jpeg(List<int> tail) => Uint8List.fromList([0xFF, 0xD8, ...tail]);

    /// Minimal SOS header: FF DA + segLen 8 + 6 payload bytes.
    List<int> sos(List<int> payload) => [0xFF, 0xDA, 0x00, 0x08, ...payload];

    test('reserved markers 0x30-0x3F are consumed at width 2', () async {
      // FF D8 SOI, FF 35 reserved (dropped), FF D9 EOI — padded past
      // the 12-byte sniff floor so detectFileType sees a JPEG.
      final input =
          jpeg([0xFF, 0x35, 0xFF, 0xD9, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
      final res = await scrubber.scrubMetadata(input);
      expect(res.scrubbedBytes, [0xFF, 0xD8, 0xFF, 0xD9]);
    });

    test('standalone TEM marker is kept verbatim', () async {
      final input =
          jpeg([0xFF, 0x01, 0xFF, 0xD9, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
      final res = await scrubber.scrubMetadata(input);
      expect(res.scrubbedBytes, [0xFF, 0xD8, 0xFF, 0x01, 0xFF, 0xD9]);
    });

    test('canonical Adobe APP14 is kept', () async {
      // FF EE + segLen 14 + 'Adobe' + 7 payload bytes.
      final input = jpeg([
        0xFF,
        0xEE,
        0x00,
        0x0E,
        ...'Adobe'.codeUnits,
        0x00,
        0x01,
        0x02,
        0x03,
        0x04,
        0x05,
        0x06,
        0xFF,
        0xD9,
      ]);
      final res = await scrubber.scrubMetadata(input);
      expect(res.scrubbedBytes.length, greaterThan(4));
      expect(res.scrubbedBytes.sublist(6, 11), 'Adobe'.codeUnits);
    });

    test('trailing lone 0xFF in entropy data is kept verbatim', () async {
      final input = jpeg([
        ...sos([0x01, 0x01, 0x00, 0x3F, 0x00, 0x11]),
        0x11, 0x22, 0xFF, // entropy ending on a lone 0xFF
      ]);
      final res = await scrubber.scrubMetadata(input);
      // Lone trailing 0xFF must be emitted, not crash the walker.
      expect(res.scrubbedBytes.last, 0xFF);
    });

    test('resync with no remaining marker drops the tail', () async {
      // SOI + APP0 with a declared length far beyond the buffer, and no
      // further 0xFF bytes to resync onto → _nextJpegMarker returns -1.
      final input = jpeg([
        0xFF, 0xE0, 0x7F, 0xFF, // segLen 32767 > remaining
        0x41, 0x41, 0x41, 0x41, // garbage, no markers
        0x42, 0x42, 0x42, 0x42,
      ]);
      final res = await scrubber.scrubMetadata(input);
      expect(res.scrubbedBytes, [0xFF, 0xD8]);
    });

    test('assembled FF E1 + Exif landing pad refuses image content', () async {
      // SOS payload ends with `FF E1 00 00` — an intra-segment pad
      // prefix that only completes when the next emitted bytes (the
      // verbatim entropy run) start with 'Exif'. The assembled-stream
      // rescan must catch the straddling pad.
      final input = jpeg([
        ...sos([0x01, 0x01, 0xFF, 0xE1, 0x00, 0x00]),
        ...'Exif'.codeUnits,
        0x00,
        0x11,
        0x22,
      ]);
      final res = await scrubber.scrubMetadata(input);
      expect(res.scrubbedBytes, [0xFF, 0xD8, 0xFF, 0xD9]);
    });

    test('assembled FF DB FF + Ducky landing pad is refused', () async {
      final input = jpeg([
        ...sos([0x01, 0x01, 0xFF, 0xDB, 0xFF, 0x00]),
        0xAA,
        0xBB,
        ...'Ducky'.codeUnits,
        0x00,
      ]);
      final res = await scrubber.scrubMetadata(input);
      expect(res.scrubbedBytes, [0xFF, 0xD8, 0xFF, 0xD9]);
    });

    test('assembled FF DB FF + Adobe landing pad is refused', () async {
      final input = jpeg([
        ...sos([0x01, 0x01, 0xFF, 0xDB, 0xFF, 0x00]),
        0xAA,
        0xBB,
        ...'Adobe'.codeUnits,
        0x00,
      ]);
      final res = await scrubber.scrubMetadata(input);
      expect(res.scrubbedBytes, [0xFF, 0xD8, 0xFF, 0xD9]);
    });

    test('detectSensitiveFields fails closed on unreadable input', () async {
      // Whatever the exif reader does with this garbage, the API must
      // return a list — a throw inside becomes [].
      final res = await scrubber.detectSensitiveFields(
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x02]));
      expect(res, isA<List<String>>());
    });
  });
}
