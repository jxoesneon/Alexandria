import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/models/workspace_models.dart';
import 'package:alexandria/providers/workspace_providers.dart';
import 'package:alexandria/ui/workspace/ingestion_pipeline_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('IngestionPipelineScreen renders queue items', (tester) async {
    const state = IngestionState(
      overallProgress: 0.6,
      statusMessage: '1 of 2 item(s) completed',
      queue: [
        IngestionItem(
          id: 'i-1',
          filename: 'document.pdf',
          progress: 1.0,
          status: IngestionStatus.completed,
        ),
        IngestionItem(
          id: 'i-2',
          filename: 'dataset.csv',
          progress: 0.4,
          status: IngestionStatus.processing,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ingestionQueueProvider.overrideWith((ref) => Stream.value(state)),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const IngestionPipelineScreen(),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Ingestion Pipeline'), findsOneWidget);
    expect(find.text('Import Queue'), findsOneWidget);
    expect(find.text('document.pdf'), findsOneWidget);
    expect(find.text('dataset.csv'), findsOneWidget);
    expect(find.text('Browse Files'), findsOneWidget);
  });

  testWidgets('IngestionPipelineScreen handles empty queue', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ingestionQueueProvider
              .overrideWith((ref) => Stream.value(const IngestionState())),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const IngestionPipelineScreen(),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Queue is empty.'), findsOneWidget);
  });

  testWidgets('IngestionPipelineScreen handles error state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ingestionQueueProvider.overrideWith(
              (ref) => Stream.error(Exception('pipeline failed'))),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const IngestionPipelineScreen(),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Error:'), findsOneWidget);
  });

  testWidgets('IngestionPipelineScreen renders all statuses and details pane',
      (tester) async {
    final state = const IngestionState(
      queue: [
        IngestionItem(
          id: 'i-pending',
          filename: 'pending.pdf',
          progress: 0.0,
          status: IngestionStatus.pending,
        ),
        IngestionItem(
          id: 'i-processing',
          filename: 'processing.csv',
          progress: 0.5,
          status: IngestionStatus.processing,
        ),
        IngestionItem(
          id: 'i-completed',
          filename: 'completed.md',
          progress: 1.0,
          status: IngestionStatus.completed,
        ),
        IngestionItem(
          id: 'i-error',
          filename: 'error.txt',
          progress: 0.0,
          status: IngestionStatus.error,
        ),
        IngestionItem(
          id: 'i-conflict',
          filename: 'conflict.epub',
          progress: 0.0,
          status: IngestionStatus.conflict,
          conflictMessage: 'Metadata conflict: duplicate title.',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ingestionQueueProvider.overrideWith((ref) => Stream.value(state)),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const IngestionPipelineScreen(),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('pending.pdf'), findsOneWidget);
    expect(find.text('processing.csv'), findsOneWidget);
    expect(find.text('completed.md'), findsOneWidget);
    expect(find.text('error.txt'), findsOneWidget);
    expect(find.text('conflict.epub'), findsOneWidget);

    await tester.tap(find.text('completed.md'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Item Details'), findsOneWidget);
    expect(find.text('COMPLETED'), findsWidgets);

    await tester.tap(find.text('conflict.epub'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Metadata conflict: duplicate title.'), findsOneWidget);
    expect(find.text('Resolve Conflict'), findsOneWidget);

    await tester.tap(find.text('Resolve Conflict'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Overwrite'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 100));
  });
}
