import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore_for_file: use_super_parameters

import 'package:alexandria/logic/content_repository.dart';
import 'package:alexandria/models/workspace_models.dart';
import 'package:alexandria/providers/workspace_providers.dart';
import 'package:alexandria/ui/workspace/annotations_notes_screen.dart';

class _FakeContentRepository extends ContentRepository {
  _FakeContentRepository(Ref ref) : super(ref);

  final addedAnnotations = <Annotation>[];

  @override
  Future<void> addAnnotation(String docId, Annotation annotation) async {
    addedAnnotations.add(annotation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const docId = 'doc-1';

  final annotations = [
    Annotation(
      id: 'a-1',
      docId: docId,
      text: 'Discuss preservation trade-offs.',
      quote: 'Decentralized storage shifts the burden.',
      author: 'Reader A',
      createdAt: DateTime(2026, 1, 10, 9, 30),
    ),
    Annotation(
      id: 'a-2',
      docId: docId,
      text: 'Compare with local-first principles.',
      author: 'Reader B',
      createdAt: DateTime(2026, 1, 11, 14, 15),
    ),
  ];

  testWidgets('AnnotationsNotesScreen renders annotations', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          annotationsProvider(docId)
              .overrideWith((ref) => Stream.value(annotations)),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const AnnotationsNotesScreen(docId: docId),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Annotations & Notes'), findsOneWidget);
    expect(find.text('Annotations'), findsOneWidget);
    expect(find.text('Discuss preservation trade-offs.'), findsOneWidget);
    expect(find.text('Compare with local-first principles.'), findsOneWidget);
  });

  testWidgets('AnnotationsNotesScreen handles empty annotations',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          annotationsProvider(docId)
              .overrideWith((ref) => Stream.value(const <Annotation>[])),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const AnnotationsNotesScreen(docId: docId),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No annotations yet.'), findsOneWidget);
  });

  testWidgets('AnnotationsNotesScreen handles error state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          annotationsProvider(docId)
              .overrideWith((ref) => Stream.error(Exception('failed'))),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const AnnotationsNotesScreen(docId: docId),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Error:'), findsOneWidget);
  });

  testWidgets('AnnotationsNotesScreen adds a note', (tester) async {
    late _FakeContentRepository fakeRepo;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          annotationsProvider(docId)
              .overrideWith((ref) => Stream.value(const <Annotation>[])),
          contentRepositoryProvider.overrideWith((ref) {
            fakeRepo = _FakeContentRepository(ref);
            return fakeRepo;
          }),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const AnnotationsNotesScreen(docId: docId),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextField).last, 'new annotation');
    await tester.tap(find.byIcon(Icons.add_comment_outlined));
    await tester.pump(const Duration(milliseconds: 100));

    expect(fakeRepo.addedAnnotations, hasLength(1));
    expect(fakeRepo.addedAnnotations.first.text, 'new annotation');
  });

  testWidgets('AnnotationsNotesScreen does not submit without a docId',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const AnnotationsNotesScreen(),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No document selected'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'orphan note');
    await tester.tap(find.byIcon(Icons.add_comment_outlined));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('orphan note'), findsOneWidget);
  });
}
