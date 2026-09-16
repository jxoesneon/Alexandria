import 'package:alexandria/data/database.dart';
import 'package:alexandria/models/library_models.dart';
import 'package:alexandria/providers/library_providers.dart';
import 'package:alexandria/ui/library/content_viewer_screen.dart';
import 'package:alexandria/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const docCid = 'cid-rich-doc';

  const richMarkdown = '''
# Heading One
## Heading Two
### Heading Three

---

> This is a blockquote about digital preservation.

```dart
void main() {
  print("Hello Alexandria");
}
```

\$\$
E = mc^2
\$\$

* First item in bullet list
* Second item in bullet list
1. Numbered item one
2. Numbered item two

A paragraph with [an external link](https://alexandria.org) and some bold **text**.
''';

  final fakeVersions = [
    ContentVersion(
      id: 1,
      manifestId: 1,
      cid: docCid,
      language: 'en',
      format: 'md-unabridged',
      sizeBytes: 10240,
      peerCount: 12,
      isPinned: true,
      createdData: DateTime.now(),
      lastHealthCheck: DateTime.now(),
      publisherPubkey: null,
      signature: null,
      flaggedReason: null,
    ),
    ContentVersion(
      id: 2,
      manifestId: 1,
      cid: 'cid-brief-doc',
      language: 'en',
      format: 'md-brief',
      sizeBytes: 2048,
      peerCount: 8,
      isPinned: true,
      createdData: DateTime.now(),
      lastHealthCheck: DateTime.now(),
      publisherPubkey: null,
      signature: null,
      flaggedReason: null,
    ),
  ];

  Widget createSubject({
    bool showSidebar = true,
    String? customContent,
    String? format,
  }) {
    return ProviderScope(
      overrides: [
        sidebarVisibleProvider.overrideWith((ref) => showSidebar),
        currentDocumentProvider.overrideWith(
          (ref, cid) async => DocumentStream(
            title: 'Decentralized Preservation In-Depth',
            content: customContent ?? richMarkdown,
            cid: docCid,
            format: format ?? 'md-unabridged',
          ),
        ),
        documentVersionsProvider.overrideWith(
          (ref, cid) async => fakeVersions,
        ),
        annotationsProvider.overrideWith(
          (ref, cid) async => const [
            Annotation(text: 'Note 1: Cryptographic integrity is paramount.'),
          ],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const ContentViewerScreen(documentCid: docCid),
      ),
    );
  }

  group('ContentViewerScreen Rich Elements Tests', () {
    testWidgets('renders all rich markdown block types', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createSubject(showSidebar: true));
      await tester.pumpAndSettle();

      // Headings
      expect(find.text('Heading One'), findsWidgets);
      expect(find.text('Heading Two'), findsWidgets);
      expect(find.text('Heading Three'), findsWidgets);

      // Quote & Code
      expect(find.textContaining('This is a blockquote'), findsOneWidget);
      expect(find.textContaining('void main()'), findsOneWidget);

      // Math display
      expect(find.text('FORMULA • KaTeX'), findsOneWidget);
      await tester.tap(find.text('Copy LaTeX'));
      await tester.pump();

      // Lists
      expect(find.text('First item in bullet list'), findsOneWidget);
      expect(find.text('Numbered item one'), findsOneWidget);

      // Edition badge in header
      expect(find.text('Edition: '), findsOneWidget);
      expect(find.text('Full Unabridged'), findsOneWidget);

      // Tap edition pill to open editions sidebar
      await tester.tap(find.text('Full Unabridged'));
      await tester.pumpAndSettle();

      // Progress slider interaction
      final sliderFinder = find.byType(Slider);
      expect(sliderFinder, findsOneWidget);
      await tester.tap(sliderFinder);
      await tester.pumpAndSettle();
    });

    testWidgets('renders executive brief variant styling', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createSubject(
        showSidebar: false,
        format: 'md-brief',
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('AUTHENTIC EXECUTIVE BRIEF'), findsOneWidget);
    });

    testWidgets('sidebar displays TOC headings and allows clicking',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createSubject(showSidebar: true));
      await tester.pumpAndSettle();

      // In TOC tab
      await tester.tap(find.text('TOC'));
      await tester.pumpAndSettle();

      final headingFinder = find.text('Heading One');
      expect(headingFinder, findsWidgets);

      // Tap heading in TOC
      await tester.tap(headingFinder.last);
      await tester.pumpAndSettle();

      // Switch to Legal tab
      await tester.tap(find.text('Legal'));
      await tester.pumpAndSettle();
      expect(find.text('Statutory Safe Harbor'), findsOneWidget);
    });
  });
}
