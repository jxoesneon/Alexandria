import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/plugin_service.dart';

void main() {
  group('PluginService & Extensibility System Tests', () {
    late PluginService service;

    setUp(() {
      service = PluginService();
    });

    test('automatically registers the flagship DOI Harvester plugin on startup',
        () {
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
      expect(
          service.plugins.firstWhere((p) => p.id == pluginId).enabled, isFalse);
      expect(service.getExecutablePlugin(pluginId)!.isEnabled, isFalse);

      service.togglePlugin(pluginId, true);
      expect(
          service.plugins.firstWhere((p) => p.id == pluginId).enabled, isTrue);
      expect(service.getExecutablePlugin(pluginId)!.isEnabled, isTrue);
    });

    test('installs valid third-party plugins from JSON manifest', () {
      final manifestJson = service.zoteroConnectorTemplate;
      final installed = service.installPlugin(manifestJson);

      expect(installed, isNotNull);
      expect(installed!.id, 'com.alexandria.zotero-connector');
      expect(
          service.plugins.any((p) => p.id == 'com.alexandria.zotero-connector'),
          isTrue);
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
      expect(
          service.plugins
              .any((p) => p.id == 'com.alexandria.calibre-connector'),
          isTrue);

      final uninstalled =
          service.uninstallPlugin('com.alexandria.calibre-connector');
      expect(uninstalled, isTrue);
      expect(
          service.plugins
              .any((p) => p.id == 'com.alexandria.calibre-connector'),
          isFalse);
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
        {
          'text':
              'Found in literature: 10.1038/s41586-020-2649-2 and doi:10.1145/3377811.3380327'
        },
      );

      expect(result.success, isTrue);
      expect(result.data['count'], 2);
      expect(result.data['dois'], contains('10.1038/s41586-020-2649-2'));
      expect(result.data['dois'], contains('10.1145/3377811.3380327'));
    });

    test('PluginManifest and ThemeManifest serialization round-trips correctly',
        () {
      const manifest = PluginManifest(
        id: 'test.manifest',
        name: 'Test Plugin',
        version: '1.2.3',
        author: 'Test Author',
        description: 'Test Description',
        entrypoint: 'index.js',
        permissions: [
          PluginPermission.networkFetch,
          PluginPermission.storagePersist
        ],
        hooks: [PluginHook.onStartup, PluginHook.onContentViewed],
        uiSlots: [UISlot.homeHeader, UISlot.detailActions],
        maxMemoryMb: 128,
        timeoutMs: 8000,
      );

      final json = manifest.toJson();
      final parsed = PluginManifest.fromJson(json);

      expect(parsed.id, 'test.manifest');
      expect(parsed.name, 'Test Plugin');
      expect(parsed.version, '1.2.3');
      expect(parsed.author, 'Test Author');
      expect(parsed.description, 'Test Description');
      expect(parsed.entrypoint, 'index.js');
      expect(parsed.permissions,
          [PluginPermission.networkFetch, PluginPermission.storagePersist]);
      expect(parsed.hooks, [PluginHook.onStartup, PluginHook.onContentViewed]);
      expect(parsed.uiSlots, [UISlot.homeHeader, UISlot.detailActions]);
      expect(parsed.maxMemoryMb, 128);
      expect(parsed.timeoutMs, 8000);

      final theme = ThemeManifest(
        id: 'test.theme',
        name: 'Test Theme',
        version: '2.0.0',
        author: 'Theme Author',
        colors: {'accent': '#FF5500'},
        sizing: {'padding': 16.0},
        fontFamily: 'Inter',
      );

      final themeJson = theme.toJson();
      final parsedTheme = ThemeManifest.fromJson(themeJson);

      expect(parsedTheme.id, 'test.theme');
      expect(parsedTheme.name, 'Test Theme');
      expect(parsedTheme.version, '2.0.0');
      expect(parsedTheme.author, 'Theme Author');
      expect(parsedTheme.colors['accent'], '#FF5500');
      expect(parsedTheme.sizing['padding'], 16.0);
      expect(parsedTheme.fontFamily, 'Inter');
    });

    test('re-registering an executable plugin updates its enabled status', () {
      final doiPlugin = DoiHarvesterPlugin();
      doiPlugin.isEnabled = false;
      service.registerPlugin(doiPlugin);

      expect(
          service.plugins
              .firstWhere((p) => p.id == doiPlugin.manifest.id)
              .enabled,
          isFalse);
      expect(
          service.executablePlugins
              .any((p) => p.manifest.id == doiPlugin.manifest.id),
          isTrue);
    });

    test('getPluginsWithHook and getPluginsForSlot filter correctly', () {
      service.installPlugin(service.zoteroConnectorTemplate);

      final startupPlugins = service.getPluginsWithHook(PluginHook.onStartup);
      expect(
          startupPlugins.any((p) => p.id == 'com.alexandria.zotero-connector'),
          isTrue);

      final settingsSlotPlugins =
          service.getPluginsForSlot(UISlot.settingsSection);
      expect(
          settingsSlotPlugins
              .any((p) => p.id == 'com.alexandria.zotero-connector'),
          isTrue);

      final homeSlotPlugins = service.getPluginsForSlot(UISlot.homeHeader);
      expect(
          homeSlotPlugins.any((p) => p.id == 'com.alexandria.zotero-connector'),
          isFalse);
    });

    test(
        'handles errors when executing non-existent or disabled plugins or when action throws',
        () async {
      final notFoundResult =
          await service.executeAction('non_existent_plugin', 'any_action');
      expect(notFoundResult.success, isFalse);
      expect(notFoundResult.message, contains('Plugin not found'));

      service.togglePlugin('org.alexandria.plugin.doi-harvester', false);
      final disabledResult = await service.executeAction(
          'org.alexandria.plugin.doi-harvester', 'extract_dois');
      expect(disabledResult.success, isFalse);
      expect(disabledResult.message, contains('is disabled'));

      service.togglePlugin('org.alexandria.plugin.doi-harvester', true);
      final unknownActionResult = await service.executeAction(
          'org.alexandria.plugin.doi-harvester', 'invalid_action');
      expect(unknownActionResult.success, isFalse);
    });

    test('togglePlugin and uninstallPlugin return false for unknown plugin',
        () {
      expect(service.togglePlugin('unknown_plugin', true), isFalse);
      expect(service.uninstallPlugin('unknown_plugin'), isFalse);
      expect(service.setActiveTheme('unknown_theme'), isFalse);
    });

    test('installPlugin and installTheme handle invalid JSON gracefully', () {
      expect(service.installPlugin('not valid json {'), isNull);
      expect(service.installTheme('not valid json {'), isNull);
    });
  });
}
