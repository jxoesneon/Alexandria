import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/secure_storage_service.dart';
import '../services/ipfs_service.dart';

class AppSettings {
  final bool ipfsSwarmMode;
  final bool biometricEnabled;
  final String gatewayUrl;
  final List<String> availableGateways;
  final ThemeMode themeMode;
  final bool reducedMotion;

  const AppSettings({
    this.ipfsSwarmMode = true,
    this.biometricEnabled = false,
    this.gatewayUrl = 'https://ipfs.io/ipfs',
    this.availableGateways = const [
      'https://ipfs.io/ipfs',
      'https://dweb.link/ipfs',
      'https://cloudflare-ipfs.com/ipfs',
    ],
    this.themeMode = ThemeMode.system,
    this.reducedMotion = false,
  });

  AppSettings copyWith({
    bool? ipfsSwarmMode,
    bool? biometricEnabled,
    String? gatewayUrl,
    List<String>? availableGateways,
    ThemeMode? themeMode,
    bool? reducedMotion,
  }) {
    return AppSettings(
      ipfsSwarmMode: ipfsSwarmMode ?? this.ipfsSwarmMode,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      gatewayUrl: gatewayUrl ?? this.gatewayUrl,
      availableGateways: availableGateways ?? this.availableGateways,
      themeMode: themeMode ?? this.themeMode,
      reducedMotion: reducedMotion ?? this.reducedMotion,
    );
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  final storage = ref.read(secureStorageServiceProvider);
  final ipfs = ref.read(ipfsServiceProvider);
  return SettingsNotifier(storage, ipfs);
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  final SecureStorageService _storage;
  final IpfsService _ipfs;

  SettingsNotifier(this._storage, this._ipfs) : super(const AppSettings()) {
    loadSettings();
  }

  Future<void> loadSettings() async {
    final theme = await _storage.read('setting_theme');
    final motion = await _storage.read('setting_reduced_motion');
    ThemeMode mode = ThemeMode.system;
    if (theme == 'light') mode = ThemeMode.light;
    if (theme == 'dark') mode = ThemeMode.dark;

    state = state.copyWith(
      themeMode: mode,
      reducedMotion: motion == 'true',
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _storage.write('setting_theme', mode.name);
  }

  Future<void> setReducedMotion(bool value) async {
    state = state.copyWith(reducedMotion: value);
    await _storage.write('setting_reduced_motion', value.toString());
  }

  Future<void> pruneIpfsRepo() async {
    await _ipfs.runGc();
  }
}
