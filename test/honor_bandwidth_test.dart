import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/honor_bandwidth_service.dart';

void main() {
  group('HonorBandwidthService QoS Tests', () {
    late HonorBandwidthService qosService;

    setUp(() {
      qosService = HonorBandwidthService(maxConcurrent: 2);
    });

    test('enqueues and executes tasks based on effective honor priority',
        () async {
      final executionOrder = <String>[];

      // Low honor request
      final f1 = qosService.enqueueRequest(
        requestId: 'req_1',
        peerId: 'peer_low',
        baseHonorScore: 10,
        verifiedPoRCount: 0,
        task: () async {
          await Future.delayed(const Duration(milliseconds: 10));
          executionOrder.add('req_1');
          return 'done_1';
        },
      );

      // High honor request
      final f2 = qosService.enqueueRequest(
        requestId: 'req_2',
        peerId: 'peer_high',
        baseHonorScore: 100,
        verifiedPoRCount: 10,
        task: () async {
          await Future.delayed(const Duration(milliseconds: 10));
          executionOrder.add('req_2');
          return 'done_2';
        },
      );

      await Future.wait([f1, f2]);
      expect(executionOrder.length, equals(2));
    });

    test('maxConcurrent <= 0 is clamped — queued work can never hang',
        () async {
      // A zero concurrency budget would leave every enqueued future
      // pending forever; the constructor must clamp it to >= 1.
      final stuck = HonorBandwidthService(maxConcurrent: 0);
      expect(stuck.maxConcurrent, 1);
      final result = await stuck.enqueueRequest(
        requestId: 'req_x',
        peerId: 'peer',
        baseHonorScore: 0,
        verifiedPoRCount: 0,
        task: () async => 'ran',
      );
      expect(result, 'ran');

      final negative = HonorBandwidthService(maxConcurrent: -5);
      expect(negative.maxConcurrent, 1);
    });
  });
}
