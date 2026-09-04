import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/network_models.dart';
import '../services/network_overview_service.dart';

final nodeStatusProvider = StreamProvider<NodeStatus>((ref) {
  final service = ref.watch(networkOverviewServiceProvider);
  return service.watchNodeStatus();
});

final networkTelemetryProvider = StreamProvider<BandwidthStats>((ref) {
  final service = ref.watch(networkOverviewServiceProvider);
  return service.watchBandwidthUsage();
});

final peerListProvider = StreamProvider<List<Peer>>((ref) {
  final service = ref.watch(networkOverviewServiceProvider);
  return service.watchPeers();
});

final transportsConfigProvider = FutureProvider<List<TransportConfig>>((ref) {
  final service = ref.watch(networkOverviewServiceProvider);
  return service.getTransports();
});

final syncProgressProvider = StreamProvider<SyncProgress>((ref) {
  final service = ref.watch(networkOverviewServiceProvider);
  return service.watchSyncProgress();
});

final crdtServiceProvider = Provider<CrdtService>((ref) {
  final network = ref.watch(networkOverviewServiceProvider);
  return CrdtService(network);
});
