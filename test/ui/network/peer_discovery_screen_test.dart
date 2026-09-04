import 'dart:async';

import 'package:alexandria/models/network_models.dart';
import 'package:alexandria/providers/network_providers.dart';
import 'package:alexandria/services/mesh_transport_service.dart';
import 'package:alexandria/services/network_overview_service.dart';
import 'package:alexandria/ui/network/peer_discovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeNetworkOverviewService extends NetworkOverviewService {
  FakeNetworkOverviewService(super.ref);

  final _peerController = StreamController<List<Peer>>.broadcast();

  @override
  Stream<List<Peer>> watchPeers() async* {
    yield [
      const Peer(
        peerId: '12D3KooWF8a',
        multiaddr: '/ip4/192.168.1.10/tcp/4001/p2p/12D3KooWF8a',
        latencyMs: 45,
        status: PeerStatus.connected,
      ),
      const Peer(
        peerId: '12D3KooWN9b',
        multiaddr: '/ip4/192.168.1.11/tcp/4001/p2p/12D3KooWN9b',
        latencyMs: 112,
        status: PeerStatus.disconnected,
      ),
    ];
    yield* _peerController.stream;
  }

  @override
  void dispose() {
    _peerController.close();
    super.dispose();
  }
}

class FakeMeshTransportService extends MeshTransportService {
  String? lastConnect;
  String? lastDisconnect;
  MeshPeer? lastRegistered;

  @override
  void registerPeer(MeshPeer peer) {
    lastRegistered = peer;
    super.registerPeer(peer);
  }

  @override
  Future<bool> connectToPeer(String multiaddr) async {
    lastConnect = multiaddr;
    return true;
  }

  @override
  Future<void> disconnectPeer(String peerId) async {
    lastDisconnect = peerId;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PeerDiscoveryScreen renders peer list', (tester) async {
    final fakeMesh = FakeMeshTransportService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkOverviewServiceProvider.overrideWith(
            (ref) => FakeNetworkOverviewService(ref),
          ),
          meshTransportServiceProvider.overrideWith((ref) => fakeMesh),
        ],
        child: const MaterialApp(
          home: PeerDiscoveryScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Peer Discovery & Mesh'), findsOneWidget);
    expect(find.text('12D3KooWF8a'), findsOneWidget);
    expect(find.text('12D3KooWN9b'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
  });

  testWidgets('PeerDiscoveryScreen handles empty peer list', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          peerListProvider.overrideWith(
            (ref) => Stream<List<Peer>>.value(const []),
          ),
        ],
        child: const MaterialApp(
          home: PeerDiscoveryScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No peers discovered'), findsOneWidget);
  });

  testWidgets('Connect/disconnect peer triggers service calls', (tester) async {
    final fakeMesh = FakeMeshTransportService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkOverviewServiceProvider.overrideWith(
            (ref) => FakeNetworkOverviewService(ref),
          ),
          meshTransportServiceProvider.overrideWith((ref) => fakeMesh),
        ],
        child: const MaterialApp(
          home: PeerDiscoveryScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final disconnectButton = find.byIcon(Icons.link_off);
    final connectButton = find.byIcon(Icons.link);

    expect(disconnectButton, findsOneWidget);
    expect(connectButton, findsOneWidget);

    await tester.tap(connectButton);
    await tester.pump();

    expect(
      fakeMesh.lastConnect,
      '/ip4/192.168.1.11/tcp/4001/p2p/12D3KooWN9b',
    );

    await tester.tap(disconnectButton);
    await tester.pump();

    expect(fakeMesh.lastDisconnect, '12D3KooWF8a');
  });

  testWidgets('PeerDiscoveryScreen shows loading state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          peerListProvider.overrideWith(
            (ref) => const Stream<List<Peer>>.empty(),
          ),
        ],
        child: const MaterialApp(
          home: PeerDiscoveryScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('PeerDiscoveryScreen shows error state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          peerListProvider.overrideWith(
            (ref) => Stream<List<Peer>>.error(Exception('peers error')),
          ),
        ],
        child: const MaterialApp(
          home: PeerDiscoveryScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Error loading peers:'), findsOneWidget);
  });

  testWidgets('PeerDiscoveryScreen shows pending peer', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          peerListProvider.overrideWith(
            (ref) => Stream<List<Peer>>.value(const [
              Peer(
                peerId: 'pending-peer',
                multiaddr: '/ip4/1.1.1.1/tcp/1',
                latencyMs: 10,
                status: PeerStatus.pending,
              ),
            ]),
          ),
        ],
        child: const MaterialApp(
          home: PeerDiscoveryScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Pending'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('PeerDiscoveryScreen adds a peer with p2p id', (tester) async {
    final fakeMesh = FakeMeshTransportService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          peerListProvider.overrideWith(
            (ref) => Stream<List<Peer>>.value(const []),
          ),
          meshTransportServiceProvider.overrideWith((ref) => fakeMesh),
        ],
        child: const MaterialApp(
          home: PeerDiscoveryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Add peer'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).first,
      '/ip4/10.0.0.1/tcp/4001/p2p/12D3KooWAdd',
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(fakeMesh.lastRegistered, isNotNull);
    expect(fakeMesh.lastRegistered!.peerId, '12D3KooWAdd');
    expect(
      fakeMesh.lastRegistered!.address,
      '/ip4/10.0.0.1/tcp/4001/p2p/12D3KooWAdd',
    );
  });

  testWidgets('PeerDiscoveryScreen adds a peer without p2p id', (tester) async {
    final fakeMesh = FakeMeshTransportService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          peerListProvider.overrideWith(
            (ref) => Stream<List<Peer>>.value(const []),
          ),
          meshTransportServiceProvider.overrideWith((ref) => fakeMesh),
        ],
        child: const MaterialApp(
          home: PeerDiscoveryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.enterText(
      find.byType(TextField).first,
      '/ip4/10.0.0.1/tcp/4001',
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(fakeMesh.lastRegistered, isNotNull);
    expect(fakeMesh.lastRegistered!.peerId.isNotEmpty, isTrue);
    expect(
      fakeMesh.lastRegistered!.address,
      '/ip4/10.0.0.1/tcp/4001',
    );
  });

  testWidgets('PeerDiscoveryScreen cancels add peer dialog', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          peerListProvider.overrideWith(
            (ref) => Stream<List<Peer>>.value(const []),
          ),
        ],
        child: const MaterialApp(
          home: PeerDiscoveryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Add peer'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Add peer'), findsNothing);
  });
}
