import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final honorBandwidthServiceProvider =
    Provider((ref) => HonorBandwidthService());

/// Attested honor credentials for a peer, supplied by an attestation
/// source (ledger/honor records), NOT by the requesting caller.
class HonorAttestation {
  final int honorScore;
  final int porCount;

  const HonorAttestation({
    required this.honorScore,
    required this.porCount,
  });
}

/// Resolves a peer's honor credentials from a trusted source. Wired by
/// the embedder (e.g. a ledger-backed honor registry); when absent the
/// queue treats all caller claims as unverified.
typedef HonorAttestationResolver = Future<HonorAttestation> Function(
    String peerId);

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
    return (baseHonorScore * 0.5) +
        (verifiedPoRCount * 2.0) +
        (waitSeconds * 0.2);
  }
}

class HonorBandwidthService {
  final List<BandwidthRequest> _requestQueue = [];
  final int maxConcurrent;
  int _inFlightCount = 0;

  /// Attestation source for peer honor credentials (round-3 red
  /// finding). When wired, caller-supplied `baseHonorScore`/
  /// `verifiedPoRCount` are REPLACED by the attested values. When
  /// absent, self-declared scores contribute NOTHING to priority -
  /// ordering falls back to FIFO plus the anti-starvation age term, so
  /// a forged INT_MAX claim can never starve honest queued work.
  final HonorAttestationResolver? attestationResolver;

  /// Hard bounds applied even to ATTESTED values - a compromised or
  /// buggy attestation source must not mint unbounded priority either.
  static const int maxAttestedHonor = 100000;
  static const int maxAttestedPoR = 10000;

  /// [maxConcurrent] is clamped to at least 1: a zero/negative budget
  /// would leave every enqueued task pending forever - the completer
  /// futures would hang silently instead of running (availability bug,
  /// not a footgun worth allowing).
  HonorBandwidthService({
    int maxConcurrent = 4,
    this.attestationResolver,
  }) : maxConcurrent = maxConcurrent < 1 ? 1 : maxConcurrent;

  int get queueLength => _requestQueue.length;
  int get inFlightCount => _inFlightCount;

  /// (round-3 red finding) `baseHonorScore` and `verifiedPoRCount` are
  /// caller-supplied CLAIMS: without an [attestationResolver] they are
  /// ignored entirely - a request can no longer declare itself to the
  /// front of the queue.
  Future<T> enqueueRequest<T>({
    required String requestId,
    required String peerId,
    required int baseHonorScore,
    required int verifiedPoRCount,
    required Future<T> Function() task,
  }) {
    final completer = Completer<T>();
    final resolver = attestationResolver;
    if (resolver == null) {
      // No attestation source: claims are unverified → zero weight.
      _enqueue(requestId, peerId, 0, 0, task, completer);
    } else {
      resolver(peerId).then((att) {
        _enqueue(
          requestId,
          peerId,
          att.honorScore.clamp(0, maxAttestedHonor),
          att.porCount.clamp(0, maxAttestedPoR),
          task,
          completer,
        );
      }, onError: (Object e, StackTrace st) {
        // Attestation failure fails closed: zero credentials.
        _enqueue(requestId, peerId, 0, 0, task, completer);
      });
    }
    return completer.future;
  }

  void _enqueue<T>(
    String requestId,
    String peerId,
    int honorScore,
    int porCount,
    Future<T> Function() task,
    Completer<T> completer,
  ) {
    _requestQueue.add(BandwidthRequest<T>(
      requestId: requestId,
      peerId: peerId,
      baseHonorScore: honorScore,
      verifiedPoRCount: porCount,
      requestTime: DateTime.now(),
      task: task,
      completer: completer,
    ));
    _processQueue();
  }

  void _processQueue() {
    if (_inFlightCount >= maxConcurrent || _requestQueue.isEmpty) return;

    final now = DateTime.now();
    _requestQueue.sort((a, b) {
      final pA = a.computeEffectivePriority(now);
      final pB = b.computeEffectivePriority(now);
      final cmp = pB.compareTo(pA); // Descending priority
      // (round-3 red finding) deterministic FIFO tiebreak - equal
      // priorities resolve by arrival order so a peer cannot win by
      // exploiting sort instability on forged-equal credentials.
      return cmp != 0 ? cmp : a.requestTime.compareTo(b.requestTime);
    });

    final next = _requestQueue.removeAt(0);
    _inFlightCount++;

    // (campaign-2 hardening) a task that throws SYNCHRONOUSLY used to
    // escape _processQueue with _inFlightCount already incremented -
    // the slot leaked forever (the queue would deadlock once all
    // permits leaked) and the completer never resolved, hanging the
    // caller. Invoke inside try/catch so a sync throw completes the
    // future with the error and releases the permit like an async one.
    // (_requestQueue holds raw BandwidthRequest objects, so task()
    // yields Future<dynamic> here.)
    Future<dynamic> taskFuture;
    try {
      taskFuture = next.task();
    } catch (err, st) {
      _inFlightCount--;
      next.completer.completeError(err, st);
      _processQueue();
      return;
    }
    taskFuture.then((result) {
      next.completer.complete(result);
    }).catchError((err, st) {
      next.completer.completeError(err, st);
    }).whenComplete(() {
      _inFlightCount--;
      _processQueue();
    });
  }
}
