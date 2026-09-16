import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart';
import 'package:alexandria/logic/content_repository.dart';
import 'package:alexandria/models/workspace_models.dart';
import 'package:alexandria/providers/workspace_providers.dart';
import 'package:alexandria/services/fast_cdc_service.dart';
import 'package:alexandria/services/metadata_service.dart';

// ignore_for_file: use_super_parameters

class _FakeContentRepository extends ContentRepository {
  _FakeContentRepository(Ref ref) : super(ref);

  final _manifests = <ContentManifest>[];
  final _notes = <Note>[];
  final _manifestsController =
      StreamController<List<ContentManifest>>.broadcast();
  final _annotationControllers = <String, StreamController<List<Annotation>>>{};

  var _throwNotes = false;

  void seedManifests(List<ContentManifest> manifests) {
    _manifests.addAll(manifests);
    _manifestsController.add(List.unmodifiable(_manifests));
  }

  void seedNotes(List<Note> notes) {
    _notes.addAll(notes);
  }

  void seedAnnotations(String docId, List<Annotation> annotations) {
    final controller = _annotationControllers.putIfAbsent(
        docId, StreamController<List<Annotation>>.broadcast);
    controller.add(List.unmodifiable(annotations));
  }

  void setThrowNotesError(bool value) {
    _throwNotes = value;
  }

  void emitManifestsError(Object error) {
    _manifestsController.addError(error);
  }

  @override
  Stream<List<ContentManifest>> watchAllManifests() =>
      _manifestsController.stream;

  @override
  Future<List<ContentManifest>> getAllManifests() async =>
      List.unmodifiable(_manifests);

  @override
  Future<List<Note>> getAllNotes() async {
    if (_throwNotes) throw Exception('notes failed');
    return List.unmodifiable(_notes);
  }

  @override
  Future<Note> getNoteByUuid(String uuid) async {
    return _notes.firstWhere(
      (n) => n.id == uuid,
      orElse: () => throw Exception('Note not found'),
    );
  }

  @override
  Stream<List<Annotation>> watchAnnotations(String docId) {
    if (docId.isEmpty) return Stream.value([]);
    final controller = _annotationControllers.putIfAbsent(
        docId, StreamController<List<Annotation>>.broadcast);
    return controller.stream;
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
  }) async {
    final uuid = 'content-${_manifests.length + 1}';
    _manifests.add(
      ContentManifest(
        id: _manifests.length + 1,
        uuid: uuid,
        title: title,
        author: author,
        description: description,
        category: category ?? 'other',
        tags: tags?.join(','),
        metadata: extraMetadata?.toString(),
        isEncrypted: isEncrypted,
        lastUpdated: DateTime.now(),
      ),
    );
    _manifestsController.add(List.unmodifiable(_manifests));
    return uuid;
  }

  @override
  Future<void> addAnnotation(String docId, Annotation annotation) async {
    seedAnnotations(docId, [annotation]);
  }
}

class _FakeMetadataService extends MetadataExtractionService {
  final Map<String, Map<String, dynamic>> _results = {};
  final Set<String> _throwOn = {};

  void setResult(String name, Map<String, dynamic> result) {
    _results[name] = result;
  }

  void setThrow(String name) {
    _throwOn.add(name);
  }

  @override
  Future<Map<String, dynamic>> extractMetadata(PlatformFile file) async {
    if (_throwOn.contains(file.name)) throw Exception('extraction failed');
    return _results[file.name] ?? {'format': 'bin', 'summary': ''};
  }
}

class _FakeFastCdcService extends FastCdcService {
  @override
  List<Chunk> chunk(Uint8List data) => [];
}

