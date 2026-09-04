import 'dart:async';

import 'package:alexandria/models/network_models.dart';
import 'package:alexandria/providers/network_providers.dart';
import 'package:alexandria/services/network_overview_service.dart';
import 'package:alexandria/ui/network/network_overview_screen.dart';
import '../../network_test_fakes.dart' as network;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeNetworkOverviewService extends NetworkOverviewService {
  FakeNetworkOverviewService(super.ref);

  final _nodeController = StreamController<NodeStatus>.broadcast();
  final _bandwidthController = StreamController<BandwidthStats>.broadcast();

  bool _isRunning = true;
  int _connectedPeers = 3;

  set isRunning(bool value) {
    _isRunning = value;
    _emitNode();
  }

  set connectedPeers(int value) {
    _connectedPeers = value;
    _emitNode();
  }

  void _emitNode() {
    if (!_nodeController.isClosed) {
      _nodeController.add(
        NodeStatus(
          isRunning: _isRunning,
          connectedPeers: _connectedPeers,
          nodeId: 'test-node',
        ),
      );
    }
  }

  @override
  Stream<NodeStatus> watchNodeStatus() async* {
    yield NodeStatus(
      isRunning: _isRunning,
      connectedPeers: _connectedPeers,
      nodeId: 'test-node',
    );
    yield* _nodeController.stream;
  }

  @override
  Stream<BandwidthStats> watchBandwidthUsage() async* {
    yield BandwidthStats(
      uploadBps: 1200,
      downloadBps: 3400,
      timestamp: DateTime.now(),
    );
    yield* _bandwidthController.stream;
  }

  @override
  Future<void> startNode() async {
    _isRunning = true;
    _emitNode();
  }

  @override
  Future<void> stopNode() async {
    _isRunning = false;
    _emitNode();
  }

  @override
  void dispose() {
    _nodeController.close();
    _bandwidthController.close();
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('NetworkOverviewScreen renders node status and bandwidth',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkOverviewServiceProvider.overrideWith(
            (ref) => FakeNetworkOverviewService(ref),
          ),
        ],
        child: const MaterialApp(
          home: NetworkOverviewScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Node Operations Dashboard'), findsOneWidget);
    expect(find.text('Network status'), findsOneWidget);
    expect(find.text('Bandwidth usage'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Peers: 3'), findsOneWidget);
    expect(find.text('1.2 Kbps'), findsOneWidget);
    expect(find.text('3.4 Kbps'), findsOneWidget);
  });

  testWidgets('Start/stop node toggles status', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkOverviewServiceProvider.overrideWith(
            (ref) => FakeNetworkOverviewService(ref),
          ),
        ],
        child: const MaterialApp(
          home: NetworkOverviewScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Stop node'), findsOneWidget);

    await tester.tap(find.text('Stop node'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Stopped'), findsOneWidget);
    expect(find.text('Start node'), findsOneWidget);

    await tester.tap(find.text('Start node'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Stop node'), findsOneWidget);
  });

  testWidgets('NetworkOverviewScreen handles empty/error telemetry',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkTelemetryProvider.overrideWith(
            (ref) =>
                Stream<BandwidthStats>.error(Exception('telemetry failed')),
          ),
          nodeStatusProvider.overrideWith(
            (ref) => Stream<NodeStatus>.error(Exception('status failed')),
          ),
        ],
        child: const MaterialApp(
          home: NetworkOverviewScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Failed to load status'), findsOneWidget);
    expect(find.textContaining('Failed to load telemetry'), findsOneWidget);
  });

  testWidgets('NetworkOverviewScreen shows loading state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nodeStatusProvider.overrideWith(
            (ref) => const Stream<NodeStatus>.empty(),
          ),
          networkTelemetryProvider.overrideWith(
            (ref) => const Stream<BandwidthStats>.empty(),
          ),
        ],
        child: const MaterialApp(
          home: NetworkOverviewScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
  });

  testWidgets('NetworkOverviewScreen formats bps and Mbps', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nodeStatusProvider.overrideWith(
            (ref) => Stream<NodeStatus>.value(
              const NodeStatus(
                isRunning: true,
                connectedPeers: 1,
                nodeId: 'test',
              ),
            ),
          ),
          networkTelemetryProvider.overrideWith(
            (ref) => Stream<BandwidthStats>.value(
              BandwidthStats(
                uploadBps: 500,
                downloadBps: 2000000,
                timestamp: DateTime.now(),
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: NetworkOverviewScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('500 bps'), findsOneWidget);
    expect(find.text('2.00 Mbps'), findsOneWidget);
  });

  testWidgets('NetworkOverviewScreen navigates to Peer Discovery',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkOverviewServiceProvider.overrideWith(
            (ref) => network.FakeNetworkOverviewService(ref),
          ),
        ],
        child: const MaterialApp(
          home: NetworkOverviewScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Peer Discovery'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Peer Discovery & Mesh'), findsOneWidget);
  });

  testWidgets('NetworkOverviewScreen navigates to Transports', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkOverviewServiceProvider.overrideWith(
            (ref) => network.FakeNetworkOverviewService(ref),
          ),
        ],
        child: const MaterialApp(
          home: NetworkOverviewScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Transports'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Transports Configuration'), findsOneWidget);
  });

  testWidgets('NetworkOverviewScreen navigates to Sync & Conflicts',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkOverviewServiceProvider.overrideWith(
            (ref) => network.FakeNetworkOverviewService(ref),
          ),
        ],
        child: const MaterialApp(
          home: NetworkOverviewScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Sync & Conflicts'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Sync & Conflict Resolution'), findsOneWidget);
  });
}
