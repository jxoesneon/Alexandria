// RED TEAM PoC — Round-4: the round-3 plugin facade restricts
// PluginContext.read to an allowlist containing only
// contentRepositoryProvider — but the provider VALUE is the whole
// ContentRepository, whose public surface reaches sensitive resources
// transitively:
//
//   lib/logic/content_repository.dart:112
//     Future<String?> contentDekBase64(String manifestUuid) =>
//         _storage.read('dek_$manifestUuid');
//
// A plugin declaring ONLY `contentRead` ("Can read content manifests")
// receives the real ContentRepository and calls contentDekBase64 —
// pulling arbitrary content DEKs out of the keychain store that the
// facade claims is NEVER on the allowlist ("Secure storage ... are NEVER
// on this list"). The facade gates the provider NAME, not the
// capability surface: secureStorageServiceProvider is blocked, yet the
// same key material flows through the allowlisted object.
//
// Asserts the SECURE expectation: a contentRead-scoped plugin must not
// obtain content key material — the allowlisted capability needs a
// narrowed view (facade object exposing manifest reads only), not the
// full repository.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/logic/content_repository.dart';
import 'package:alexandria/services/plugin_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

class _FakeSecureStorage extends SecureStorageService {
  final Map<String, String> map = {
    'dek_victim-doc': 'U0VDUkVULURFSw==', // the round-2 crown jewel
  };
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
  @override
  Future<void> delete(String key) async => map.remove(key);
  @override
  Future<bool> containsKey(String key) async => map.containsKey(key);
}

void main() {
  test(
      'a contentRead-only plugin must not reach content DEKs through '
      'the allowlisted repository', () async {
    final container = ProviderContainer(overrides: [
      secureStorageServiceProvider.overrideWithValue(_FakeSecureStorage()),
    ]);
    addTearDown(container.dispose);

    // Exactly what registerPlugin issues — declared permission:
    // contentRead only.
    final ctx = PluginContext(
      container: container,
      pluginId: 'com.evil.read-only',
      permissions: {PluginPermission.contentRead},
    );

    final repo = ctx.read(contentRepositoryProvider);
    expect(repo, isA<ContentRepository>());

    // The transitively-reachable secure-storage read.
    final dek =
        await (repo as ContentRepository).contentDekBase64('victim-doc');

    expect(dek, isNull,
        reason: 'a plugin declaring ONLY contentRead recovered a content DEK '
            '("$dek") from secure storage via ContentRepository.'
            'contentDekBase64 — the facade blocks the storage PROVIDER '
            'but hands the plugin an object that reads it anyway. '
            '"contentRead" was declared for manifest reads, not key '
            'material exfiltration.');
  });

  test(
      'non-allowlisted providers still resolve to an inert capability '
      '(verification — round-3 fix holds)', () async {
    final container = ProviderContainer(overrides: [
      secureStorageServiceProvider.overrideWithValue(_FakeSecureStorage()),
    ]);
    addTearDown(container.dispose);
    final ctx = PluginContext(
      container: container,
      pluginId: 'com.evil.reader',
      permissions: {PluginPermission.contentRead},
    );

    final denied = ctx.read(secureStorageServiceProvider);
    expect(denied, isNot(isA<SecureStorageService>()));
    // noSuchMethod reads as absent — no key material leaks.
    expect(await denied.read('dek_victim-doc'), isNull);
  });
}
