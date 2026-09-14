import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final secureStorageServiceProvider = Provider((ref) => SecureStorageService());

/// Storage key names shared across services that all live in the SAME
/// [SecureStorageService] keychain. Never write these keys through a
/// second `FlutterSecureStorage` instance — platform options differ
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

  Future<String?> read(String key) async => await _storage.read(key: key);
  Future<void> write(String key, String value) async =>
      await _storage.write(key: key, value: value);
  Future<void> delete(String key) async => await _storage.delete(key: key);
  Future<void> deleteAll() async => await _storage.deleteAll();
  Future<bool> containsKey(String key) async =>
      await _storage.containsKey(key: key);
}
