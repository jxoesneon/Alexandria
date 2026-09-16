import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'plugins/doi_harvester_plugin.dart';
import 'plugins/plugin_interface.dart';

export 'plugins/doi_harvester_plugin.dart';
export 'plugins/plugin_interface.dart';

/// Provider for the PluginService
final pluginServiceProvider = Provider((ref) => PluginService(ref));

/// Plugin permissions (Spec §19.2)
enum PluginPermission {
  networkFetch, // Can make HTTP requests
  storagePersist, // Can store persistent data
  uiInject, // Can inject UI components
  contentRead, // Can read content manifests
  contentWrite, // Can create/modify content
  settingsRead, // Can read app settings
  settingsWrite, // Can modify app settings
}

/// Plugin hook types (Spec §19.3)
enum PluginHook {
  onStartup, // Called when app starts
  onContentAdded, // Called when content is added
  onContentViewed, // Called when content is viewed
  onSearch, // Called during search
  onPreserve, // Called before preservation
  onSettingsChanged, // Called when settings change
}

/// UI slot for plugin injection (Spec §19.4)
enum UISlot {
  homeHeader, // Top of home screen
  homeFooter, // Bottom of home screen
  detailSidebar, // Sidebar on detail screen
  detailActions, // Action buttons on detail
  searchFilters, // Additional search filters
  settingsSection, // Section in settings
  profileBadges, // Badge area in profile
}

/// Plugin manifest schema (Spec §19.1)
class PluginManifest {
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final String? homepage;
  final String? repository;
  final String entrypoint;
  final List<PluginPermission> permissions;
  final List<PluginHook> hooks;
  final List<UISlot> uiSlots;
  final int maxMemoryMb;
  final int timeoutMs;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.author,
    required this.description,
    this.homepage,
    this.repository,
    required this.entrypoint,
    required this.permissions,
    this.hooks = const [],
    this.uiSlots = const [],
    this.maxMemoryMb = 64,
    this.timeoutMs = 5000,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'author': author,
        'description': description,
        'homepage': homepage,
        'repository': repository,
        'entrypoint': entrypoint,
        'permissions': permissions.map((p) => p.name).toList(),
        'hooks': hooks.map((h) => h.name).toList(),
        'uiSlots': uiSlots.map((s) => s.name).toList(),
        'maxMemoryMb': maxMemoryMb,
        'timeoutMs': timeoutMs,
      };

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    return PluginManifest(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      author: json['author'] as String,
      description: json['description'] as String,
      homepage: json['homepage'] as String?,
      repository: json['repository'] as String?,
      entrypoint: json['entrypoint'] as String,
      permissions: (json['permissions'] as List?)
              ?.map(
                (p) => PluginPermission.values.firstWhere((e) => e.name == p),
              )
              .toList() ??
          [],
      hooks: (json['hooks'] as List?)
              ?.map((h) => PluginHook.values.firstWhere((e) => e.name == h))
              .toList() ??
          [],
      uiSlots: (json['uiSlots'] as List?)
              ?.map((s) => UISlot.values.firstWhere((e) => e.name == s))
              .toList() ??
          [],
      maxMemoryMb: json['maxMemoryMb'] as int? ?? 64,
      timeoutMs: json['timeoutMs'] as int? ?? 5000,
    );
  }
}

/// Installed plugin instance
class InstalledPlugin {
  final PluginManifest manifest;
  final DateTime installedAt;
  bool enabled;
  final Map<String, dynamic> settings;

  InstalledPlugin({
    required this.manifest,
    required this.installedAt,
    this.enabled = true,
    this.settings = const {},
  });

  String get id => manifest.id;
  String get name => manifest.name;
}

/// Theme manifest (Spec §19.10)
class ThemeManifest {
  final String id;
  final String name;
  final String version;
  final String author;
  final Map<String, String> colors;
  final Map<String, double> sizing;
  final String? fontFamily;

  ThemeManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.author,
    required this.colors,
    this.sizing = const {},
    this.fontFamily,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'author': author,
        'colors': colors,
        'sizing': sizing,
        'fontFamily': fontFamily,
      };

  factory ThemeManifest.fromJson(Map<String, dynamic> json) {
    return ThemeManifest(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      author: json['author'] as String,
      colors: Map<String, String>.from(json['colors'] as Map),
      sizing: Map<String, double>.from(json['sizing'] as Map? ?? {}),
      fontFamily: json['fontFamily'] as String?,
    );
  }
}

/// Plugin service for The Garden.
///
/// Orchestrates Alexandria's extensible plugin system, managing built-in
/// executable plugins (such as [DoiHarvesterPlugin]), dynamic manifest installations,
/// theme switching, and lifecycle hook dispatching.
class PluginService {
  final Ref? _ref;
  final List<InstalledPlugin> _plugins = [];
  final Map<String, AlexandriaPlugin> _executablePlugins = {};
  final List<ThemeManifest> _themes = [];
  String? _activeThemeId;

  PluginService([this._ref]) {
    _initBuiltinPlugins();
  }

  void _initBuiltinPlugins() {
    // Register the Flagship First Plugin: DOI Scientific Harvester
    final doiPlugin = DoiHarvesterPlugin();
    registerPlugin(doiPlugin);
  }

  /// Get all installed plugins
  List<InstalledPlugin> get plugins => List.unmodifiable(_plugins);

  /// Get enabled plugins
  List<InstalledPlugin> get enabledPlugins =>
      _plugins.where((p) => p.enabled).toList();

  /// Get executable plugins
  List<AlexandriaPlugin> get executablePlugins =>
      _executablePlugins.values.toList();

  /// Retrieve an executable plugin by its ID
  AlexandriaPlugin? getExecutablePlugin(String id) => _executablePlugins[id];

  /// Get available themes
  List<ThemeManifest> get themes => List.unmodifiable(_themes);

  /// Get active theme
  ThemeManifest? get activeTheme =>
      _themes.where((t) => t.id == _activeThemeId).firstOrNull;

  /// Register an executable plugin
  void registerPlugin(AlexandriaPlugin plugin) {
    // (round-3 red finding) refuse to even initialize a plugin whose
    // declared permission set is malformed — the manifest is the trust
    // contract the context enforces.
    if (!_validatePermissions(plugin.manifest.permissions)) {
      debugPrint(
          'Refusing to register ${plugin.manifest.id}: invalid permissions');
      return;
    }
    _executablePlugins[plugin.manifest.id] = plugin;

    // Initialize with a permission-SCOPED context — the raw Ref is
    // private inside PluginContext and read() resolves only allowlisted
    // capabilities matching the manifest's declared permissions.
    final context = PluginContext(
      ref: _ref,
      pluginId: plugin.manifest.id,
      permissions: plugin.manifest.permissions.toSet(),
    );
    plugin.initialize(context);

    // Sync into installed plugins list
    final existingIndex =
        _plugins.indexWhere((p) => p.id == plugin.manifest.id);
    if (existingIndex >= 0) {
      _plugins[existingIndex].enabled = plugin.isEnabled;
    } else {
      _plugins.add(InstalledPlugin(
        manifest: plugin.manifest,
        installedAt: DateTime.now(),
        enabled: plugin.isEnabled,
      ));
    }
  }

  /// Execute an action on a registered plugin
  Future<PluginActionResult> executeAction(
    String pluginId,
    String actionId, [
    Map<String, dynamic> parameters = const {},
  ]) async {
    final plugin = _executablePlugins[pluginId];
    if (plugin == null) {
      return PluginActionResult.error('Plugin not found: $pluginId');
    }
    if (!plugin.isEnabled) {
      return PluginActionResult.error('Plugin $pluginId is disabled.');
    }

    try {
      return await plugin.executeAction(actionId, parameters);
    } catch (e, stack) {
      debugPrint('Plugin execution error [$pluginId:$actionId]: $e\n$stack');
      return PluginActionResult.error('Execution exception: $e');
    }
  }

  /// Dispatch a lifecycle hook to all active, capable plugins
  Future<void> dispatchHook(PluginHook hook, [dynamic payload]) async {
    for (final plugin in _executablePlugins.values) {
      if (plugin.isEnabled && plugin.manifest.hooks.contains(hook)) {
        try {
          await plugin.onHook(hook, payload);
        } catch (e) {
          debugPrint('Hook error in ${plugin.manifest.id} on $hook: $e');
        }
      }
    }
  }

