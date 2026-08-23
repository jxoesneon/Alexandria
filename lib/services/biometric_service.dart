import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'secure_storage_service.dart';

final biometricServiceProvider = Provider((ref) => BiometricService(ref));

class BiometricService {
  final Ref? _ref;
  final LocalAuthentication _auth = LocalAuthentication();

  BiometricService([this._ref]);

  Future<bool> isBiometricsAvailable() async {
    try {
      final canAuth = await _auth.canCheckBiometrics;
      return canAuth || await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  Future<bool> authenticate({String reason = 'Please authenticate to access Alexandria'}) async {
    try {
      final isAvailable = await isBiometricsAvailable();
      if (!isAvailable) return true;

      if (_ref != null) {
        final storage = _ref!.read(secureStorageServiceProvider);
        final secureMode = await storage.read('secure_mode_enabled');
        if (secureMode != 'true') return true;
      }

      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
    } on PlatformException {
      return false;
    }
  }

  Future<void> setSecureMode(bool enabled) async {
    if (_ref != null) {
      final storage = _ref!.read(secureStorageServiceProvider);
      await storage.write('secure_mode_enabled', enabled.toString());
    }
  }
}
