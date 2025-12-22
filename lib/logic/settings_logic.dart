import 'package:alexandria/services/biometric_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// State Class
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

// Provider
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  final secureStorage = ref.read(secureStorageServiceProvider);
  final ipfsService = ref.read(ipfsServiceProvider);
  final identityService = ref.read(identityServiceProvider);
  final biometricService = ref.read(biometricServiceProvider);

  return SettingsNotifier(
    secureStorage,
    ipfsService,
    identityService,
    biometricService,
  );
});

// Notifier
class SettingsNotifier extends StateNotifier<AppSettings> {
  final SecureStorageService _storage;
  final IpfsService _ipfsService;
  final IdentityService _identityService;
  final BiometricService _biometricService;
  final Future<void> Function()? _clearCacheFn;

  SettingsNotifier(
    this._storage,
    this._ipfsService,
    this._identityService,
    this._biometricService, {
    Future<void> Function()? clearCacheFn,
  }) : _clearCacheFn = clearCacheFn,
       super(const AppSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final swarm = await _storage.read('setting_swarm_mode');
    final gateway = await _storage.read('setting_gateway');
    final customGatewaysStr = await _storage.read('setting_custom_gateways');
    final theme = await _storage.read('setting_theme');
    final motion = await _storage.read('setting_reduced_motion');
    final bio = await _storage.read('setting_biometric');

    List<String> loadedGateways = const [
      'https://ipfs.io/ipfs',
      'https://dweb.link/ipfs',
      'https://cloudflare-ipfs.com/ipfs',
    ];

    if (customGatewaysStr != null && customGatewaysStr.isNotEmpty) {
      loadedGateways = [...loadedGateways, ...customGatewaysStr.split(',')];
    }

    ThemeMode mode = ThemeMode.system;
    if (theme == 'light') mode = ThemeMode.light;
    if (theme == 'dark') mode = ThemeMode.dark;

    if (mounted) {
      state = AppSettings(
        ipfsSwarmMode: swarm != 'false', // Default true
        biometricEnabled: bio == 'true', // Default false
        gatewayUrl: gateway ?? 'https://ipfs.io/ipfs',
        availableGateways: loadedGateways,
        themeMode: mode,
        reducedMotion: motion == 'true',
      );
    }
  }

  Future<void> setSwarmMode(bool value) async {
    state = state.copyWith(ipfsSwarmMode: value);
    await _storage.write('setting_swarm_mode', value.toString());
  }

  Future<void> setBiometric(bool value) async {
    state = state.copyWith(biometricEnabled: value);
    await _storage.write('setting_biometric', value.toString());
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    String val = 'system';
    if (mode == ThemeMode.light) val = 'light';
    if (mode == ThemeMode.dark) val = 'dark';
    await _storage.write('setting_theme', val);
  }

  Future<void> setReducedMotion(bool value) async {
    state = state.copyWith(reducedMotion: value);
    await _storage.write('setting_reduced_motion', value.toString());
  }

  Future<void> setGateway(String value) async {
    state = state.copyWith(gatewayUrl: value);
    await _storage.write('setting_gateway', value);
  }

  Future<void> addCustomGateway(String url) async {
    if (!state.availableGateways.contains(url)) {
      final newGateways = [...state.availableGateways, url];
      state = state.copyWith(
        availableGateways: newGateways,
        gatewayUrl: url,
      ); // Auto select

      // Persist only custom ones (simplified logic: store all custom ones as CSV)
      // Filter out defaults to find customs
      final defaults = const [
        'https://ipfs.io/ipfs',
        'https://dweb.link/ipfs',
        'https://cloudflare-ipfs.com/ipfs',
      ];
      final customs = newGateways.where((g) => !defaults.contains(g)).join(',');
      await _storage.write('setting_custom_gateways', customs);
      await _storage.write('setting_gateway', url);
    } else {
      await setGateway(url);
    }
  }

  // Actions

  Future<void> clearCache() async {
    if (_clearCacheFn != null) {
      await _clearCacheFn();
    } else {
      await DefaultCacheManager().emptyCache();
    }
  }

  Future<void> pruneIpfsRepo() async {
    // Assuming IpfsService has a prune method, or we add one.
    // Since we are updating IpfsService next, we call it here.
    await _ipfsService.runGc();
  }

  Future<String?> exportPrivateKey() async {
    final authenticated = await _biometricService.authenticate();
    if (!authenticated) return null;

    final identity = await _identityService.getIdentity();
    if (identity == null) return null;

    return identity.privateKey
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<bool> performBurnerMode() async {
    final authenticated = await _biometricService.authenticate();
    if (!authenticated) return false;

    await _identityService.deleteIdentity();
    await _storage.deleteAll();
    await _ipfsService.runGc(); // Try to clean up
    await clearCache();

    // Reset state
    state = const AppSettings();
    return true;
  }
}
