import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/models/workspace_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Workspace', () {
    test('constructor stores fields', () {
      const ws = Workspace(id: '1', name: 'My Workspace', pendingTasks: 3);
      expect(ws.id, '1');
      expect(ws.name, 'My Workspace');
      expect(ws.pendingTasks, 3);
    });

    test('pendingTasks defaults to zero', () {
      const ws = Workspace(id: '2', name: 'Empty');
      expect(ws.pendingTasks, 0);
    });
  });

  group('ActivityEvent', () {
    test('constructor stores fields', () {
      final now = DateTime.now();
      final event = ActivityEvent(
        title: 't',
        description: 'd',
        timestamp: now,
      );
      expect(event.title, 't');
      expect(event.description, 'd');
      expect(event.timestamp, now);
    });
  });

  group('IngestionStatus', () {
    test('contains the expected values', () {
      expect(IngestionStatus.values, [
        IngestionStatus.pending,
        IngestionStatus.processing,
        IngestionStatus.completed,
        IngestionStatus.error,
        IngestionStatus.conflict,
      ]);
    });
  });

  group('IngestionItem', () {
    const item = IngestionItem(
      id: 'i1',
      filename: 'file.txt',
      progress: 0.5,
      status: IngestionStatus.processing,
      conflictMessage: 'original',
    );

    test('constructor stores all fields', () {
      expect(item.id, 'i1');
      expect(item.filename, 'file.txt');
      expect(item.progress, 0.5);
      expect(item.status, IngestionStatus.processing);
      expect(item.conflictMessage, 'original');
    });

    test('copyWith updates id', () {
      final copy = item.copyWith(id: 'i2');
      expect(copy.id, 'i2');
      expect(copy.filename, 'file.txt');
      expect(copy.progress, 0.5);
      expect(copy.status, IngestionStatus.processing);
      expect(copy.conflictMessage, 'original');
    });

    test('copyWith updates filename', () {
      final copy = item.copyWith(filename: 'new.txt');
      expect(copy.id, 'i1');
      expect(copy.filename, 'new.txt');
    });

    test('copyWith updates progress', () {
      final copy = item.copyWith(progress: 0.9);
      expect(copy.progress, 0.9);
      expect(copy.id, 'i1');
    });

    test('copyWith updates status', () {
      final copy = item.copyWith(status: IngestionStatus.completed);
      expect(copy.status, IngestionStatus.completed);
    });

    test('copyWith updates conflictMessage', () {
      final copy = item.copyWith(conflictMessage: 'updated');
      expect(copy.conflictMessage, 'updated');
    });

    test('copyWith keeps original when no value supplied', () {
      final copy = item.copyWith();
      expect(copy.id, item.id);
      expect(copy.filename, item.filename);
      expect(copy.progress, item.progress);
      expect(copy.status, item.status);
      expect(copy.conflictMessage, item.conflictMessage);
    });
  });

  group('IngestionState', () {
    test('constructor uses defaults', () {
      const state = IngestionState();
      expect(state.overallProgress, 0.0);
      expect(state.statusMessage, '');
      expect(state.queue, isEmpty);
    });

    test('constructor stores explicit values', () {
      const state = IngestionState(
        overallProgress: 0.5,
        statusMessage: 'msg',
        queue: [
          IngestionItem(
              id: 'i',
              filename: 'f',
              progress: 0.0,
              status: IngestionStatus.pending)
        ],
      );
      expect(state.overallProgress, 0.5);
      expect(state.statusMessage, 'msg');
      expect(state.queue, hasLength(1));
    });

    test('copyWith updates all fields', () {
      const original = IngestionState();
      final updatedQueue = [
        const IngestionItem(
            id: 'i',
            filename: 'f',
            progress: 1.0,
            status: IngestionStatus.completed)
      ];
      final copy = original.copyWith(
        overallProgress: 1.0,
        statusMessage: 'done',
        queue: updatedQueue,
      );
      expect(copy.overallProgress, 1.0);
      expect(copy.statusMessage, 'done');
      expect(copy.queue, updatedQueue);
    });

    test('copyWith preserves unspecified fields', () {
      const original = IngestionState(statusMessage: 'in progress');
      final copy = original.copyWith(overallProgress: 0.5);
      expect(copy.overallProgress, 0.5);
      expect(copy.statusMessage, 'in progress');
      expect(copy.queue, isEmpty);
    });
  });

  group('NoteStatus', () {
    test('labels are correct', () {
      expect(NoteStatus.draft.label, 'Draft');
      expect(NoteStatus.saved.label, 'Saved');
      expect(NoteStatus.modified.label, 'Modified');
      expect(NoteStatus.committed.label, 'Committed');
    });
  });

  group('Note', () {
    const note = Note(
      id: 'n1',
      title: 'Note Title',
      author: 'Author',
      tags: ['a', 'b'],
      summary: 'summary',
      content: 'content',
      status: NoteStatus.saved,
    );

    test('constructor stores all fields', () {
      expect(note.id, 'n1');
      expect(note.title, 'Note Title');
      expect(note.author, 'Author');
      expect(note.tags, ['a', 'b']);
      expect(note.summary, 'summary');
      expect(note.content, 'content');
      expect(note.status, NoteStatus.saved);
    });

    test('status defaults to draft', () {
      const draft = Note(
        id: 'n2',
        title: 't',
        author: 'a',
        tags: [],
        summary: 's',
        content: 'c',
      );
      expect(draft.status, NoteStatus.draft);
    });

    test('copyWith updates each field', () {
      expect(note.copyWith(id: 'x').id, 'x');
      expect(note.copyWith(title: 'new title').title, 'new title');
      expect(note.copyWith(author: 'new').author, 'new');
      expect(note.copyWith(tags: ['x']).tags, ['x']);
      expect(note.copyWith(summary: 's2').summary, 's2');
      expect(note.copyWith(content: 'c2').content, 'c2');
      expect(note.copyWith(status: NoteStatus.committed).status,
          NoteStatus.committed);
    });

    test('copyWith preserves unspecified fields', () {
      final copy = note.copyWith(title: 'new');
      expect(copy.id, note.id);
      expect(copy.author, note.author);
      expect(copy.content, note.content);
    });
  });

  group('Annotation', () {
    final now = DateTime(2024, 1, 1);
    final annotation = Annotation(
      id: 'a1',
      docId: 'd1',
      text: 'interesting',
      quote: 'q1',
      createdAt: now,
    );

    test('constructor stores all fields', () {
      expect(annotation.id, 'a1');
      expect(annotation.docId, 'd1');
      expect(annotation.text, 'interesting');
      expect(annotation.quote, 'q1');
      expect(annotation.createdAt, now);
    });

    test('author defaults to Reader', () {
      expect(annotation.author, 'Reader');
    });

    test('copyWith updates each field', () {
      final updated = DateTime(2025, 1, 1);
      expect(annotation.copyWith(id: 'x').id, 'x');
      expect(annotation.copyWith(docId: 'y').docId, 'y');
      expect(annotation.copyWith(text: 't2').text, 't2');
      expect(annotation.copyWith(quote: 'q2').quote, 'q2');
      expect(annotation.copyWith(author: 'A').author, 'A');
      expect(annotation.copyWith(createdAt: updated).createdAt, updated);
    });

    test('copyWith preserves unspecified fields', () {
      final copy = annotation.copyWith(text: 'updated');
      expect(copy.id, 'a1');
      expect(copy.docId, 'd1');
      expect(copy.author, 'Reader');
    });
  });
}
