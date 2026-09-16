// RED TEAM PoC — HonorBandwidthService.enqueueRequest trusts
// CALLER-SUPPLIED `baseHonorScore` and `verifiedPoRCount` verbatim
// (lib/services/honor_bandwidth_service.dart:45-76). The priority
// formula ((honor*0.5)+(PoR*2.0)+(age*0.2)) sorts the queue on those
// self-declared values — there is no lookup against the ledger, no
// signature, no clamp. A peer that declares honor=INT_MAX and
// PoR=INT_MAX jumps ahead of every honest requester, permanently
// starving them (the 0.2/s anti-starvation term can never catch up).
//
// Asserts the SECURE expectation: a request that claims impossible
// honor credentials must not outrank honest queued work — the score
// must be attested (or at least bound-clamped/peer-derived), not
// caller-supplied.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/honor_bandwidth_service.dart';

void main() {
  test(
      'self-declared honor score must not let an attacker jump the '
      'queue', () async {
    final svc = HonorBandwidthService(maxConcurrent: 1);
    final order = <String>[];

    // Occupy the single slot with a controllable blocker.
    final gate = Completer<void>();
    unawaited(svc.enqueueRequest<String>(
      requestId: 'blocker',
      peerId: 'peer0',
      baseHonorScore: 100,
      verifiedPoRCount: 10,
      task: () async {
        await gate.future;
        order.add('blocker');
        return 'b';
      },
    ));

    // Honest low-reputation request queued first.
    unawaited(svc.enqueueRequest<String>(
      requestId: 'honest',
      peerId: 'peer-honest',
      baseHonorScore: 10,
      verifiedPoRCount: 2,
      task: () async {
        order.add('honest');
        return 'h';
      },
    ));

    // Attacker queues SECOND but claims absurd credentials.
    unawaited(svc.enqueueRequest<String>(
      requestId: 'attacker',
      peerId: 'peer-attacker',
      baseHonorScore: 0x7FFFFFFF, // self-declared, never verified
      verifiedPoRCount: 0x7FFFFFFF,
      task: () async {
        order.add('attacker');
        return 'a';
      },
    ));

    gate.complete();
    // Let the queue drain.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(order.indexOf('attacker') > order.indexOf('honest'), isTrue,
        reason: 'the attacker\'s self-declared honor/PoR outranked the '
            'honest request (order=$order) — computeEffectivePriority '
            'sorts on caller-supplied credentials, so any peer can '
            'claim INT_MAX and starve the queue. Scores must be '
            'attested/derived, not asserted.');
  });
}
