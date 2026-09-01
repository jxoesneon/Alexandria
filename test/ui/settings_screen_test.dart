import 'package:alexandria/logic/settings_logic.dart';
import 'package:alexandria/services/biometric_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:alexandria/services/tor_service.dart';
import 'package:alexandria/ui/settings/settings_screen.dart';
import 'package:alexandria/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// --- Fakes ---

class FakeSecureStorageService implements SecureStorageService {
  final Map<String, String> storage = {};
  @override
  Future<String?> read(String key) async => storage[key];
  @override
  Future<void> write(String key, String value) async => storage[key] = value;
  @override
  Future<void> delete(String key) async => storage.remove(key);
  @override
  Future<void> deleteAll() async => storage.clear();
  @override
  Future<bool> containsKey(String key) async => storage.containsKey(key);
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

class FakeTorService implements TorService {
  bool enabled = false;

  @override
  bool get isEnabled => enabled;

  @override
  Future<bool> enable() async {
    enabled = true;
    return true;
  }

  @override
  Future<void> disable() async {
    enabled = false;
  }

  @override
  String get proxyAddress => '127.0.0.1:9050';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSecureStorageService storage;
  late FakeIpfsService ipfs;
  late FakeTorService tor;
  late SettingsNotifier settingsNotifier;

  setUp(() {
    storage = FakeSecureStorageService();
    ipfs = FakeIpfsService();
    tor = FakeTorService();
    settingsNotifier = SettingsNotifier(storage, ipfs);
  });

  Widget createSubject() {
    return ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => settingsNotifier),
        torServiceProvider.overrideWithValue(tor),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const SettingsScreen(),
      ),
    );
  }

  testWidgets('SettingsScreen renders all sections', (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Network & Privacy'), findsOneWidget);
    expect(find.text('Storage & Maintenance'), findsOneWidget);
  });

  testWidgets('Theme dropdown updates state', (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    final dropdownFinder = find.byType(DropdownButton<ThemeMode>);
    expect(dropdownFinder, findsOneWidget);
    await tester.tap(dropdownFinder);
    await tester.pumpAndSettle();

    final lightOption = find.text('Light').last;
    await tester.tap(lightOption);
    await tester.pumpAndSettle();

    expect(settingsNotifier.state.themeMode, ThemeMode.light);
    expect(storage.storage['setting_theme'], 'light');
  });

  testWidgets('Reduced Motion toggle updates state', (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    final reducedMotionFinder = find.text('Reduced Motion');
    await tester.tap(reducedMotionFinder);
    await tester.pumpAndSettle();

    expect(settingsNotifier.state.reducedMotion, true);
  });

  testWidgets('Prune Repo triggers GC', (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    final pruneFinder = find.text('Prune');
    await tester.tap(pruneFinder);
    await tester.pumpAndSettle();

    expect(ipfs.gcRun, true);
    expect(find.text('Storage cleanup completed successfully.'), findsOneWidget);
  });

  testWidgets('Emergency Data Wipe shows confirmation dialog', (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();

    final wipeFinder = find.text('Emergency Data Wipe');
    await tester.tap(wipeFinder);
    await tester.pumpAndSettle();

    expect(find.text('Confirm Emergency Data Wipe'), findsOneWidget);
    expect(find.text('Confirm Wipe'), findsOneWidget);

    await tester.tap(find.text('Confirm Wipe'));
    await tester.pumpAndSettle();
    expect(find.text('Data wipe completed.'), findsOneWidget);
  });
}
