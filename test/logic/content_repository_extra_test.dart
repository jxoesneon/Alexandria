import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart';
import 'package:alexandria/logic/content_repository.dart';
import 'package:alexandria/models/workspace_models.dart';
import 'package:alexandria/services/audit_log_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

class _FakeIpfsService extends IpfsService {
  _FakeIpfsService(super.ref);

  var _counter = 0;

  @override
  Future<String> addFile(Uint8List data) async {
    _counter++;
    return 'fake-cid-$_counter';
  }

  @override
  Stream<Uint8List> getFile(String cid) async* {
    yield Uint8List(0);
  }
}

class _FakeSecureStorageService extends SecureStorageService {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<bool> containsKey(String key) async => false;
}

class _FakeAuditLogService extends AuditLogService {
  _FakeAuditLogService(super.ref);

  @override
  Future<void> log(String action,
      {String? details, String? actor, String status = 'Success'}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase inMemoryDb;
  late ProviderContainer container;

  setUp(() {
    inMemoryDb = AppDatabase();
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(inMemoryDb),
        ipfsServiceProvider.overrideWith((ref) => _FakeIpfsService(ref)),
        secureStorageServiceProvider
            .overrideWithValue(_FakeSecureStorageService()),
        auditLogServiceProvider
            .overrideWith((ref) => _FakeAuditLogService(ref)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await inMemoryDb.close();
  });

  group('getAllNotes', () {
    test('returns only manifests with category note', () async {
      final repo = container.read(contentRepositoryProvider);

      await inMemoryDb.insertManifest({
        'uuid': 'u1',
        'title': 'Book',
        'lastUpdated': DateTime.now(),
        'category': 'book',
        'metadata': jsonEncode({'content': 'book content'}),
      });

      await inMemoryDb.insertManifest({
        'uuid': 'u2',
        'title': 'Note One',
        'lastUpdated': DateTime.now(),
        'category': 'note',
        'author': 'Alice',
        'tags': '["tag1","tag2"]',
        'description': 'A summary',
        'metadata': jsonEncode({'content': 'note body', 'status': 'saved'}),
      });

      final notes = await repo.getAllNotes();

      expect(notes, hasLength(1));
      expect(notes.first.id, 'u2');
      expect(notes.first.title, 'Note One');
      expect(notes.first.author, 'Alice');
      expect(notes.first.tags, ['tag1', 'tag2']);
      expect(notes.first.summary, 'A summary');
      expect(notes.first.content, 'note body');
      expect(notes.first.status, NoteStatus.saved);
    });

    test('parses comma-separated tags when JSON decoding fails', () async {
      final repo = container.read(contentRepositoryProvider);

      await inMemoryDb.insertManifest({
        'uuid': 'u3',
        'title': 'Note Two',
        'lastUpdated': DateTime.now(),
        'category': 'note',
        'tags': 'a, b, c',
        'metadata': jsonEncode({'content': 'c', 'status': 'draft'}),
      });

      final notes = await repo.getAllNotes();

      expect(notes.first.tags, ['a', 'b', 'c']);
    });
  });

  group('getNoteByUuid', () {
    test('returns the matching note', () async {
      final repo = container.read(contentRepositoryProvider);

      await inMemoryDb.insertManifest({
        'uuid': 'n1',
        'title': 'Target',
        'lastUpdated': DateTime.now(),
        'category': 'note',
        'author': 'Bob',
        'metadata': jsonEncode({'content': 'hello', 'status': 'committed'}),
      });

      final note = await repo.getNoteByUuid('n1');

      expect(note.title, 'Target');
      expect(note.author, 'Bob');
      expect(note.content, 'hello');
      expect(note.status, NoteStatus.committed);
    });

    test('throws when the note does not exist', () {
      final repo = container.read(contentRepositoryProvider);

      expect(repo.getNoteByUuid('missing'), throwsA(isA<Exception>()));
    });
  });

  group('saveNote', () {
    test('inserts a new note manifest', () async {
      final repo = container.read(contentRepositoryProvider);
      final note = const Note(
        id: 'new-note',
        title: 'Fresh',
        author: 'Charlie',
        tags: ['x'],
        summary: 's',
        content: 'body',
        status: NoteStatus.draft,
      );

      await repo.saveNote(note);
      final notes = await repo.getAllNotes();

      expect(notes, hasLength(1));
      expect(notes.first.id, 'new-note');
      expect(notes.first.title, 'Fresh');
      expect(notes.first.author, 'Charlie');
      expect(notes.first.tags, ['x']);
      expect(notes.first.content, 'body');
      expect(notes.first.status, NoteStatus.draft);
    });

    test('updates an existing note manifest', () async {
      final repo = container.read(contentRepositoryProvider);
      final original = const Note(
        id: 'update-note',
        title: 'Old',
        author: 'Dana',
        tags: [],
        summary: 's',
        content: 'old',
        status: NoteStatus.draft,
      );

      await repo.saveNote(original);
      final updated = original.copyWith(
        title: 'New',
        content: 'updated body',
        status: NoteStatus.modified,
        tags: ['t'],
      );
      await repo.saveNote(updated);

      final saved = await repo.getNoteByUuid('update-note');

      expect(saved.title, 'New');
      expect(saved.content, 'updated body');
      expect(saved.status, NoteStatus.modified);
      expect(saved.tags, ['t']);
    });
  });

  group('commitNote', () {
    test('saves the note and creates a markdown version', () async {
      final repo = container.read(contentRepositoryProvider);
      final note = const Note(
        id: 'commit-note',
        title: 'Commit Me',
        author: 'Eve',
        tags: [],
        summary: 's',
        content: 'markdown here',
        status: NoteStatus.saved,
      );

      await repo.saveNote(note);
      final cid = await repo.commitNote(note);

      expect(cid, startsWith('fake-cid-'));

      final manifest = await repo.getManifestByUuid('commit-note');
      expect(manifest, isNotNull);
      final versions = await inMemoryDb.getVersionsForManifest(manifest!.id);

      expect(versions, hasLength(1));
      expect(versions.first.format, 'md');
      expect(versions.first.cid, cid);
    });
  });

  group('watchAnnotations', () {
    test('emits empty list for an empty docId', () async {
      final repo = container.read(contentRepositoryProvider);
      final annotations = await repo.watchAnnotations('').first;
      expect(annotations, isEmpty);
    });

    test('emits annotations stored in manifest metadata', () async {
      final repo = container.read(contentRepositoryProvider);

      await inMemoryDb.insertManifest({
        'uuid': 'doc1',
        'title': 'Doc',
        'lastUpdated': DateTime.now(),
        'category': 'book',
        'metadata': jsonEncode({
          'annotations': [
            {
              'id': 'a1',
              'docId': 'doc1',
              'text': 'First',
              'author': 'Reader',
              'createdAt': '2024-01-01T00:00:00.000',
            },
            {
              'id': 'a2',
              'docId': 'doc1',
              'text': 'Second',
              'createdAt': '2024-06-01T00:00:00.000',
            },
          ]
        }),
      });

      final annotations = await repo.watchAnnotations('doc1').first;

      expect(annotations, hasLength(2));
      expect(annotations.first.text, 'First');
      expect(annotations.first.author, 'Reader');
      expect(annotations[1].text, 'Second');
    });

    test('emits empty list when document has no annotations', () async {
      final repo = container.read(contentRepositoryProvider);

      await inMemoryDb.insertManifest({
        'uuid': 'doc2',
        'title': 'No Annotations',
        'lastUpdated': DateTime.now(),
        'category': 'book',
        'metadata': jsonEncode({}),
      });

      final annotations = await repo.watchAnnotations('doc2').first;
      expect(annotations, isEmpty);
    });
  });

  group('addAnnotation', () {
    test('appends an annotation to the manifest metadata', () async {
      final repo = container.read(contentRepositoryProvider);

      await inMemoryDb.insertManifest({
        'uuid': 'doc3',
        'title': 'Annotate',
        'lastUpdated': DateTime.now(),
        'category': 'book',
        'metadata': jsonEncode({}),
      });

      final annotation = Annotation(
        id: 'a3',
        docId: 'doc3',
        text: 'Nice point',
        quote: 'selected text',
        author: 'Reviewer',
        createdAt: DateTime(2024, 3, 1),
      );

      await repo.addAnnotation('doc3', annotation);
      final manifest = await repo.getManifestByUuid('doc3');

      expect(manifest, isNotNull);
      final meta =
          jsonDecode(manifest!.metadata ?? '{}') as Map<String, dynamic>;
      expect(meta['annotations'], hasLength(1));
      expect(meta['annotations'].first['text'], 'Nice point');
      expect(meta['annotations'].first['quote'], 'selected text');
      expect(meta['annotations'].first['author'], 'Reviewer');
    });

    test('throws when the document does not exist', () async {
      final repo = container.read(contentRepositoryProvider);
      final annotation = Annotation(
        id: 'a4',
        docId: 'missing',
        text: 'text',
        createdAt: DateTime.now(),
      );

      await expectLater(
        repo.addAnnotation('missing', annotation),
        throwsA(isA<Exception>()),
      );
    });
  });
}
