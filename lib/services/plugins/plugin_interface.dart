import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../plugin_service.dart';

/// Definition of an executable action exposed by a plugin.
class PluginActionDefinition {
  final String id;
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  const PluginActionDefinition({
    required this.id,
    required this.name,
    required this.description,
    this.parameters = const {},
  });
}

/// Result returned from executing a plugin action.
class PluginActionResult {
  final bool success;
  final String message;
  final dynamic data;

  const PluginActionResult({
    required this.success,
    required this.message,
    this.data,
  });

  factory PluginActionResult.ok(String message, [dynamic data]) =>
      PluginActionResult(success: true, message: message, data: data);

  factory PluginActionResult.error(String message, [dynamic data]) =>
      PluginActionResult(success: false, message: message, data: data);
}

/// Runtime execution context provided to plugins.
class PluginContext {
  final Ref? ref;
  final ProviderContainer? container;
  final String pluginId;
  final Map<String, dynamic> storage;

  PluginContext({
    this.ref,
    this.container,
    required this.pluginId,
    Map<String, dynamic>? storage,
  }) : storage = storage ?? <String, dynamic>{};

  bool get hasReader => ref != null || container != null;

  T read<T>(ProviderListenable<T> provider) {
    if (ref != null) return ref!.read(provider);
    if (container != null) return container!.read(provider);
    throw StateError('PluginContext does not have an active Ref or ProviderContainer.');
  }
}

/// Abstract contract for executable Alexandria plugins.
abstract class AlexandriaPlugin {
  PluginManifest get manifest;

  bool get isEnabled;
  set isEnabled(bool value);

  Future<void> initialize(PluginContext context);

  List<PluginActionDefinition> get actions;

  Future<PluginActionResult> executeAction(
    String actionId,
    Map<String, dynamic> parameters,
  );

  Future<void> onHook(PluginHook hook, dynamic payload) async {}
}
