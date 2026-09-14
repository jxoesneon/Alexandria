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

  testWidgets('switches to editions and legal tabs, toggles tts and zoom', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(createSubject(showSidebar: true));
    await tester.pumpAndSettle();

    // Toggle TTS
    await tester.tap(find.byTooltip('Toggle Text-to-Speech (TTS)'));
    await tester.pump();

    // Toggle Font
    await tester.tap(find.byTooltip('Toggle OpenDyslexic Font'));
    await tester.pump();

    // Zoom in and out
    await tester.tap(find.byTooltip('Zoom In'));
    await tester.pump();
    await tester.tap(find.byTooltip('Zoom Out'));
    await tester.pump();

    // Switch to Editions tab
    await tester.tap(find.text('Editions'));
    await tester.pumpAndSettle();

    // Switch to Legal tab
    await tester.tap(find.text('Legal'));
    await tester.pumpAndSettle();

    // Switch to TOC tab
    await tester.tap(find.text('TOC'));
    await tester.pumpAndSettle();
  });
}
