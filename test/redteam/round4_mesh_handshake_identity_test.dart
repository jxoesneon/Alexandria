// RED TEAM PoC — Round-4: the round-3 ALX-MESH/1 handshake added a
// nonce + echoed peerId to the probe, and the docstring claims the ACK
// "binds it to the claimed identity (no look-alike endpoint standing in
// for another peer)". But the peerId in the ACK is SELF-ASSERTED by the
// answering endpoint — there is no signature over the nonce. Any TCP
// listener that speaks the protocol can claim ANY peerId: the caller
// already told it which peerId it expects (it's in the multiaddr), so
// the endpoint just echoes it back. The handshake proves liveness, not
// identity — a hostile endpoint still mints isReachable for a victim's
// peerId and absorbs that peer's payload traffic.
//
// Second finding (availability): connectToPeer demotes an already-PROVEN
// peer to isPending/isReachable=false BEFORE the probe, and a failed
// re-dial leaves it unreachable — even when the stored address (the one
// that was proven) is untouched. An attacker who can trigger a re-dial
// with a dead multiaddr revokes a proven peer's routing.
//
// Asserts the SECURE expectations: reachability must bind peerId
// cryptographically (sign the nonce), and a failed probe of a NEW
// address must not destroy the PROVEN state of the old one.
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/mesh_transport_service.dart';

void main() {
  test(
      'an arbitrary endpoint can claim a victim peerId and become '
      'reachable (no cryptographic binding)', () async {
    // Stand up a hostile endpoint that answers ANY HELLO with an ACK
    // claiming the VICTIM's peerId — exactly what serveHandshake does
    // when configured to lie.
    const victimPeerId = 'QmVictimNodeThatDoesNotLiveHere';
    final server = await ServerSocket.bind('127.0.0.1', 0);
    addTearDown(server.close);
    server.listen((socket) {
      MeshTransportService.serveHandshake(socket, victimPeerId);
    });

    final svc = MeshTransportService();
    final ok = await svc
        .connectToPeer('/ip4/127.0.0.1/tcp/${server.port}/p2p/$victimPeerId');

    expect(ok, isFalse,
        reason: 'connectToPeer returned TRUE for an endpoint that holds no '
            'credentials for $victimPeerId — the ACK\'s peerId is '
            'self-asserted plaintext, so the "binding" verifies only '
            'that the endpoint can echo the peerId it was dialed with. '
            'The peer is now isReachable and sendPayload routes to it.');

    final peer = svc.peers.firstWhere((p) => p.peerId == victimPeerId);
    expect(peer.isReachable, isFalse);
  });

  test('a failed re-dial must not revoke a proven peer\'s reachability',
      () async {
    // Probe succeeds for the "good" address only.
    final svc = MeshTransportService(
      handshakeProbe: (addr) async => addr.contains('good.example'),
    );

    final goodAddr = '/dns4/good.example/tcp/4001/p2p/QmProvenPeer';
    expect(await svc.connectToPeer(goodAddr), isTrue);
    expect(svc.activePeers.any((p) => p.peerId == 'QmProvenPeer'), isTrue);

    // Attacker initiates a dial of the SAME peerId via a dead address —
    // e.g. a poisoned multiaddr announcement. The probe fails...
    final badAddr = '/dns4/dead.example/tcp/4001/p2p/QmProvenPeer';
    expect(await svc.connectToPeer(badAddr), isFalse);

    // ...but the peer keeps its ORIGINAL proven address record — the
    // failure of a new endpoint says nothing about the old one.
    final peer = svc.peers.firstWhere((p) => p.peerId == 'QmProvenPeer');
    expect(peer.isReachable, isTrue,
        reason: 'a failed handshake to a DIFFERENT address demoted the '
            'proven peer (isReachable=${peer.isReachable}, '
            'address=${peer.address}) — connectToPeer overwrites '
            'reachability unconditionally on probe failure. Any caller '
            'able to submit a multiaddr can strip routing from an '
            'honest peer (routing DoS).');
    expect(await svc.sendPayload('QmProvenPeer', Uint8List(3)), isTrue);
  });
}
