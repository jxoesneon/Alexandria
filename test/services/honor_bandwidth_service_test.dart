import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/honor_bandwidth_service.dart';

void main() {
  group('HonorBandwidthService (test/services)', () {
    late HonorBandwidthService service;

    setUp(() {
      service = HonorBandwidthService(maxConcurrent: 1);
    });

    test('provider exposes a service instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(honorBandwidthServiceProvider),
        isA<HonorBandwidthService>(),
      );
    });

    test('initial queue and in-flight counts are zero', () {
      expect(service.queueLength, equals(0));
      expect(service.inFlightCount, equals(0));
    });

    test('enqueued task completes with its value', () async {
      final result = await service.enqueueRequest(
        requestId: 'r1',
        peerId: 'peer',
        baseHonorScore: 10,
        verifiedPoRCount: 0,
        task: () async => 'done',
      );
      expect(result, equals('done'));
      expect(service.inFlightCount, equals(0));
    });

    test('failed task propagates the error', () async {
      final future = service.enqueueRequest(
        requestId: 'r2',
        peerId: 'peer',
        baseHonorScore: 10,
        verifiedPoRCount: 0,
        task: () async => throw Exception('boom'),
      );

      await expectLater(future, throwsA(isA<Exception>()));
      expect(service.inFlightCount, equals(0));
    });

    test('a SYNCHRONOUSLY throwing task completes with error and '
        'releases the permit (campaign-2)', () async {
      // A task that throws before returning a Future used to leak the
      // in-flight permit — the queue would deadlock once every permit
      // leaked, and the completer never resolved.
      final future = service.enqueueRequest(
        requestId: 'sync-boom',
        peerId: 'peer',
        baseHonorScore: 10,
        verifiedPoRCount: 0,
        task: () => throw StateError('sync boom'),
      );

      await expectLater(future, throwsA(isA<StateError>()));
      // Permit released — a follow-up task must still run.
      final result = await service.enqueueRequest(
        requestId: 'after',
        peerId: 'peer',
        baseHonorScore: 10,
        verifiedPoRCount: 0,
        task: () async => 'recovered',
      );
      expect(result, equals('recovered'));
      expect(service.inFlightCount, equals(0));
    });

    test('concurrency limit keeps excess requests in queue', () async {
      final completer1 = Completer<void>();
      final completer2 = Completer<void>();

      final f1 = service.enqueueRequest(
        requestId: 'r3',
        peerId: 'p1',
        baseHonorScore: 10,
        verifiedPoRCount: 0,
        task: () async {
          await completer1.future;
          return 'first';
        },
      );

      final f2 = service.enqueueRequest(
        requestId: 'r4',
        peerId: 'p2',
        baseHonorScore: 10,
        verifiedPoRCount: 0,
        task: () async {
          await completer2.future;
          return 'second';
        },
      );

      await Future<void>.delayed(Duration.zero);
      expect(service.inFlightCount, equals(1));
      expect(service.queueLength, equals(1));

      completer1.complete();
      completer2.complete();
      await Future.wait([f1, f2]);
    });

    test('higher priority request starts before lower priority one', () async {
      final priorityService = HonorBandwidthService(maxConcurrent: 2);
      final lowCompleter = Completer<void>();
      final highCompleter = Completer<void>();
      final order = <String>[];

      final low = priorityService.enqueueRequest(
        requestId: 'low',
        peerId: 'p-low',
        baseHonorScore: 10,
        verifiedPoRCount: 0,
        task: () async {
          await lowCompleter.future;
          order.add('low');
          return 'low';
        },
      );

      final high = priorityService.enqueueRequest(
        requestId: 'high',
        peerId: 'p-high',
        baseHonorScore: 100,
        verifiedPoRCount: 20,
        task: () async {
          await highCompleter.future;
          order.add('high');
          return 'high';
        },
      );

      expect(priorityService.inFlightCount, equals(2));

      highCompleter.complete();
      await Future<void>.delayed(Duration.zero);
      lowCompleter.complete();

      await Future.wait([low, high]);
      expect(order.first, equals('high'));
      expect(order.last, equals('low'));
    });

    test('BandwidthRequest.computeEffectivePriority uses wait time', () {
      final now = DateTime(2025, 1, 1, 12, 0, 10);
      final requestTime = DateTime(2025, 1, 1, 12, 0, 0);
      final req = BandwidthRequest<int>(
        requestId: 'r5',
        peerId: 'peer',
        baseHonorScore: 20,
        verifiedPoRCount: 5,
        requestTime: requestTime,
        task: () async => 0,
        completer: Completer<int>(),
      );

      final priority = req.computeEffectivePriority(now);
      expect(priority, equals((20 * 0.5) + (5 * 2.0) + (10 * 0.2)));
    });
  });
}
