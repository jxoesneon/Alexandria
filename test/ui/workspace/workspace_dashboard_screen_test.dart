import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/models/workspace_models.dart';
import 'package:alexandria/providers/workspace_providers.dart';
import 'package:alexandria/ui/workspace/annotations_notes_screen.dart';
import 'package:alexandria/ui/workspace/ingestion_pipeline_screen.dart';
import 'package:alexandria/ui/workspace/metadata_editor_screen.dart';
import 'package:alexandria/ui/workspace/workspace_dashboard_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('WorkspaceDashboardScreen renders workspaces and activity feed',
      (tester) async {
    const workspaces = [
      Workspace(id: 'ws-1', name: 'Project Alpha', pendingTasks: 2),
      Workspace(id: 'ws-2', name: 'Draft Curation', pendingTasks: 5),
    ];
    final activity = [
      ActivityEvent(
        title: 'Import Completed',
        description: 'Ingested 5 EPUBs to Library',
        timestamp: DateTime(2026, 1, 10, 9, 30),
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspacesProvider
              .overrideWith((ref) => Stream.value(workspaces)),
          activityFeedProvider.overrideWith((ref) => Stream.value(activity)),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const WorkspaceDashboardScreen(),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Workspace'), findsOneWidget);
    expect(find.text('Ongoing Tasks'), findsOneWidget);
    expect(find.text('Project Alpha'), findsOneWidget);
    expect(find.text('Draft Curation'), findsOneWidget);
    expect(find.text('2 pending tasks'), findsOneWidget);
    expect(find.text('5 pending tasks'), findsOneWidget);
    expect(find.text('Activity Feed'), findsOneWidget);
    expect(find.text('Import Completed'), findsOneWidget);
  });

  testWidgets('WorkspaceDashboardScreen handles empty state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspacesProvider.overrideWith((ref) => Stream.value([])),
          activityFeedProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const WorkspaceDashboardScreen(),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No workspaces yet.'), findsOneWidget);
    expect(find.text('No recent activity.'), findsOneWidget);
  });

  testWidgets('WorkspaceDashboardScreen handles error state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspacesProvider
              .overrideWith((ref) => Stream.error(Exception('boom'))),
          activityFeedProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const WorkspaceDashboardScreen(),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Error loading workspaces'), findsOneWidget);
  });

  testWidgets('WorkspaceDashboardScreen handles activity feed error',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspacesProvider.overrideWith((ref) => Stream.value([])),
          activityFeedProvider
              .overrideWith((ref) => Stream.error(Exception('feed boom'))),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const WorkspaceDashboardScreen(),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Error loading activity'), findsOneWidget);
  });

  testWidgets('WorkspaceDashboardScreen action buttons push child routes',
      (tester) async {
    const workspace =
        Workspace(id: 'ws-1', name: 'Project Alpha', pendingTasks: 2);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkspacesProvider
              .overrideWith((ref) => Stream.value(const [workspace])),
          activityFeedProvider.overrideWith((ref) => Stream.value([])),
          ingestionQueueProvider
              .overrideWith((ref) => Stream.value(const IngestionState())),
          notesListProvider.overrideWith((ref) => Future.value(const <Note>[])),
          annotationsProvider('')
              .overrideWith((ref) => Stream.value(const <Annotation>[])),
          annotationsProvider(workspace.id)
              .overrideWith((ref) => Stream.value(const <Annotation>[])),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const WorkspaceDashboardScreen(),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('New Import'));
    await tester.pumpAndSettle();

    expect(find.text('Ingestion Pipeline'), findsOneWidget);

    Navigator.of(tester.element(find.byType(IngestionPipelineScreen))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Note'));
    await tester.pumpAndSettle();

    expect(find.text('Annotations & Notes'), findsOneWidget);

    Navigator.of(tester.element(find.byType(AnnotationsNotesScreen))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Metadata'));
    await tester.pumpAndSettle();

    expect(find.text('Metadata Editor'), findsOneWidget);

    Navigator.of(tester.element(find.byType(MetadataEditorScreen))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(find.text('Annotations & Notes'), findsOneWidget);
  });
}
