// RED TEAM PoC — Round-3: the round-2 "handshake probe" in
// MeshTransportService still admits unproven peers into the reachable
// set through TWO gaps.
//
// GAP 1 — the probe proves a TCP LISTENER, not a peer.
// _defaultHandshakeProbe (lib/services/mesh_transport_service.dart:105)
// is a bare Socket.connect: it completes the moment ANY TCP service
// accepts the connection — an SSH daemon, a web server, a tarpit. No
// protocol handshake, no /p2p/ peer-id proof, no key exchange. The
// claimed peerId in the multiaddr is never bound to the endpoint, so
// an attacker dials her own open port and the service records HER
// chosen peerId (e.g. a victim's well-known id) as reachable —
// unlocking activePeers, selectBestTransport and sendPayload for a
// phantom.
//
// GAP 2 — registerPeer bypasses the probe entirely.
// `MeshPeer.isReachable` defaults to TRUE and registerPeer()
// (line 184) trusts the caller's flag with no proof requirement. The
// peer-discovery UI (lib/ui/network/peer_discovery_screen.dart:90-101)
// registers a raw user/multiaddr-supplied MeshPeer() — isReachable
// defaults to true → an unproven address enters activePeers without a
// single packet.
//
// Asserts the SECURE expectation: a peer may only appear in
// activePeers / pass the sendPayload gate after a handshake that
// proves the remote end speaks the mesh protocol AND controls the
// claimed peerId. Failure marks both bypasses live.
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/mesh_transport_service.dart';

void main() {
  test('a bare TCP listener must NOT satisfy the peer handshake',
      () async {
    // A listening socket that accepts and speaks NOTHING — no libp2p,
    // no Alexandria protocol, just a TCP accept. If this counts as a
    // handshake, any open port on the internet can impersonate a peer.
    final server = await ServerSocket.bind('127.0.0.1', 0);
    final sub = server.listen((s) => s.destroy());
    addTearDown(() async {
      await sub.cancel();
      await server.close();
    });

    final svc = MeshTransportService(); // production default probe
    final ok = await svc.connectToPeer(
        '/ip4/127.0.0.1/tcp/${server.port}/p2p/QmSpoofedVictimIdentity');

    expect(ok, isFalse,
        reason:
            'connectToPeer returned true for a socket that never '
            'answered a single protocol byte — the "handshake" is a '
            'bare TCP connect, so any listener satisfies it and the '
            'claimed /p2p/ id is unbound. A peer must only become '
            'reachable after a protocol-level handshake proving the '
            'claimed peerId.');
    expect(svc.activePeers.any((p) => p.peerId == 'QmSpoofedVictimIdentity'),
        isFalse,
        reason: 'unproven endpoint entered activePeers');
  });

  test('registerPeer must not admit an unproven peer into activePeers',
      () async {
    final svc = MeshTransportService();
    // Mirrors lib/ui/network/peer_discovery_screen.dart:94-101 — a
    // raw multiaddr off the wire/UI becomes a MeshPeer whose
    // isReachable defaults to true: no probe ever runs.
    svc.registerPeer(MeshPeer(
      peerId: 'QmNeverHandshaken',
      address: '/ip4/203.0.113.9/tcp/4001/p2p/QmNeverHandshaken',
      tier: TransportTier.webrtcDirect,
      latencyMs: 0,
    ));

    expect(
        svc.activePeers.any((p) => p.peerId == 'QmNeverHandshaken'),
        isFalse,
        reason:
            'registerPeer admitted a peer that was never probed — '
            'MeshPeer.isReachable defaults to true, so the round-2 '
            'handshake gate is trivially bypassed on this path.');
    expect(
        await svc.sendPayload(
            'QmNeverHandshaken', Uint8List.fromList([1, 2, 3])),
        isFalse,
        reason: 'payload "sent" to an unproven peer');
    expect(svc.selectBestTransport('QmNeverHandshaken'), isNull,
        reason: 'transport selected for an unproven peer');
  });
}
