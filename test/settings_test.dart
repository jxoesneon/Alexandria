import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/logic/settings_logic.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

// --- Fakes ---

class FakeSecureStorageService implements SecureStorageService {
  final Map<String, String> _storage = {};

  @override
  Future<String?> read(String key) async => _storage[key];

  @override
  Future<void> write(String key, String value) async => _storage[key] = value;

  @override
  Future<void> delete(String key) async => _storage.remove(key);

  @override
  Future<void> deleteAll() async => _storage.clear();

  @override
  Future<bool> containsKey(String key) async => _storage.containsKey(key);
}

class FakeIpfsService implements IpfsService {
  bool gcRun = false;

  @override
  Future<bool> runGc() async {
    gcRun = true;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    return '.';
  });

  late SettingsNotifier notifier;
  late FakeSecureStorageService storage;
  late FakeIpfsService ipfs;

  setUp(() {
    storage = FakeSecureStorageService();
    ipfs = FakeIpfsService();
    notifier = SettingsNotifier(storage, ipfs);
  });

  group('SettingsLogic', () {
    test('Initial state loads defaults', () async {
      expect(notifier.state.themeMode, ThemeMode.system);
      expect(notifier.state.reducedMotion, false);
      expect(notifier.state.biometricEnabled, false);
    });

    test('Updating Theme persists setting', () async {
      await notifier.setThemeMode(ThemeMode.light);
      expect(notifier.state.themeMode, ThemeMode.light);
      expect(await storage.read('setting_theme'), 'light');

      await notifier.setThemeMode(ThemeMode.dark);
      expect(notifier.state.themeMode, ThemeMode.dark);
      expect(await storage.read('setting_theme'), 'dark');
    });

    test('Updating Reduced Motion persists setting', () async {
      await notifier.setReducedMotion(true);
      expect(notifier.state.reducedMotion, true);
      expect(await storage.read('setting_reduced_motion'), 'true');
    });

    test('Prune IPFS Repo triggers GC', () async {
      await notifier.pruneIpfsRepo();
      expect(ipfs.gcRun, true);
    });
  });
}
