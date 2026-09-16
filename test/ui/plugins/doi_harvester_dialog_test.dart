import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/plugin_service.dart';
import 'package:alexandria/ui/plugins/doi_harvester_dialog.dart';

class _FakeDoiHarvesterPluginService extends PluginService {
  @override
  Future<PluginActionResult> executeAction(
    String pluginId,
    String action, [
    Map<String, dynamic> params = const {},
  ]) async {
    return const PluginActionResult(
      success: true,
      message: 'Harvest completed successfully',
      data: {
        'results': [
          {
            'success': true,
            'doi': '10.1038/s41586-020-2649-2',
            'title': 'An ultra-rare genetic variation in humans',
            'author': 'Karczewski et al.',
            'format': 'pdf',
            'capturedPdf': true,
          }
        ]
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DoiHarvesterDialog Tests', () {
    testWidgets(
        'renders DOI harvester dialog, loads sample, and executes harvest',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeService = _FakeDoiHarvesterPluginService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pluginServiceProvider.overrideWithValue(fakeService),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: DoiHarvesterDialog(initialDoi: '10.1038/s41586-020-2649-2'),
            ),
          ),
        ),
      );

      expect(find.text('DOI SCIENTIFIC HARVESTER'), findsOneWidget);
      expect(find.text('10.1038/s41586-020-2649-2'), findsOneWidget);

      // Load sample DOIs
      final sampleButton = find.text('Sample DOIs');
      expect(sampleButton, findsOneWidget);
      await tester.tap(sampleButton);
      await tester.pumpAndSettle();

      // Toggle switch
      final pdfSwitch = find.byType(Switch);
      expect(pdfSwitch, findsOneWidget);
      await tester.tap(pdfSwitch);
      await tester.pumpAndSettle();

      // Tap harvest button
      final harvestBtn = find.widgetWithText(FilledButton, 'Harvest 3 Works');
      expect(harvestBtn, findsOneWidget);
      await tester.tap(harvestBtn);
      await tester.pumpAndSettle();

      expect(find.text('Harvested Scientific Documents:'), findsOneWidget);
      expect(find.text('An ultra-rare genetic variation in humans'),
          findsOneWidget);
      expect(find.text('OPEN ACCESS PDF'), findsOneWidget);
    });
  });
}
