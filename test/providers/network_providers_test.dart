import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/models/network_models.dart';
import 'package:alexandria/providers/network_providers.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/mesh_transport_service.dart';
import 'package:alexandria/services/network_overview_service.dart';

import '../network_test_fakes.dart';

ProviderContainer _createContainer() => ProviderContainer(
      overrides: [
        networkOverviewServiceProvider.overrideWith(
          (ref) => FakeNetworkOverviewService(ref),
        ),
        meshTransportServiceProvider.overrideWith(
          (ref) => FakeMeshTransportService(),
        ),
        ipfsServiceProvider.overrideWith(
          (ref) => FakeIpfsService(ref),
        ),
      ],
    );

void main() {
  group('network_providers', () {
    test('nodeStatusProvider emits a NodeStatus', () async {
      final container = _createContainer();
      addTearDown(container.dispose);

      final future = container.read(nodeStatusProvider.future);
      await expectLater(future, completion(isA<NodeStatus>()));
    });

    test('networkTelemetryProvider emits a BandwidthStats', () async {
      final container = _createContainer();
      addTearDown(container.dispose);

      final future = container.read(networkTelemetryProvider.future);
      await expectLater(future, completion(isA<BandwidthStats>()));
    });

    test('peerListProvider emits a list of Peer objects', () async {
      final container = _createContainer();
      addTearDown(container.dispose);

      final future = container.read(peerListProvider.future);
      await expectLater(future, completion(isA<List<Peer>>()));
    });

    test('transportsConfigProvider resolves to transport list', () async {
      final container = _createContainer();
      addTearDown(container.dispose);

      final future = container.read(transportsConfigProvider.future);
      final configs = await future;
      expect(configs, isA<List<TransportConfig>>());
      expect(configs, hasLength(3));
    });

    test('syncProgressProvider emits a SyncProgress', () async {
      final container = _createContainer();
      addTearDown(container.dispose);

      final future = container.read(syncProgressProvider.future);
      await expectLater(future, completion(isA<SyncProgress>()));
    });

    test('crdtServiceProvider exposes a CrdtService', () {
      final container = _createContainer();
      addTearDown(container.dispose);

      final service = container.read(crdtServiceProvider);
      expect(service, isA<CrdtService>());
    });

    test('ipfs and mesh providers are overridden with fakes', () {
      final container = _createContainer();
      addTearDown(container.dispose);

      expect(container.read(ipfsServiceProvider), isA<FakeIpfsService>());
      expect(
        container.read(meshTransportServiceProvider),
        isA<FakeMeshTransportService>(),
      );
    });
  });
}
