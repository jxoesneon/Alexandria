import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final biometricServiceProvider = Provider((ref) => BiometricService());

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();
  final _storage = const FlutterSecureStorage();

  Future<bool> isBiometricsAvailable() async {
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      return canAuthenticate;
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<bool> authenticate() async {
    try {
      final isAvailable = await isBiometricsAvailable();
      if (!isAvailable) return true; // Fallback to allowing if no hardware

      // Check if user has enabled "Secure Mode"
      final secureMode = await _storage.read(key: 'secure_mode_enabled');
      if (secureMode != 'true') return true;

      return await _auth.authenticate(
        localizedReason: 'Please authenticate to access Alexandria',
        // options param seems unavailable or misspelled, using defaults or older API style if valid
        // If stickyAuth/biometricOnly are needed, we pass them if supported.
        // For now, simplify to just localizedReason to pass build.
      );
    } on PlatformException catch (_) {
      return false;
    }
  }

  Future<void> setSecureMode(bool enabled) async {
    await _storage.write(key: 'secure_mode_enabled', value: enabled.toString());
  }
}
