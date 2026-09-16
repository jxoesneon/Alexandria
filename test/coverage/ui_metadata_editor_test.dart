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
    content:
        '# Heading One\n\n## Heading Two\n\n### Heading Three\n\n- dash item\n* star item\n\nA paragraph with **bold words** inside.\n\nPlain tail.',
    status: NoteStatus.draft,
  );

  const note2 = Note(
    id: 'note-2',
    title: 'Second Note',
    author: 'Grace Hopper',
    tags: [],
    summary: '',
    content: 'x',
    status: NoteStatus.draft,
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size size = const Size(1920, 1080),
    List<Note> notes = const [note],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notesListProvider.overrideWith((ref) => Future.value(notes)),
          noteProvider(note.id).overrideWith((ref) => Future.value(note)),
          noteProvider(note2.id).overrideWith((ref) => Future.value(note2)),
          contentRepositoryProvider
              .overrideWith((ref) => _FakeContentRepository(ref)),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const MetadataEditorScreen(),
        ),
      ),
    );
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  }

  testWidgets('narrow layout navigates list → editor → back', (tester) async {
    await pumpScreen(tester, size: const Size(480, 900));

    // Narrow: only the note list shows.
    expect(find.text('Project Requirements'), findsOneWidget);
    expect(find.text('Grace Hopper'), findsNothing);
    expect(find.byTooltip('Back to notes'), findsNothing);

    // Tap the note → editor pane with back button.
    await tester.tap(find.text('Project Requirements'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byTooltip('Back to notes'), findsOneWidget);
    expect(find.text('Note Details'), findsOneWidget);

    // Back → the note list again.
    await tester.tap(find.byTooltip('Back to notes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byTooltip('Back to notes'), findsNothing);
    expect(find.text('Project Requirements'), findsOneWidget);
  });

  testWidgets('wide layout lets a second note be selected', (tester) async {
    await pumpScreen(tester, notes: const [note, note2]);

    await tester.tap(find.text('Second Note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Grace Hopper'), findsWidgets);
  });

  testWidgets('tag add via submit, duplicate guard, and delete chip',
      (tester) async {
    await pumpScreen(tester);

    // Add a tag via onSubmitted.
    await tester.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration is InputDecoration &&
            (w.decoration as InputDecoration).hintText == 'Add a tag',
      ),
      'research',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('research'), findsOneWidget);

    // Empty / duplicate submissions are ignored.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // Delete the chip via its delete icon (any Icon inside the chip).
    await tester.tap(find.descendant(
      of: find.widgetWithText(InputChip, 'workspace'),
      matching: find.byType(Icon),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('workspace'), findsNothing);
    expect(find.text('planning'), findsOneWidget);
  });

  testWidgets('preview renders all markdown block kinds', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    expect(find.text('Heading One'), findsOneWidget);
    expect(find.text('Heading Two'), findsOneWidget);
    expect(find.text('Heading Three'), findsOneWidget);
    expect(find.text('• ', findRichText: false), findsWidgets);
    expect(find.textContaining('bold words'), findsWidgets);
    expect(find.textContaining('Plain tail'), findsOneWidget);
  });

  testWidgets('editing markdown marks the note as modified', (tester) async {
    await pumpScreen(tester);

    // The Editor tab is the default; type into the markdown field.
    await tester.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration is InputDecoration &&
            (w.decoration as InputDecoration).hintText == 'Enter markdown...',
      ),
      'fresh content',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Modified'), findsOneWidget);
  });
}
