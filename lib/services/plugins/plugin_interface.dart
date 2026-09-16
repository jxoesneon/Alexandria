import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/content_repository.dart';
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

/// Inert object handed back when a plugin reads a provider it is not
/// permitted to reach (round-3 red finding).
///
/// Every member access resolves to "absent" rather than throwing, so a
/// denied plugin learns nothing — not even the shape of the real
/// service: lookup-style calls (`read('dek_x')`, `getIdentity()`,
/// `fetch(name)`, …) answer `null`, while opaque operations over
/// caller-supplied blobs (`sign(bytes)`, `encrypt(bytes)`, `seal(k)`, …)
/// yield the inert capability itself so any further member access on
/// their result — `.length`, `.publicKey`, … — still reads as absent
/// ([length] covers the common case of dereferencing a byte result).
class _DeniedCapability {
  const _DeniedCapability();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isMethod &&
        invocation.positionalArguments.isNotEmpty &&
        invocation.positionalArguments.first is! String) {
      return this;
    }
    return null;
  }

  /// `(await denied.sign(bytes)).length` reads as absent too.
  int? get length => null;

  @override
  String toString() => 'PluginCapability(denied)';
}

/// Runtime execution context provided to plugins.
///
/// (round-3 red finding) The raw Riverpod `Ref`/`ProviderContainer` is
/// kept PRIVATE — previously `context.read(provider)` resolved ANY
/// provider in the application graph, so a manifest declaring
/// `permissions: []` could still reach `secureStorageServiceProvider`
/// (every content DEK), `identityServiceProvider` (a signing oracle for
/// forging ledger entries, votes and receipts), and the credit service.
/// Now [read] only resolves providers on the capability allowlist, and
/// only when the plugin's manifest declared the matching
/// [PluginPermission]; anything else returns an inert
/// [_DeniedCapability].
class PluginContext {
  final Ref? _ref;
  final ProviderContainer? _container;
  final String pluginId;
  final Map<String, dynamic> storage;

  /// The permission set this context was issued under (the plugin
  /// manifest's declared — and validated — permissions).
  final Set<PluginPermission> permissions;

  PluginContext({
    Ref? ref,
    ProviderContainer? container,
    required this.pluginId,
    Map<String, dynamic>? storage,
    Set<PluginPermission> permissions = const {},
  })  : _ref = ref,
        _container = container,
        storage = storage ?? <String, dynamic>{},
        permissions = Set.unmodifiable(permissions);

  bool get hasReader => _ref != null || _container != null;

  /// Capability allowlist: which providers a plugin may resolve, and
  /// which declared permission unlocks each. Deliberately small — only
  /// content-repository access is needed by the built-in DOI harvester.
  /// Secure storage, identity/signing, and credit services are NEVER on
  /// this list: no permission grants them (round-3 red finding).
  static final Map<ProviderListenable<dynamic>, Set<PluginPermission>>
      _capabilityAllowlist = {
    contentRepositoryProvider: {
      PluginPermission.contentRead,
      PluginPermission.contentWrite,
    },
  };

  /// Permission-gated provider resolution. Returns the provider's value
  /// when it is allowlisted AND the plugin holds a matching permission;
  /// otherwise an inert [_DeniedCapability] (never the real service).
  ///
  /// (round-4 red finding) an allowlisted provider is still narrowed to
  /// a capability VIEW, not the raw service: the content repository is
  /// returned as a [PluginContentRepository] — manifest/metadata reads
  /// only, no DEK/key-material/decrypt paths (they previously rode
  /// through the allowlisted object transitively), and mutations gated
  /// on the declared `contentWrite` permission.
  dynamic read(ProviderListenable<dynamic> provider) {
    final required = _capabilityAllowlist[provider];
    if (required == null || !permissions.any(required.contains)) {
      return const _DeniedCapability();
    }
    final ref = _ref;
    final container = _container;
    if (ref == null && container == null) return const _DeniedCapability();
    final value = ref != null ? ref.read(provider) : container!.read(provider);
    if (provider == contentRepositoryProvider && value is ContentRepository) {
      return value.asPluginCapability(
        canWrite: permissions.contains(PluginPermission.contentWrite),
      );
    }
    return value;
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
