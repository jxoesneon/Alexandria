import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app_network.dart';

final secureStorageServiceProvider = Provider((ref) => SecureStorageService());

/// Storage key names shared across services that all live in the SAME
/// [SecureStorageService] keychain. Never write these keys through a
/// second `FlutterSecureStorage` instance - platform options differ
/// (e.g. macOS data-protection keychain), which splits the store.
class SecureStorageKeys {
  SecureStorageKeys._();

  /// Marker recording that the current identity's recovery phrase has
  /// been backed up. Written by `IdentityService.markMnemonicBackupConfirmed`
  /// (via `MnemonicService.markBackupConfirmed`, which delegates so the
  /// write is serialized with identity mutations), read by
  /// `SecurityOverviewService`, and cleared by `IdentityService`
  /// whenever the stored keypair is replaced.
  static const String mnemonicBackup = 'alexandria_mnemonic_backup';
}

class SecureStorageService {
  final _storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(
      usesDataProtectionKeychain: false,
    ),
  );

  /// Key namespace for the active network: testnet prefixes every key
  /// with [AppNetwork.testnetKeyPrefix] so keychain state (identity,
  /// settings, node seed) never collides with mainnet.
  final String keyPrefix;

  SecureStorageService({String? keyPrefix})
      : keyPrefix = keyPrefix ??
            (AppNetwork.testnet ? AppNetwork.testnetKeyPrefix : '');

  String _k(String key) => '$keyPrefix$key';

  Future<String?> read(String key) async => await _storage.read(key: _k(key));
  Future<void> write(String key, String value) async =>
      await _storage.write(key: _k(key), value: value);
  Future<void> delete(String key) async => await _storage.delete(key: _k(key));
  Future<void> deleteAll() async {
    if (keyPrefix.isEmpty) return _storage.deleteAll();
    // Scoped wipe: remove only this network's keys - a testnet wipe
    // must not touch mainnet keychain state.
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(keyPrefix)) await _storage.delete(key: key);
    }
  }

  Future<bool> containsKey(String key) async =>
      await _storage.containsKey(key: _k(key));
}
