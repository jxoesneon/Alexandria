import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alexandria/logic/settings_logic.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  group('SettingsLogic & AppSettings Notifier Tests', () {
    late ProviderContainer container;
    late SettingsNotifier notifier;

    setUp(() async {
      container = ProviderContainer();
      notifier = container.read(settingsProvider.notifier);
      await notifier.loadSettings();
    });

    tearDown(() {
      container.dispose();
    });

    test('updates theme mode and persists state', () async {
      await notifier.setThemeMode(ThemeMode.light);
      expect(
          container.read(settingsProvider).themeMode, equals(ThemeMode.light));

      await notifier.setThemeMode(ThemeMode.dark);
      expect(
          container.read(settingsProvider).themeMode, equals(ThemeMode.dark));
    });

    test('toggles reduced motion preference', () async {
      await notifier.setReducedMotion(true);
      expect(container.read(settingsProvider).reducedMotion, isTrue);

      await notifier.setReducedMotion(false);
      expect(container.read(settingsProvider).reducedMotion, isFalse);
    });

    test('prunes IPFS repository via GC', () async {
      await notifier.pruneIpfsRepo();
    });
  });
}
