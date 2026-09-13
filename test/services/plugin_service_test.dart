import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/plugin_service.dart';

void main() {
  group('PluginService & Extensibility System Tests', () {
    late PluginService service;

    setUp(() {
      service = PluginService();
    });

    test('automatically registers the flagship DOI Harvester plugin on startup', () {
      expect(service.plugins.isNotEmpty, isTrue);
      final doiPlugin = service.plugins.firstWhere(
        (p) => p.id == 'org.alexandria.plugin.doi-harvester',
      );
      expect(doiPlugin.manifest.name, 'DOI Scientific Harvester');
      expect(doiPlugin.enabled, isTrue);

      final executable =
          service.getExecutablePlugin('org.alexandria.plugin.doi-harvester');
      expect(executable, isNotNull);
      expect(executable, isA<DoiHarvesterPlugin>());
    });

    test('enables and disables plugins dynamically', () {
      const pluginId = 'org.alexandria.plugin.doi-harvester';
      expect(service.getExecutablePlugin(pluginId)!.isEnabled, isTrue);

      service.togglePlugin(pluginId, false);
      expect(service.plugins.firstWhere((p) => p.id == pluginId).enabled, isFalse);
      expect(service.getExecutablePlugin(pluginId)!.isEnabled, isFalse);

      service.togglePlugin(pluginId, true);
      expect(service.plugins.firstWhere((p) => p.id == pluginId).enabled, isTrue);
      expect(service.getExecutablePlugin(pluginId)!.isEnabled, isTrue);
    });

    test('installs valid third-party plugins from JSON manifest', () {
      final manifestJson = service.zoteroConnectorTemplate;
      final installed = service.installPlugin(manifestJson);

      expect(installed, isNotNull);
      expect(installed!.id, 'com.alexandria.zotero-connector');
      expect(service.plugins.any((p) => p.id == 'com.alexandria.zotero-connector'), isTrue);
    });

    test('rejects duplicate plugin installations', () {
      final manifestJson = service.calibreConnectorTemplate;
      final first = service.installPlugin(manifestJson);
      expect(first, isNotNull);

      final duplicate = service.installPlugin(manifestJson);
      expect(duplicate, isNull);
    });

    test('uninstalls plugins cleanly', () {
      final manifestJson = service.calibreConnectorTemplate;
      service.installPlugin(manifestJson);
      expect(service.plugins.any((p) => p.id == 'com.alexandria.calibre-connector'), isTrue);

      final uninstalled = service.uninstallPlugin('com.alexandria.calibre-connector');
      expect(uninstalled, isTrue);
      expect(service.plugins.any((p) => p.id == 'com.alexandria.calibre-connector'), isFalse);
    });

    test('dispatches hooks to enabled plugins without throwing', () async {
      await expectLater(
        service.dispatchHook(PluginHook.onStartup, {'node': 'test_node'}),
        completes,
      );
    });

    test('installs and switches themes', () {
      final themeJson = '''
      {
        "id": "theme.archive-amber",
        "name": "Archive Amber",
        "version": "1.0.0",
        "author": "Alexandria Team",
        "colors": {
          "primary": "#D4A373",
          "background": "#141518",
          "surface": "#1F2125"
        }
      }
      ''';

      final theme = service.installTheme(themeJson);
      expect(theme, isNotNull);
      expect(theme!.name, 'Archive Amber');

      final activated = service.setActiveTheme('theme.archive-amber');
      expect(activated, isTrue);
      expect(service.activeTheme?.id, 'theme.archive-amber');
    });

    test('executes registered actions on plugins', () async {
      final result = await service.executeAction(
        'org.alexandria.plugin.doi-harvester',
        'extract_dois',
        {'text': 'Found in literature: 10.1038/s41586-020-2649-2 and doi:10.1145/3377811.3380327'},
      );

      expect(result.success, isTrue);
      expect(result.data['count'], 2);
      expect(result.data['dois'], contains('10.1038/s41586-020-2649-2'));
      expect(result.data['dois'], contains('10.1145/3377811.3380327'));
    });
  });
}
