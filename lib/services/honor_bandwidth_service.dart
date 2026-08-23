import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final honorBandwidthServiceProvider = Provider((ref) => HonorBandwidthService());

class BandwidthRequest<T> {
  final String requestId;
  final String peerId;
  final int baseHonorScore;
  final int verifiedPoRCount;
  final DateTime requestTime;
  final Future<T> Function() task;
  final Completer<T> completer;

  BandwidthRequest({
    required this.requestId,
    required this.peerId,
    required this.baseHonorScore,
    required this.verifiedPoRCount,
    required this.requestTime,
    required this.task,
    required this.completer,
  });

  double computeEffectivePriority(DateTime now) {
    final waitSeconds = now.difference(requestTime).inSeconds;
    // Weighted priority = (BaseHonor * 0.5) + (VerifiedPoR * 2.0) + (AntiStarvationAge * 0.2)
    return (baseHonorScore * 0.5) + (verifiedPoRCount * 2.0) + (waitSeconds * 0.2);
  }
}

class HonorBandwidthService {
  final List<BandwidthRequest> _requestQueue = [];
  final int maxConcurrent;
  int _inFlightCount = 0;

  HonorBandwidthService({this.maxConcurrent = 4});

  int get queueLength => _requestQueue.length;
  int get inFlightCount => _inFlightCount;

  Future<T> enqueueRequest<T>({
    required String requestId,
    required String peerId,
    required int baseHonorScore,
    required int verifiedPoRCount,
    required Future<T> Function() task,
  }) {
    final completer = Completer<T>();
    final req = BandwidthRequest<T>(
      requestId: requestId,
      peerId: peerId,
      baseHonorScore: baseHonorScore,
      verifiedPoRCount: verifiedPoRCount,
      requestTime: DateTime.now(),
      task: task,
      completer: completer,
    );

    _requestQueue.add(req);
    _processQueue();
    return completer.future;
  }

  void _processQueue() {
    if (_inFlightCount >= maxConcurrent || _requestQueue.isEmpty) return;

    final now = DateTime.now();
    _requestQueue.sort((a, b) {
      final pA = a.computeEffectivePriority(now);
      final pB = b.computeEffectivePriority(now);
      return pB.compareTo(pA); // Descending priority
    });

    final next = _requestQueue.removeAt(0);
    _inFlightCount++;

    next.task().then((result) {
      next.completer.complete(result);
    }).catchError((err, st) {
      next.completer.completeError(err, st);
    }).whenComplete(() {
      _inFlightCount--;
      _processQueue();
    });
  }
}
