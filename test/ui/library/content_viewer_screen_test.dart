import 'package:alexandria/models/library_models.dart';
import 'package:alexandria/providers/library_providers.dart';
import 'package:alexandria/ui/library/content_viewer_screen.dart';
import 'package:alexandria/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const docCid = 'cid-doc-1';

  Widget createSubject({bool showSidebar = false}) {
    return ProviderScope(
      overrides: [
        sidebarVisibleProvider.overrideWith((ref) => showSidebar),
        currentDocumentProvider.overrideWith(
          (ref, cid) async => const DocumentStream(
            title: 'The Decentralized Web',
            content: 'A deep dive into decentralized archives.',
          ),
        ),
        annotationsProvider.overrideWith(
          (ref, cid) async => const [
            Annotation(text: 'Key insight about preservation'),
            Annotation(text: 'Note on peer-to-peer distribution'),
          ],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const ContentViewerScreen(documentCid: docCid),
      ),
    );
  }

  testWidgets('renders document title and content', (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Archival Reader & Content Viewer'), findsOneWidget);
    expect(find.text('The Decentralized Web'), findsOneWidget);
    expect(
        find.text('A deep dive into decentralized archives.'), findsOneWidget);
  });

  testWidgets('renders annotations in sidebar', (tester) async {
    await tester.pumpWidget(createSubject(showSidebar: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Annotations live under the Notes tab of the context panel
    await tester.tap(find.text('Notes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Key insight about preservation'), findsOneWidget);
    expect(find.text('Note on peer-to-peer distribution'), findsOneWidget);
  });
}
