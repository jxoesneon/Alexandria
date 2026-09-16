// RED TEAM PoC — MeshTransportService.connectToPeer marks ANY
// "/p2p/<id>" address reachable without a network exchange or
// cryptographic proof.
//
// lib/services/mesh_transport_service.dart:210-243 performs the
// "handshake" by calling _attemptSend on an EMPTY payload — and
// _attemptSend (193-203) only checks local map state plus an enabled
// transport tier. There is no socket, no ping, no peer-signature
// verification. A Sybil can therefore:
//   * register thousands of phantom peers, all instantly "reachable",
//   * get attacker multiaddrs listed in activePeers / routed by
//     selectBestTransport, inflating peer-count metrics that feed
//     credit rewards and preservation health checks.
//
// Asserts the SECURE expectation: reachability must require evidence.
// Failure marks a live phantom-peer/Sybil amplification.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/mesh_transport_service.dart';

void main() {
  test('unverifiable address must not become a reachable peer', () async {
    final mesh = MeshTransportService(); // no bootstrap — empty swarm
    addTearDown(mesh.dispose);

    // Attacker-controlled garbage multiaddr. Nothing is listening at
    // 192.0.2.1 (TEST-NET-1) — no real handshake could ever succeed.
    final ok = await mesh.connectToPeer(
        '/ip4/192.0.2.1/tcp/9/p2p/QmPhantomSybilPeer0001');

    expect(ok, isFalse,
        reason:
            'connectToPeer returned true for an unreachable, '
            'unauthenticated address — the "handshake" is a local state '
            'transition with zero network I/O');

    final peers =
        mesh.activePeers.where((p) => p.peerId == 'QmPhantomSybilPeer0001');
    expect(peers, isEmpty,
        reason:
            'phantom peer was marked isReachable and now appears in '
            'activePeers — Sybil inflation of the swarm view');
  });

  test('phantom reachability must not unlock payload routing', () async {
    final mesh = MeshTransportService();
    addTearDown(mesh.dispose);

    await mesh.connectToPeer('/p2p/QmGhostPeer9999');
    final tier = mesh.selectBestTransport('QmGhostPeer9999');

    expect(tier, isNull,
        reason:
            'a peer that never exchanged a byte got a transport route; '
            'credit/peer-count consumers downstream read this as a '
            'live connection');

    final sent =
        await mesh.sendPayload('QmGhostPeer9999', Uint8List.fromList([1, 2]));
    expect(sent, isFalse,
        reason: 'payload "sent" to a peer that was never proven');
  });

  test('bootstrap candidates must stay unproven until a real handshake',
      () async {
    final mesh = MeshTransportService(bootstrap: true);
    addTearDown(mesh.dispose);

    // Bootstrap peers are pending; connectToPeer on one of them must
    // not succeed without an actual endpoint — the stub _attemptSend
    // always returns true when a tier is enabled.
    final ok = await mesh.connectToPeer(
        '/dns4/node1.alexandria.network/tcp/4001/p2p/QmBootstrapNode1AlexandriaAlpha');

    expect(ok, isFalse,
        reason:
            'bootstrap handshake "succeeded" against a peer no test '
            'network could reach — reachability claims are fabricated');
  });
}