ProviderContainer _makeContainer({_FakeMetadataService? metadata}) {
  return ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(AppDatabase()),
      fastCdcServiceProvider.overrideWithValue(_FakeFastCdcService()),
      metadataServiceProvider
          .overrideWithValue(metadata ?? _FakeMetadataService()),
      contentRepositoryProvider
          .overrideWith((ref) => _FakeContentRepository(ref)),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('activeWorkspacesProvider', () {
    test('starts in loading state', () {
      final container = _makeContainer();
      addTearDown(container.dispose);
      expect(container.read(activeWorkspacesProvider),
          isA<AsyncLoading<List<Workspace>>>());
    });

    test('emits workspaces derived from manifests', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final repo =
          container.read(contentRepositoryProvider) as _FakeContentRepository;
      container.read(activeWorkspacesProvider);
      repo.seedManifests([
        ContentManifest(
          id: 1,
          uuid: 'u1',
          title: 'Alpha',
          category: 'book',
          isEncrypted: false,
          lastUpdated: DateTime(2024, 1, 2),
          author: 'A',
          description: 'D',
          tags: 't1,t2',
        ),
        ContentManifest(
          id: 2,
          uuid: 'u2',
          title: 'Beta',
          category: 'note',
          isEncrypted: false,
          lastUpdated: DateTime(2024, 1, 1),
        ),
      ]);

      final workspaces = await container.read(activeWorkspacesProvider.future);

      expect(workspaces, hasLength(2));
      expect(workspaces.first.name, 'Alpha');
      expect(workspaces.first.pendingTasks, 0);
      expect(workspaces.last.name, 'Beta');
      expect(workspaces.last.pendingTasks, 3);
    });

    test('produces error state when the repository stream errors', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final repo =
          container.read(contentRepositoryProvider) as _FakeContentRepository;
      container.read(activeWorkspacesProvider);
      repo.emitManifestsError(Exception('boom'));

      await expectLater(
        container.read(activeWorkspacesProvider.future),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('activityFeedProvider', () {
    test('emits activity events sorted by lastUpdated', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final repo =
          container.read(contentRepositoryProvider) as _FakeContentRepository;
      container.read(activityFeedProvider);
      final t1 = DateTime(2024, 1, 1);
      final t2 = DateTime(2024, 1, 2);
      repo.seedManifests([
        ContentManifest(
            id: 1,
            uuid: 'u1',
            title: 'One',
            category: 'book',
            isEncrypted: false,
            lastUpdated: t1),
        ContentManifest(
            id: 2,
            uuid: 'u2',
            title: 'Two',
            category: 'note',
            isEncrypted: false,
            lastUpdated: t2),
      ]);

      final events = await container.read(activityFeedProvider.future);

      expect(events, hasLength(2));
      expect(events.first.title, 'Two');
      expect(events.last.title, 'One');
    });
  });

  group('ingestionManagerProvider', () {
    test('adds a file and completes it', () async {
      final metadata = _FakeMetadataService();
      metadata.setResult('new.txt', {'format': 'txt', 'summary': 'A note'});
      final container = _makeContainer(metadata: metadata);
      addTearDown(container.dispose);

      final file = PlatformFile(
        name: 'new.txt',
        size: 12,
        bytes: Uint8List.fromList('hello world'.codeUnits),
        identifier: 'id',
      );

      await container.read(ingestionManagerProvider.notifier).addFiles([file]);

      final state = container.read(ingestionManagerProvider);
      expect(state.queue, hasLength(1));
      expect(state.queue.first.status, IngestionStatus.completed);
      expect(state.queue.first.progress, 1.0);
      expect(state.overallProgress, 1.0);
      expect(state.statusMessage, '1 of 1 item(s) completed');
    });

    test('detects metadata conflict for existing title', () async {
      final metadata = _FakeMetadataService();
      metadata
          .setResult('existing.txt', {'format': 'txt', 'summary': 'Summary'});
      final container = _makeContainer(metadata: metadata);
      addTearDown(container.dispose);

      final repo =
          container.read(contentRepositoryProvider) as _FakeContentRepository;
      repo.seedManifests([
        ContentManifest(
            id: 1,
            uuid: 'u1',
            title: 'existing',
            category: 'other',
            isEncrypted: false,
            lastUpdated: DateTime(2024, 1, 1)),
      ]);

      final file = PlatformFile(
        name: 'existing.txt',
        size: 4,
        bytes: Uint8List.fromList('data'.codeUnits),
        identifier: 'id',
      );

      await container.read(ingestionManagerProvider.notifier).addFiles([file]);

      final state = container.read(ingestionManagerProvider);
      expect(state.queue.first.status, IngestionStatus.conflict);
      expect(state.queue.first.conflictMessage, contains('Metadata conflict'));
      expect(state.queue.first.progress, 0.0);
    });

    test('marks item as error when metadata extraction fails', () async {
      final metadata = _FakeMetadataService();
      metadata.setThrow('bad.txt');
      final container = _makeContainer(metadata: metadata);
      addTearDown(container.dispose);

      final file = PlatformFile(
        name: 'bad.txt',
        size: 4,
        bytes: Uint8List.fromList('data'.codeUnits),
        identifier: 'id',
      );

      await container.read(ingestionManagerProvider.notifier).addFiles([file]);

      final state = container.read(ingestionManagerProvider);
      expect(state.queue.first.status, IngestionStatus.error);
      expect(state.queue.first.conflictMessage, contains('Ingestion error'));
    });

    test(
        'refuses a file whose declared size exceeds the ingest '
        'ceiling (campaign-2 service-side bound)', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      // Declared size over the cap - bytes never materialized.
      final file = PlatformFile(
        name: 'huge.bin',
        size: IngestionPipelineManager.maxIngestBytes + 1,
        identifier: 'id',
      );

      await container.read(ingestionManagerProvider.notifier).addFiles([file]);

      final state = container.read(ingestionManagerProvider);
      expect(state.queue.first.status, IngestionStatus.error);
      expect(state.queue.first.conflictMessage, contains('ingest limit'));
    });

    test(
        'a file with neither bytes nor path errors out instead of '
        'ingesting a phantom zero-byte manifest', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final file = PlatformFile(
        name: 'ghost.bin',
        size: 10,
        identifier: 'id',
      );

      await container.read(ingestionManagerProvider.notifier).addFiles([file]);

      final state = container.read(ingestionManagerProvider);
      expect(state.queue.first.status, IngestionStatus.error);
      expect(state.queue.first.conflictMessage, contains('No file data'));
    });

    test('addFiles does nothing when the file list is empty', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      await container.read(ingestionManagerProvider.notifier).addFiles([]);

      expect(container.read(ingestionManagerProvider).queue, isEmpty);
      expect(container.read(ingestionManagerProvider).statusMessage, '');
    });
  });

  group('notesListProvider', () {
    test('emits data', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final repo =
          container.read(contentRepositoryProvider) as _FakeContentRepository;
      repo.seedNotes([
        const Note(
            id: 'n1',
            title: 'Note 1',
            author: 'A',
            tags: [],
            summary: 's',
            content: 'c'),
      ]);

      final notes = await container.read(notesListProvider.future);

      expect(notes, hasLength(1));
      expect(notes.first.title, 'Note 1');
    });

    test('emits error when repository throws', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final repo =
          container.read(contentRepositoryProvider) as _FakeContentRepository;
      repo.setThrowNotesError(true);

      await expectLater(
        container.read(notesListProvider.future),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('noteProvider', () {
    test('returns the note by uuid', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final repo =
          container.read(contentRepositoryProvider) as _FakeContentRepository;
      repo.seedNotes([
        const Note(
            id: 'n1',
            title: 'Note 1',
            author: 'A',
            tags: [],
            summary: 's',
            content: 'c'),
      ]);

      final note = await container.read(noteProvider('n1').future);
      expect(note.title, 'Note 1');
    });

    test('throws when the note is not found', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      await expectLater(
        container.read(noteProvider('missing').future),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('annotationsProvider', () {
    test('emits empty list for an empty docId', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final annotations = await container.read(annotationsProvider('').future);
      expect(annotations, isEmpty);
    });

    test('emits annotations for a document', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final repo =
          container.read(contentRepositoryProvider) as _FakeContentRepository;
      final annotation = Annotation(
        id: 'a1',
        docId: 'd1',
        text: 'text',
        createdAt: DateTime.now(),
      );
      container.read(annotationsProvider('d1'));
      repo.seedAnnotations('d1', [annotation]);

      final annotations =
          await container.read(annotationsProvider('d1').future);
      expect(annotations, hasLength(1));
      expect(annotations.first.text, 'text');
    });
  });
}
