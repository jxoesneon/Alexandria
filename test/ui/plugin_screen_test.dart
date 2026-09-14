import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/plugin_service.dart';
import 'package:alexandria/ui/plugin_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PluginScreen Tests', () {
    testWidgets('renders plugins and themes tabs, and opens install dialog', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = PluginService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pluginServiceProvider.overrideWithValue(service),
          ],
          child: const MaterialApp(
            home: PluginScreen(),
          ),
        ),
      );

      expect(find.text('THE GARDEN'), findsOneWidget);
      expect(find.text('Plugins & Themes'), findsOneWidget);
      expect(find.text('PLUGINS'), findsWidgets);
      expect(find.text('THEMES'), findsWidgets);

      // Switch to themes tab
      await tester.tap(find.text('THEMES').first);
      await tester.pumpAndSettle();

      // Open install dialog
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();

      expect(find.text('Install Theme'), findsOneWidget);
      expect(find.text('Paste the manifest JSON:'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('plugin toggle switch and quick template insertion', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = PluginService();
      // Install a sample plugin
      service.installPlugin(service.zoteroConnectorTemplate);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pluginServiceProvider.overrideWithValue(service),
          ],
          child: const MaterialApp(
            home: PluginScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Zotero Connector'), findsOneWidget);

      // Toggle switch (first switch is DoiHarvester, second is Zotero)
      final switchFinders = find.byType(Switch);
      expect(switchFinders, findsNWidgets(2));
      await tester.tap(switchFinders.last);
      await tester.pumpAndSettle();

      // Open install plugin dialog and tap template chip
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();

      expect(find.text('Calibre'), findsOneWidget);
      await tester.tap(find.text('Calibre'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Install'));
      await tester.pumpAndSettle();

      expect(service.plugins.any((p) => p.manifest.name == 'Calibre Connector'), isTrue);
    });

    testWidgets('theme selection and template install in themes tab', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = PluginService();
      service.installTheme(jsonEncode({
        'id': 'solarized-dark',
        'name': 'Solarized Dark',
        'version': '1.0.0',
        'author': 'Alexandria',
        'colors': {'background': '#002B36', 'primary': '#268BD2'},
      }));
      service.setActiveTheme('solarized-dark');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pluginServiceProvider.overrideWithValue(service),
          ],
          child: const MaterialApp(
            home: PluginScreen(),
          ),
        ),
      );

      // Navigate to themes
      await tester.tap(find.text('THEMES').first);
      await tester.pumpAndSettle();

      expect(find.text('Solarized Dark'), findsOneWidget);
      expect(find.text('ACTIVE'), findsOneWidget);

      // Tap on the theme card
      await tester.tap(find.text('Solarized Dark'));
      await tester.pumpAndSettle();

      expect(service.activeTheme?.name, 'Solarized Dark');
    });
  });
}
