// RED TEAM PoC — Round-6: MeshTransportService.connectToPeer writes a
// STALE peer snapshot back after the async handshake probe, re-creating
// — as REACHABLE — a peer that was unregistered or disconnected while
// the probe was in flight.
//
//   lib/services/mesh_transport_service.dart:395-444
//     peer = _peers[peerId];                 // snapshot at T0
//     _peers[peerId] = peer.copyWith(isPending: true);
//     ok = await _handshakeProbe(multiaddr);  // ← async gap
//     if (ok) {
//       _peers[peerId] = peer.copyWith(…, isReachable: true);
//       //            ^^^^ stale snapshot, unconditional reinsert —
//       //                 no re-check that the peer still exists or
//       //                 that a concurrent unregister/disconnect ran.
//
// Consequence: an endpoint that answers the handshake slowly (or an
// operator racing a dial) defeats peer revocation — `unregisterPeer`
// and `disconnectPeer` are silently undone and the resurrected record
// is marked `isReachable`, which is the ONLY gate on sendPayload /
// selectBestTransport. A removed peer regains a live route.
//
// Asserts the SECURE expectation: once unregistered/disconnected, a
// completed probe must not resurrect or re-mark the peer.
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/mesh_transport_service.dart';

const _addr = '/ip4/127.0.0.1/tcp/4001/p2p/victim-peer';
const _peerId = 'victim-peer';

void main() {
  test('a probe completing after unregisterPeer resurrects the peer '
      'as reachable', () async {
    final probe = Completer<bool>();
    final svc = MeshTransportService(handshakeProbe: (_) => probe.future);

    final dial = svc.connectToPeer(_addr);
    await Future<void>.delayed(Duration.zero); // let the dial register

    // Operator revokes the peer while the handshake is outstanding.
    svc.unregisterPeer(_peerId);
    expect(svc.peers.any((p) => p.peerId == _peerId), isFalse);

    probe.complete(true); // endpoint finally answers
    expect(await dial, isTrue);

    final resurrected =
        svc.peers.where((p) => p.peerId == _peerId).toList();
    expect(resurrected, isEmpty,
        reason:
            'connectToPeer wrote back its pre-probe snapshot after an '
            'unregisterPeer — the removed peer is present again AND '
            'marked isReachable, so sendPayload/selectBestTransport '
            'route to a peer the operator revoked.');
    expect(await svc.sendPayload(_peerId, Uint8List(4)), isFalse,
        reason:
            'a resurrected peer must not be dispatchable, but the '
            'stale-snapshot write marked it isReachable.');
  });

  test('a probe completing after disconnectPeer re-marks the peer '
      'reachable', () async {
    final probe = Completer<bool>();
    final svc = MeshTransportService(handshakeProbe: (_) => probe.future);

    final dial = svc.connectToPeer(_addr);
    await Future<void>.delayed(Duration.zero);

    await svc.disconnectPeer(_peerId);
    probe.complete(true);
    await dial;

    final peer = svc.peers.firstWhere((p) => p.peerId == _peerId);
    expect(peer.isReachable, isFalse,
        reason:
            'disconnectPeer during an in-flight probe is undone by the '
            'stale write-back — the peer is reachable again without any '
            'new handshake, and sendPayload will dispatch to it.');
  });

  test('a probe completing after registerPeer clobbers the fresh record',
      () async {
    final probe = Completer<bool>();
    final svc = MeshTransportService(handshakeProbe: (_) => probe.future);

    final dial = svc.connectToPeer(_addr);
    await Future<void>.delayed(Duration.zero);

    // A fresher registration lands mid-probe (new address, BLE tier).
    const newAddr = '/ip4/10.0.0.9/tcp/5000/p2p/victim-peer';
    svc.registerPeer(MeshPeer(
      peerId: _peerId,
      address: newAddr,
      tier: TransportTier.bleProximity,
      latencyMs: 7,
    ));

    probe.complete(true);
    await dial;

    final peer = svc.peers.firstWhere((p) => p.peerId == _peerId);
    // The T0 snapshot had webrtcDirect/address=_addr; the write-back
    // stomps the registered record's tier.
    expect(peer.tier, equals(TransportTier.bleProximity),
        reason:
            'connectToPeer’s stale-snapshot write clobbered the tier of '
            'a peer record that was re-registered mid-probe.');
  });
}
