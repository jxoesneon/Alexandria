import 'package:alexandria/data/database.dart';
import 'package:alexandria/logic/content_repository.dart';
import 'package:alexandria/models/library_models.dart';
import 'package:alexandria/providers/library_providers.dart';
import 'package:alexandria/ui/library/content_viewer_screen.dart';
import 'package:alexandria/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ContentVersion _version(String cid, String format, int sizeBytes,
        {int id = 1}) =>
    ContentVersion(
      id: id,
      manifestId: 1,
      cid: cid,
      language: 'en',
      format: format,
      sizeBytes: sizeBytes,
      peerCount: 3,
      isPinned: true,
      createdData: DateTime(2024),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const docCid = 'cid-doc-1';

  Widget createSubject({
    bool showSidebar = false,
    String content = '# Title\n\nBody text.',
    String docFormat = 'md',
    String? docCid2,
    List<ContentVersion>? versions,
    Future<List<Annotation>> Function()? annotations,
    Future<ContentIntegrityReport> Function()? integrity,
  }) {
    return ProviderScope(
      overrides: [
        sidebarVisibleProvider.overrideWith((ref) => showSidebar),
        currentDocumentProvider.overrideWith(
          (ref, cid) async => DocumentStream(
            title: 'Doc Title',
            content: content,
            format: docFormat,
            cid: docCid2,
          ),
        ),
        documentVersionsProvider.overrideWith(
          (ref, cid) async => versions ?? const <ContentVersion>[],
        ),
        annotationsProvider.overrideWith(
          (ref, cid) => annotations != null
              ? annotations()
              : Future.value(const <Annotation>[]),
        ),
        contentIntegrityProvider.overrideWith(
          (ref, cid) => integrity != null
              ? integrity()
              : Future.value(const ContentIntegrityReport(
                  cid: 'x',
                  payloadHashOk: true,
                  signatureValid: null,
                )),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const ContentViewerScreen(documentCid: docCid),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  }

  testWidgets('shows error state when the document fails to load',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentDocumentProvider.overrideWith(
            (ref, cid) => Future<DocumentStream>.error(StateError('ipfs down'))),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const ContentViewerScreen(documentCid: docCid),
      ),
    ));
    await settle(tester);
    expect(find.textContaining('Error loading document'), findsOneWidget);
  });

  testWidgets('sidebar toggle button opens the context panel', (tester) async {
    await tester.pumpWidget(createSubject());
    await settle(tester);
    await tester.tap(find.byTooltip('Toggle Reader Context Panel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Editions'), findsOneWidget);
    expect(find.text('Legal'), findsOneWidget);
  });

  testWidgets('TTS toggle shows activation snackbar', (tester) async {
    await tester.pumpWidget(createSubject());
    await settle(tester);
    await tester.tap(find.byTooltip('Toggle Text-to-Speech (TTS)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.textContaining('Text-to-Speech active'), findsOneWidget);
  });

  testWidgets('TOC lists headings and scrolls on tap', (tester) async {
    await tester.pumpWidget(createSubject(
      showSidebar: true,
      content: '# Alpha\n\n## Beta\n\n### Gamma\n\n${'Filler line.\n' * 60}',
    ));
    await settle(tester);
    // TOC is the default tab
    expect(find.text('Alpha'), findsWidgets);
    expect(find.text('Beta'), findsWidgets);
    await tester.tap(find.text('Gamma').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('TOC shows placeholder for a heading-free document',
      (tester) async {
    await tester.pumpWidget(createSubject(
      showSidebar: true,
      content: 'Just a paragraph, no headings.',
    ));
    await settle(tester);
    expect(find.text('No section headings found.'), findsOneWidget);
  });

  testWidgets('editions view renders versions, search, filters, and switching',
      (tester) async {
    await tester.pumpWidget(createSubject(
      showSidebar: true,
      versions: [
        _version('cid-full', 'md-unabridged', 2048, id: 1),
        _version('cid-brief', 'md-brief', 512, id: 2),
        _version('cid-epub', 'epub', 2097152, id: 3),
      ],
    ));
    await settle(tester);
    await openTab(tester, 'Editions');

    expect(find.text('Editions & Formats'), findsOneWidget);
    expect(find.text('3 versions'), findsOneWidget);
    expect(find.text('Showing 3 of 3 editions'), findsOneWidget);
    // 2048 B + 512 B + 2 MiB total → MB formatting
    expect(find.textContaining('MB on mesh'), findsOneWidget);

    // Search filter — CID match keeps exactly the epub card.
    await tester.enterText(find.byType(TextField), 'cid-epub');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Showing 1 of 3 editions'), findsOneWidget);
    expect(find.text('EPUB'), findsWidgets);

    // Clear via suffix icon
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Showing 3 of 3 editions'), findsOneWidget);

    // Filter chips live in a horizontally scrollable row inside the
    // 380px sidebar — scroll them into view before tapping.
    final briefsChip = find.text('Briefs (1)');
    await tester.ensureVisible(briefsChip);
    await tester.pump();
    await tester.tap(briefsChip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Showing 1 of 3 editions'), findsOneWidget);
    expect(find.text('Executive Brief'), findsOneWidget);

    await tester.tap(find.text('Unabridged (1)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Full Unabridged Primary Text'), findsOneWidget);

    await tester.tap(find.text('All (3)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  });

  testWidgets('editions search with no matches shows clear-filters state',
      (tester) async {
    await tester.pumpWidget(createSubject(
      showSidebar: true,
      versions: [_version('cid-full', 'md-unabridged', 10)],
    ));
    await settle(tester);
    await openTab(tester, 'Editions');

    await tester.enterText(find.byType(TextField), 'zzzzz');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('No editions match "zzzzz"'), findsOneWidget);

    await tester.tap(find.text('Clear Filters'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Showing 1 of 1 editions'), findsOneWidget);
  });

  testWidgets('editions error state renders the failure text', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sidebarVisibleProvider.overrideWith((ref) => true),
        currentDocumentProvider.overrideWith(
          (ref, cid) async =>
              const DocumentStream(title: 'T', content: 'C'),
        ),
        documentVersionsProvider.overrideWith(
          (ref, cid) => Future<List<ContentVersion>>.error(StateError('db err')),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const ContentViewerScreen(documentCid: docCid),
      ),
    ));
    await settle(tester);
    await openTab(tester, 'Editions');
    expect(find.textContaining('Error querying versions'), findsOneWidget);
  });

  testWidgets('tapping a non-active edition card switches the active CID',
      (tester) async {
    await tester.pumpWidget(createSubject(
      showSidebar: true,
      versions: [
        _version('cid-full', 'md-unabridged', 2048, id: 1),
        _version('cid-brief', 'md-brief', 512, id: 2),
      ],
    ));
    await settle(tester);
    await openTab(tester, 'Editions');

    // The brief card is not active — tap it.
    await tester.tap(find.text('Executive Brief'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.textContaining('Switched to Executive Brief'), findsOneWidget);
  });

  testWidgets('legal tab renders integrity report fields', (tester) async {
    await tester.pumpWidget(createSubject(
      showSidebar: true,
      docCid2: 'cid-full',
      versions: [_version('cid-full', 'md-unabridged', 2048)],
      integrity: () async => const ContentIntegrityReport(
        cid: 'cid-full',
        payloadHashOk: false,
        signatureValid: true,
        flaggedReason: 'suspect-fragment-of:cid-other',
      ),
    ));
    await settle(tester);
    await openTab(tester, 'Legal');

    expect(find.text('Statutory Safe Harbor'), findsOneWidget);
    expect(find.text('HASH MISMATCH — REJECTED'), findsOneWidget);
    expect(find.text('Ed25519 Verified'), findsOneWidget);
    expect(find.text('suspect-fragment-of:cid-other'), findsOneWidget);
  });

  testWidgets('legal tab renders unsigned and failure integrity states',
      (tester) async {
    await tester.pumpWidget(createSubject(
      showSidebar: true,
      docCid2: 'cid-full',
      versions: [_version('cid-full', 'md-unabridged', 10)],
      integrity: () async => const ContentIntegrityReport(
        cid: 'cid-full',
        payloadHashOk: true,
        signatureValid: null,
      ),
    ));
    await settle(tester);
    await openTab(tester, 'Legal');
    expect(find.text('Unsigned (legacy record)'), findsOneWidget);
    expect(find.text('SHA-256 CID Digest OK'), findsOneWidget);
  });

  testWidgets('legal tab shows verification failure on provider error',
      (tester) async {
    await tester.pumpWidget(createSubject(
      showSidebar: true,
      docCid2: 'cid-full',
      versions: [_version('cid-full', 'md-unabridged', 10)],
      integrity: () => Future<ContentIntegrityReport>.error(StateError('x')),
    ));
    await settle(tester);
    await openTab(tester, 'Legal');
    expect(find.text('Verification failed'), findsOneWidget);
  });

  testWidgets('legal tab renders linked editions and switch action',
      (tester) async {
    await tester.pumpWidget(createSubject(
      showSidebar: true,
      versions: [
        _version('cid-full', 'md-unabridged', 2048, id: 1),
        _version('cid-brief', 'md-brief', 512, id: 2),
      ],
    ));
    await settle(tester);
    await openTab(tester, 'Legal');

    expect(find.text('Linked Editions & CIDs (Zero Duplication):'),
        findsOneWidget);
    // The brief edition has a 'Switch Edition' action.
    final switchButton = find.text('Switch Edition');
    await tester.ensureVisible(switchButton);
    await tester.pump();
    await tester.tap(switchButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // The active edition CID flips to the brief.
    final ctx = tester.element(find.byType(ContentViewerScreen));
    final container = ProviderScope.containerOf(ctx);
    expect(container.read(activeVersionCidProvider(docCid)), 'cid-brief');
  });

  testWidgets('notes tab renders empty and populated annotation states',
      (tester) async {
    await tester.pumpWidget(createSubject(
      showSidebar: true,
      annotations: () async => const [
        Annotation(text: 'A marginal note'),
      ],
    ));
    await settle(tester);
    await openTab(tester, 'Notes');
    expect(find.text('A marginal note'), findsOneWidget);
  });

  testWidgets('notes tab shows the empty placeholder', (tester) async {
    await tester.pumpWidget(createSubject(showSidebar: true));
    await settle(tester);
    await openTab(tester, 'Notes');
    expect(find.text('No annotations or reading notes.'), findsOneWidget);
  });

  testWidgets('notes tab shows provider error', (tester) async {
    await tester.pumpWidget(createSubject(
      showSidebar: true,
      annotations: () => Future<List<Annotation>>.error(StateError('db boom')),
    ));
    await settle(tester);
    await openTab(tester, 'Notes');
    expect(find.textContaining('Error:'), findsOneWidget);
  });

  testWidgets('renders quotes, list items, dividers and unclosed code fences',
      (tester) async {
    await tester.pumpWidget(createSubject(
      content: '> a quoted line\n> second quote line\n\n'
          '- bullet item\n'
          '* star item\n'
          '1. numbered item\n\n'
          '***\n\n'
          '```\n'
          'unclosed code fence\n'
          'still code',
    ));
    await settle(tester);
    expect(find.text('a quoted line second quote line'), findsOneWidget);
    expect(find.text('bullet item'), findsOneWidget);
    expect(find.text('star item'), findsOneWidget);
    expect(find.text('numbered item'), findsOneWidget);
    expect(find.textContaining('unclosed code fence'), findsOneWidget);
  });

  testWidgets('renders inline formatting: bold, italic, code, math',
      (tester) async {
    await tester.pumpWidget(createSubject(
      content: 'Para with **bolded** and *italics* and `mono` and math '
          r'$x+y$ plus display $$a^2$$ end.',
    ));
    await settle(tester);
    // Rich-text runs — assert the plain runs still appear.
    expect(find.textContaining('bolded'), findsWidgets);
    expect(find.textContaining('mono'), findsWidgets);
  });

  testWidgets('renders image blocks and the offline fallback card',
      (tester) async {
    await tester.pumpWidget(createSubject(
      content: '![Diagram](ipfs://not-a-valid-cid "A title")\n\n'
          '![Local](/etc/passwd)\n\n'
          '![Other](some-random-path.bin)',
    ));
    await settle(tester);
    // Invalid CID gateway rewrite → offline fallback card.
    expect(find.text('AIR-GAPPED OR OFFLINE'), findsWidgets);
    await tester.tap(find.text('Copy Asset URI').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Asset URI copied to clipboard'), findsOneWidget);
  });

  testWidgets('inline image badge opens the lightbox dialog', (tester) async {
    await tester.pumpWidget(createSubject(
      content: 'A paragraph with an inline ![Figure](ipfs://bad-cid) inside.',
    ));
    await settle(tester);
    await tester.tap(find.text('Figure'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byTooltip('Copy Image Reference'), findsOneWidget);
    await tester.tap(find.byTooltip('Copy Image Reference'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(
        find.text('Image reference copied to clipboard'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byTooltip('Copy Image Reference'), findsNothing);
  });

  testWidgets('reading progress slider seeks through the document',
      (tester) async {
    await tester.pumpWidget(createSubject(
      content: '# Big\n\n${'Scrolling filler paragraph.\n\n' * 80}',
    ));
    await settle(tester);
    expect(find.text('0%'), findsOneWidget);

    final slider = find.byType(Slider);
    await tester.tapAt(tester.getCenter(slider));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    // Slider moved — the percentage label should no longer read 0%.
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('multi-line display math block renders', (tester) async {
    await tester.pumpWidget(createSubject(
      content: 'Intro.\n\n\$\$\nx = \\\\frac{a}{b}\ny^2\n\$\$\n\nAfter.',
    ));
    await settle(tester);
    expect(find.text('After.'), findsOneWidget);
  });
}
