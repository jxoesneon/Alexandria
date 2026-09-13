import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:alexandria/data/database.dart';
import 'package:alexandria/models/library_models.dart';
import 'package:alexandria/providers/library_providers.dart';
import 'package:alexandria/ui/library/content_viewer_screen.dart';

void main() {
  group('Reader Scientific Math, Symbol & Image Rendering', () {
    testWidgets('renders display KaTeX math, inline math, and figure images with captions',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const testDocCid = 'bafytestmathandimages1234567890';
      const testMarkdownContent = r'''# On the Electrodynamics of Moving Bodies
**Albert Einstein**

## Fundamental Formulations

The average energy of an oscillator resonator satisfies:

$$\bar{E} = \frac{R}{N} T$$

In photo-electric emission, the maximum kinetic energy is:

$$E_{\max} = h\nu - P$$

where $h\nu$ is the energy quantum and $\alpha$-machine computes digits.

## Experimental Crystallography

![Double Helix X-ray Diffraction Photo 51](https://example.org/photo51.png)

This establishes the B-form helical structure.
''';

      const testStream = DocumentStream(
        cid: testDocCid,
        title: 'On the Electrodynamics of Moving Bodies',
        content: testMarkdownContent,
        format: 'md-unabridged',
        sizeBytes: 1024,
      );

      final testVersion = ContentVersion(
        id: 1,
        manifestId: 1,
        cid: testDocCid,
        language: 'en',
        format: 'md-unabridged',
        sizeBytes: 1024,
        peerCount: 4,
        isPinned: true,
        createdData: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentDocumentProvider(testDocCid).overrideWith((ref) async => testStream),
            documentVersionsProvider(testDocCid).overrideWith((ref) async => [testVersion]),
            activeVersionCidProvider(testDocCid).overrideWith((ref) => testDocCid),
          ],
          child: const MaterialApp(
            home: ContentViewerScreen(documentCid: testDocCid),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 200));

      // 1. Verify KaTeX Math widgets are rendered
      expect(find.byType(Math), findsWidgets,
          reason: 'KaTeX Math widgets must render display and inline formulas');

      // 2. Verify display formula KaTeX cards exist with badges and copy button
      expect(find.text('FORMULA • KaTeX'), findsNWidgets(2));
      expect(find.text('Copy LaTeX'), findsNWidgets(2));

      // 3. Verify Image figure is parsed and rendered with caption
      expect(find.text('Figure: Double Helix X-ray Diffraction Photo 51'), findsOneWidget);

      // 4. Test tapping on image opens lightbox inspection dialog
      final figureCaptionFinder = find.text('Figure: Double Helix X-ray Diffraction Photo 51');
      expect(figureCaptionFinder, findsOneWidget);

      await tester.ensureVisible(figureCaptionFinder);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(figureCaptionFinder);
      await tester.pump(const Duration(milliseconds: 200));

      // Verify lightbox opened
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('Pinch or scroll to zoom • Click and drag to pan • Air-gapped peer preservation'), findsOneWidget);

      // Close lightbox
      final closeButton = find.byIcon(Icons.close);
      expect(closeButton, findsOneWidget);
      await tester.tap(closeButton);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(InteractiveViewer), findsNothing);
    });
  });
}
