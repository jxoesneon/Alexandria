import 'package:alexandria/logic/settings_logic.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:alexandria/services/tor_service.dart';
import 'package:alexandria/ui/settings/settings_screen.dart';
import 'package:alexandria/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSecureStorageService implements SecureStorageService {
  @override
  String get keyPrefix => '';
  final _storage = <String, String>{};

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

class _FakeIpfsService implements IpfsService {
  @override
  int get storedBytes => 0;

  @override
  Future<bool> runGc() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTorService implements TorService {
  bool _enabled = false;
  final bool _success;

  _FakeTorService({bool enabled = false, bool success = true})
      : _enabled = enabled,
        _success = success;

  @override
  bool get isEnabled => _enabled;

  @override
  Future<bool> enable() async {
    _enabled = _success;
    return _success;
  }

  @override
  Future<void> disable() async {
    _enabled = false;
  }

  @override
  String get proxyAddress => '127.0.0.1:9050';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget createSubject({
    required _FakeTorService tor,
  }) {
    return ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => SettingsNotifier(
              _FakeSecureStorageService(),
              _FakeIpfsService(),
            )),
        torServiceProvider.overrideWithValue(tor),
        torStatusProvider.overrideWith((ref) => TorStatus.disabled),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const SettingsScreen(),
      ),
    );
  }

  testWidgets('SettingsScreen enables and disables Tor via switch',
      (tester) async {
    final tor = _FakeTorService();

    await tester.pumpWidget(createSubject(tor: tor));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Tor Disabled'), findsOneWidget);

    await tester.tap(find.text('Route via Tor Proxy (SOCKS5)'));
    await tester.pumpAndSettle();

    expect(tor.isEnabled, isTrue);
    expect(find.text('Connected via Tor (127.0.0.1:9050)'), findsOneWidget);

    await tester.tap(find.text('Route via Tor Proxy (SOCKS5)'));
    await tester.pumpAndSettle();

    expect(tor.isEnabled, isFalse);
    expect(find.text('Tor Disabled'), findsOneWidget);
  });

  testWidgets('SettingsScreen shows Tor error when enable fails',
      (tester) async {
    final tor = _FakeTorService(success: false);

    await tester.pumpWidget(createSubject(tor: tor));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Route via Tor Proxy (SOCKS5)'));
    await tester.pumpAndSettle();

    expect(find.text('Tor Connection Failed — Check your Tor daemon'),
        findsOneWidget);
  });
}
