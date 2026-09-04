import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore_for_file: use_super_parameters

import 'package:alexandria/logic/content_repository.dart';
import 'package:alexandria/models/workspace_models.dart';
import 'package:alexandria/providers/workspace_providers.dart';
import 'package:alexandria/ui/workspace/metadata_editor_screen.dart';

class _FakeContentRepository extends ContentRepository {
  _FakeContentRepository(Ref ref) : super(ref);

  final savedNotes = <Note>[];
  final committedNotes = <Note>[];

  @override
  Future<void> saveNote(Note note) async {
    savedNotes.add(note);
  }

  @override
  Future<String> commitNote(Note note) async {
    committedNotes.add(note);
    return 'fake-hash';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const note = Note(
    id: 'note-1',
    title: 'Project Requirements',
    author: 'Ada Lovelace',
    tags: ['workspace', 'planning'],
    summary: 'High-level requirements',
    content: '## Sample Note\n\n- item\n- **bold**',
    status: NoteStatus.draft,
  );

  testWidgets('MetadataEditorScreen renders note list and editor',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesListProvider.overrideWith((ref) => Future.value(const [note])),
          noteProvider(note.id).overrideWith((ref) => Future.value(note)),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const MetadataEditorScreen(),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Metadata Editor'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Project Requirements'), findsNWidgets(2));
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Note Details'), findsOneWidget);
  });

  testWidgets('MetadataEditorScreen handles empty notes', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesListProvider.overrideWith((ref) => Future.value(const <Note>[])),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const MetadataEditorScreen(),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No notes yet.'), findsOneWidget);
  });

  testWidgets('MetadataEditorScreen handles error state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesListProvider
              .overrideWith((ref) => Future.error(Exception('load failed'))),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const MetadataEditorScreen(),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Error loading notes'), findsOneWidget);
  });

  testWidgets('MetadataEditorScreen edits, previews, saves and commits a note',
      (tester) async {
    late _FakeContentRepository fakeRepo;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesListProvider.overrideWith((ref) => Future.value(const [note])),
          noteProvider(note.id).overrideWith((ref) => Future.value(note)),
          contentRepositoryProvider.overrideWith((ref) {
            fakeRepo = _FakeContentRepository(ref);
            return fakeRepo;
          }),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const MetadataEditorScreen(),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Draft'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Updated');
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Modified'), findsOneWidget);

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration is InputDecoration &&
            (widget.decoration as InputDecoration).hintText == 'Add a tag',
      ),
      'tag-x',
    );
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('tag-x'), findsOneWidget);

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    expect(find.text('Sample Note'), findsOneWidget);
    expect(find.text('item'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Note saved'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(fakeRepo.savedNotes, hasLength(1));

    await tester.tap(find.text('Commit'));
    await tester.pumpAndSettle();

    expect(find.text('Committed'), findsOneWidget);
    expect(fakeRepo.committedNotes, hasLength(1));
  });

  testWidgets('MetadataEditorScreen handles note loading error',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesListProvider.overrideWith((ref) => Future.value(const [note])),
          noteProvider(note.id)
              .overrideWith((ref) => Future.error(Exception('boom'))),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const MetadataEditorScreen(),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Error loading note'), findsOneWidget);
  });
}