  /// Install a plugin from manifest JSON
  InstalledPlugin? installPlugin(String manifestJson) {
    try {
      final json = jsonDecode(manifestJson) as Map<String, dynamic>;
      final manifest = PluginManifest.fromJson(json);

      // Check for duplicate
      if (_plugins.any((p) => p.id == manifest.id)) {
        return null;
      }

      // Validate permissions
      if (!_validatePermissions(manifest.permissions)) {
        return null;
      }

      final plugin = InstalledPlugin(
        manifest: manifest,
        installedAt: DateTime.now(),
      );

      _plugins.add(plugin);
      return plugin;
    } catch (e) {
      return null;
    }
  }

  /// Uninstall a plugin
  bool uninstallPlugin(String pluginId) {
    final index = _plugins.indexWhere((p) => p.id == pluginId);
    if (index == -1) return false;

    _plugins.removeAt(index);
    _executablePlugins.remove(pluginId);
    return true;
  }

  /// Enable/disable a plugin
  bool togglePlugin(String pluginId, bool enabled) {
    final plugin = _plugins.where((p) => p.id == pluginId).firstOrNull;
    if (plugin == null) return false;

    plugin.enabled = enabled;
    if (_executablePlugins.containsKey(pluginId)) {
      _executablePlugins[pluginId]!.isEnabled = enabled;
    }
    return true;
  }

  /// Get plugins with a specific hook
  List<InstalledPlugin> getPluginsWithHook(PluginHook hook) {
    return enabledPlugins
        .where((p) => p.manifest.hooks.contains(hook))
        .toList();
  }

  /// Get plugins for a UI slot
  List<InstalledPlugin> getPluginsForSlot(UISlot slot) {
    return enabledPlugins
        .where((p) => p.manifest.uiSlots.contains(slot))
        .toList();
  }

  /// Install a theme
  ThemeManifest? installTheme(String manifestJson) {
    try {
      final json = jsonDecode(manifestJson) as Map<String, dynamic>;
      final theme = ThemeManifest.fromJson(json);

      // Check for duplicate
      if (_themes.any((t) => t.id == theme.id)) {
        return null;
      }

      _themes.add(theme);
      return theme;
    } catch (e) {
      return null;
    }
  }

  /// Set active theme
  bool setActiveTheme(String themeId) {
    if (!_themes.any((t) => t.id == themeId)) return false;
    _activeThemeId = themeId;
    return true;
  }

  /// Validate that permissions are allowed (round-3 red finding — was a
  /// `return true` stub). Only known enum values are accepted and
  /// duplicates are rejected. Enforcement happens at
  /// [PluginContext.read] — this check guarantees the manifest declares
  /// a well-formed contract.
  bool _validatePermissions(List<PluginPermission> permissions) {
    return permissions.every(PluginPermission.values.contains) &&
        permissions.toSet().length == permissions.length;
  }

  /// Create Zotero connector plugin template
  String get zoteroConnectorTemplate => jsonEncode({
        'id': 'com.alexandria.zotero-connector',
        'name': 'Zotero Connector',
        'version': '1.0.0',
        'author': 'Alexandria',
        'description': 'Import and sync with Zotero library',
        'entrypoint': 'zotero_connector.wasm',
        'permissions': ['networkFetch', 'contentWrite', 'storagePersist'],
        'hooks': ['onStartup', 'onContentAdded'],
        'uiSlots': ['settingsSection'],
      });

  /// Create Calibre connector plugin template
  String get calibreConnectorTemplate => jsonEncode({
        'id': 'com.alexandria.calibre-connector',
        'name': 'Calibre Connector',
        'version': '1.0.0',
        'author': 'Alexandria',
        'description': 'Import books from Calibre library',
        'entrypoint': 'calibre_connector.wasm',
        'permissions': ['contentRead', 'contentWrite', 'storagePersist'],
        'hooks': ['onStartup'],
        'uiSlots': ['settingsSection'],
      });
}
