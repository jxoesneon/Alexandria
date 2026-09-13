import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alexandria/data/database.dart';
import 'package:alexandria/models/library_models.dart';
import 'package:alexandria/providers/library_providers.dart';
import 'package:alexandria/ui/library/content_viewer_screen.dart';

void main() {
  testWidgets('Edition indicator and side panel search/filter interaction', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    const docUuid = 'doc-uuid-einstein-1905';
    const unabridgedCid = 'bafyunabridged1234567890';
    const briefCid = 'bafybrief1234567890';

    final unabridgedVersion = ContentVersion(
      id: 1,
      manifestId: 1,
      cid: unabridgedCid,
      language: 'en',
      format: 'md-unabridged',
      sizeBytes: 11600,
      peerCount: 4,
      isPinned: true,
      createdData: DateTime(2026, 1, 1),
    );

    final briefVersion = ContentVersion(
      id: 2,
      manifestId: 1,
      cid: briefCid,
      language: 'en',
      format: 'md-brief',
      sizeBytes: 2400,
      peerCount: 2,
      isPinned: true,
      createdData: DateTime(2026, 1, 1),
    );

    const docStreamUnabridged = DocumentStream(
      cid: unabridgedCid,
      title: 'On the Electrodynamics of Moving Bodies',
      content: '# Full Unabridged Edition\n\nContent...',
      format: 'md-unabridged',
      sizeBytes: 11600,
    );

    const docStreamBrief = DocumentStream(
      cid: briefCid,
      title: 'On the Electrodynamics of Moving Bodies (Brief)',
      content: '# Executive Brief\n\nSummary...',
      format: 'md-brief',
      sizeBytes: 2400,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentDocumentProvider(docUuid).overrideWith((ref) async {
            final activeCid = ref.watch(activeVersionCidProvider(docUuid));
            if (activeCid == briefCid) {
              return docStreamBrief;
            }
            return docStreamUnabridged;
          }),
          documentVersionsProvider(docUuid).overrideWith((ref) async => [
            unabridgedVersion,
            briefVersion,
          ]),
        ],
        child: const MaterialApp(
          home: ContentViewerScreen(documentCid: docUuid),
        ),
      ),
    );

    // Initial pump and wait for async providers to resolve
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    // 1. Verify Edition indicator is rendered with kebab icon
    expect(find.text('Edition: '), findsOneWidget);
    expect(find.text('Full Unabridged'), findsWidgets);
    expect(find.text('2 available'), findsOneWidget);

    // 2. Click the kebab icon button to open the Editions side panel
    final kebabFinder = find.byTooltip('Open Editions Catalog (2 versions)');
    expect(kebabFinder, findsOneWidget);
    await tester.tap(kebabFinder);
    await tester.pump(const Duration(milliseconds: 200));

    // 3. Verify side panel opened with Editions tab selected
    expect(find.text('Editions & Formats'), findsOneWidget);
    expect(find.text('2 versions'), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);

    // 4. Test searching in side panel
    await tester.enterText(find.byType(TextField), 'brief');
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Showing 1 of 2 editions'), findsOneWidget);
    expect(find.text('Executive Brief'), findsWidgets);

    // 5. Clear search query
    final clearFinder = find.byIcon(Icons.clear);
    expect(clearFinder, findsOneWidget);
    await tester.tap(clearFinder);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Showing 2 of 2 editions'), findsOneWidget);

    // 6. Switch to Executive Brief
    final switchButtonFinder = find.text('Switch to this Edition');
    expect(switchButtonFinder, findsOneWidget);
    await tester.tap(switchButtonFinder);
    await tester.pump(const Duration(milliseconds: 200));

    // Verify switched to brief
    expect(find.text('Switched to Executive Brief (md-brief)'), findsOneWidget);
  });
}
