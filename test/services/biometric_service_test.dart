import 'package:alexandria/services/biometric_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSecureStorage implements SecureStorageService {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> deleteAll() async => _data.clear();

  @override
  Future<bool> containsKey(String key) async => _data.containsKey(key);
}

final _testBiometricProvider = Provider((ref) => BiometricService(ref));

void main() {
  group('BiometricService', () {
    const channel = MethodChannel('plugins.flutter.io/local_auth');
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(_FakeSecureStorage()),
        ],
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'isDeviceSupported') return true;
        if (call.method == 'canCheckBiometrics') return true;
        if (call.method == 'getAvailableBiometrics') return ['fingerprint'];
        if (call.method == 'authenticate') return true;
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      container.dispose();
    });

    BiometricService getService() => container.read(_testBiometricProvider);

    test('isBiometricsAvailable returns true when device supports biometrics',
        () async {
      expect(await getService().isBiometricsAvailable(), isTrue);
    });

    test('authenticate returns true when secure mode is disabled', () async {
      expect(await getService().authenticate(), isTrue);
    });

    test('setSecureMode writes to storage', () async {
      final service = getService();
      await service.setSecureMode(true);
      expect(
          await container
              .read(secureStorageServiceProvider)
              .read('secure_mode_enabled'),
          'true');
      await service.setSecureMode(false);
      expect(
          await container
              .read(secureStorageServiceProvider)
              .read('secure_mode_enabled'),
          'false');
    });

    test('authenticate with secure mode enabled invokes platform', () async {
      final service = getService();
      await service.setSecureMode(true);
      expect(await service.authenticate(), isTrue);
    });

    test('isBiometricsAvailable returns false on platform exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ERR');
      });
      expect(await getService().isBiometricsAvailable(), isFalse);
    });

    test('authenticate returns false on platform exception', () async {
      final service = getService();
      await service.setSecureMode(true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'isDeviceSupported') return true;
        if (call.method == 'canCheckBiometrics') return true;
        if (call.method == 'authenticate') {
          throw PlatformException(code: 'ERR');
        }
        return null;
      });
      expect(await service.authenticate(), isFalse);
    });

    test('isBiometricsAvailable returns true when isDeviceSupported only',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'canCheckBiometrics') return false;
        if (call.method == 'isDeviceSupported') return true;
        return null;
      });
      expect(await getService().isBiometricsAvailable(), isTrue);
    });

    test('isBiometricsAvailable returns false when neither is supported',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'canCheckBiometrics') return false;
        if (call.method == 'isDeviceSupported') return false;
        return null;
      });
      expect(await getService().isBiometricsAvailable(), isFalse);
    });

    test('authenticate returns true when biometrics unavailable', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'canCheckBiometrics') return false;
        if (call.method == 'isDeviceSupported') return false;
        return null;
      });
      expect(await getService().authenticate(), isTrue);
    });

    test('setSecureMode does nothing when no ref is provided', () async {
      final service = BiometricService();
      await service.setSecureMode(true);
      // Should complete without error.
      expect(true, isTrue);
    });

    test('authenticate with null ref and no biometrics returns true', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'canCheckBiometrics') return false;
        if (call.method == 'isDeviceSupported') return false;
        return null;
      });
      final service = BiometricService();
      expect(await service.authenticate(), isTrue);
    });

    test('authenticate returns false when platform auth returns false',
        () async {
      final service = getService();
      await service.setSecureMode(true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'isDeviceSupported') return true;
        if (call.method == 'canCheckBiometrics') return true;
        if (call.method == 'authenticate') return false;
        return null;
      });
      expect(await service.authenticate(), isFalse);
    });

    test('authenticate returns true when secure mode is explicitly disabled',
        () async {
      final service = getService();
      await service.setSecureMode(false);
      expect(await service.authenticate(), isTrue);
    });

    test('biometricServiceProvider is readable', () {
      final service = container.read(biometricServiceProvider);
      expect(service, isA<BiometricService>());
    });
  });
}
