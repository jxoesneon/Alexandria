import 'package:alexandria/models/network_models.dart';
import 'package:alexandria/providers/network_providers.dart';
import 'package:alexandria/services/network_overview_service.dart';
import 'package:alexandria/ui/network/transports_config_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeNetworkOverviewService extends NetworkOverviewService {
  FakeNetworkOverviewService(super.ref);

  final _configs = [
    const TransportConfig(
      protocol: TransportProtocol.ipfs,
      enabled: true,
      port: 4001,
      relay: '',
    ),
    const TransportConfig(
      protocol: TransportProtocol.webrtc,
      enabled: false,
      port: 0,
      relay: '',
    ),
    const TransportConfig(
      protocol: TransportProtocol.tor,
      enabled: false,
      port: 9050,
      relay: '127.0.0.1:9050',
    ),
  ];

  TransportConfig? lastUpdated;
  bool testCalled = false;

  @override
  Future<List<TransportConfig>> getTransports() async => _configs;

  @override
  Future<void> updateTransport(TransportConfig config) async {
    lastUpdated = config;
    final index = _configs.indexWhere((c) => c.protocol == config.protocol);
    if (index >= 0) {
      _configs[index] = config;
    }
  }

  @override
  Future<String> testConnections() async {
    testCalled = true;
    return 'All transports tested';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TransportsConfigScreen renders transport list', (tester) async {
    late FakeNetworkOverviewService fake;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkOverviewServiceProvider.overrideWith((ref) {
            fake = FakeNetworkOverviewService(ref);
            return fake;
          }),
        ],
        child: const MaterialApp(
          home: TransportsConfigScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Transports Configuration'), findsOneWidget);
    expect(find.text('IPFS'), findsOneWidget);
    expect(find.byType(Switch), findsWidgets);
  });

  testWidgets('TransportsConfigScreen tests configuration', (tester) async {
    late FakeNetworkOverviewService fake;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkOverviewServiceProvider.overrideWith((ref) {
            fake = FakeNetworkOverviewService(ref);
            return fake;
          }),
        ],
        child: const MaterialApp(
          home: TransportsConfigScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Test connection'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(fake.testCalled, isTrue);
    expect(find.text('All transports tested'), findsOneWidget);
  });

  testWidgets('TransportsConfigScreen saves configuration', (tester) async {
    late FakeNetworkOverviewService fake;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkOverviewServiceProvider.overrideWith((ref) {
            fake = FakeNetworkOverviewService(ref);
            return fake;
          }),
        ],
        child: const MaterialApp(
          home: TransportsConfigScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byType(Switch).last);
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(fake.lastUpdated, isNotNull);
    expect(find.text('Transport settings saved'), findsOneWidget);
  });

  testWidgets('TransportsConfigScreen handles load error', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transportsConfigProvider.overrideWith(
            (ref) => Future<List<TransportConfig>>.error(
              Exception('load failed'),
            ),
          ),
        ],
        child: const MaterialApp(
          home: TransportsConfigScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Error:'), findsOneWidget);
  });
}
