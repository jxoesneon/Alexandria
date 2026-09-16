// MeshBountyTransport tests: the production BountyTransport binding
// over the mesh channel layer. The two mesh services below are wired
// with synthetic handshake tickets sharing one channel key and
// frameTransport shims that deliver each other's frames — so the full
// real frame path (seq ‖ payload ‖ HMAC over the handshake-derived
// channel key, MAC verify + replay guard on receive) carries the
// envelopes end to end.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/agent/beacon_models.dart';
import 'package:alexandria/services/agent/escrow_attestation.dart';
import 'package:alexandria/services/agent/mesh_bounty_transport.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/mesh_transport_service.dart';

Future<SimpleKeyPair> _newKey() => Ed25519().newKeyPair();

Future<String> _pubHex(SimpleKeyPair kp) async =>
    bytesToHex((await kp.extractPublicKey()).bytes);

/// A field-identical handshake ticket for both ends of ONE session:
/// the channel key is `HKDF(salt=sharedSecret, ikm=transcriptBytes)`
/// and the transcript embeds peerId+multiaddr+nonce+ephemerals — so
/// both probes must return byte-identical ticket FIELDS for the two
/// channels to share one key. [responderSide] is the only allowed
/// difference: it selects which direction tag each side MACs with
/// (dialer sends tag 0 / receives tag 1; responder the reverse), and
/// is not part of the transcript. The ticket's inner peerId/multiaddr
/// are transcript material only — the channel is installed under the
/// DIALED multiaddr's /p2p/ component.
MeshHandshakeTicket _sharedTicket({bool responderSide = false}) =>
    MeshHandshakeTicket(
      peerId: 'session-peer',
      multiaddr: '/ip4/127.0.0.1/tcp/4999/p2p/session-peer',
      nonce: 'aabbccddeeff0011',
      responderSignature: Uint8List(0),
      dialerEphemeral: 'dGVzdGRpYWxlcmVwaGVtZXJhbGtleWJ5dGVzMDAw',
      responderEphemeral: 'dGVzdHJlc3BvbmRlcmVwaGVtZXJhbGtleWJ5dGUw',
      sharedSecret: Uint8List.fromList(List<int>.generate(32, (i) => i)),
      transcriptBound: true,
      responderSide: responderSide,
    );

/// Two mesh services cross-wired into ONE session: A is the dialer
/// (responderSide: false), B is the responder (responderSide: true) —
/// the direction-bound MACs then pair exactly as they would over a
/// real handshake socket. Each side's frameTransport delivers its
/// outbound frames to the other service's receiveFrame under the
/// sender's peerId.
class _MeshPair {
  late final MeshTransportService a;
  late final MeshTransportService b;
  final aId = 'peerA';
  final bId = 'peerB';
  final aAddr = '/ip4/127.0.0.1/tcp/4001/p2p/peerA';
  final bAddr = '/ip4/127.0.0.1/tcp/4002/p2p/peerB';

  Future<void> connect() async {
    a = MeshTransportService(
      sessionProbe: (addr) async => _sharedTicket(responderSide: false),
      frameTransport: (peerId, frame) => b.receiveFrame(aId, frame),
    );
    b = MeshTransportService(
      sessionProbe: (addr) async => _sharedTicket(responderSide: true),
      frameTransport: (peerId, frame) => a.receiveFrame(bId, frame),
    );
    expect(await a.connectToPeer(bAddr), isTrue);
    expect(await b.connectToPeer(aAddr), isTrue);
    expect(a.hasChannelBinding(bId), isTrue);
    expect(b.hasChannelBinding(aId), isTrue);
  }

  void dispose() {
    a.dispose();
    b.dispose();
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  test('envelopes flow over the MAC\'d mesh channel: publish → parse → '
      'ingest', () async {
    final pair = _MeshPair();
    await pair.connect();
    addTearDown(pair.dispose);

    final transportA = MeshBountyTransport(pair.a);
    final transportB = MeshBountyTransport(pair.b);

    final received = <BeaconEnvelope>[];
    final sub = transportB.envelopes.listen(received.add);
    addTearDown(sub.cancel);

    final kp = await _newKey();
    final env = await BeaconEnvelope.create(
        kind: 'moltbook_post', keyPair: kp, payload: {'hello': 'mesh'});
    await transportA.publish(env);
    expect(transportA.lastFanout, 1);
    await _settle();

    expect(received, hasLength(1));
    expect(received.single.kind, 'moltbook_post');
    expect(await received.single.verify(), isTrue);
    expect(received.single.pubkey, await _pubHex(kp));
  });

  test('publish with no proven peers completes best-effort with zero '
      'fanout', () async {
    final mesh = MeshTransportService(
        sessionProbe: (_) async => null, frameTransport: (_, __) async => false);
    final transport = MeshBountyTransport(mesh);
    final env = await BeaconEnvelope.create(
        kind: 'moltbook_post', keyPair: await _newKey(), payload: {});
    await transport.publish(env); // must not throw
    expect(transport.lastFanout, 0);
    mesh.dispose();
  });

  test('malformed inbound payloads are dropped before the envelope '
      'stream', () async {
    final pair = _MeshPair();
    await pair.connect();
    addTearDown(pair.dispose);

    final transportB = MeshBountyTransport(pair.b);
    final received = <BeaconEnvelope>[];
    final sub = transportB.envelopes.listen(received.add);
    addTearDown(sub.cancel);

    // Hand-craft a frame carrying non-envelope bytes IN THE DIALER'S
    // direction (tag 0 — what A→B traffic MACs under; B's responder-
    // side channel accepts exactly that direction). The frame MAC-
    // verifies but fails envelope parse and must be dropped.
    final key = MeshTransportService.deriveSessionKey(_sharedTicket());
    final junk = MeshTransportService.encodeFrame(
        key, 0, Uint8List.fromList(utf8.encode('not a beacon envelope')),
        0);
    expect(await pair.b.receiveFrame(pair.aId, junk), isTrue);
    await _settle();
    expect(received, isEmpty);
  });

  test('end-to-end over real mesh channels: bounty announce → verified '
      'claim → poster-side settlement evidence', () async {
    final pair = _MeshPair();
    await pair.connect();
    addTearDown(pair.dispose);

    // Poster node. The poster key is fixed UP FRONT — the funded
    // re-announcement below must carry the SAME originAgentId as the
    // first announcement (the dedup-upgrade gate refuses an origin
    // change, so rotating keys mid-test would strand the upgrade).
    final csA = CreditService(initialBalance: 100.0);
    final svcA = MoltbookService(
        creditService: csA, bountyTransport: MeshBountyTransport(pair.a));
    addTearDown(svcA.dispose);
    final posterKp = await _newKey();
    await svcA.setKeyPair(posterKp);

    // Claimant node trusts the attestor and rides the mesh transport.
    final attestor = await _newKey();
    final csB = CreditService(initialBalance: 50.0);
    final svcB = MoltbookService(
      creditService: csB,
      bountyTransport: MeshBountyTransport(pair.b),
      trustedAttestorPubkeys: {await _pubHex(attestor)},
    );
    addTearDown(svcB.dispose);
    await svcB.setKeyPair(await _newKey());

    // 1. Announce over the mesh — lands attributed but unfunded.
    final posted = await svcA.postPreservationBounty(
        cid: 'bafk_mesh', title: 'mesh bounty', offeredCredits: 20.0,
        force: true);
    await _settle();
    expect(svcB.isOriginVerified(posted.id), isTrue);
    var stored =
        svcB.activeBounties.firstWhere((b) => b.id == posted.id);
    expect(stored.funded, isFalse);

    // 2. Attestor-signed funding upgrade (envelope-carried attestation).
    final exp =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
    final attSig = await Ed25519().sign(
        EscrowAttestation.signingPreimage(
            bountyId: posted.id,
            cid: posted.cid,
            amountMilli: 20000,
            expiresAt: exp),
        keyPair: attestor);
    // Re-announce under the poster's own key so the origin binding
    // holds and the dedup-upgrade sees the same poster identity.
    final fundedEnv = await BeaconEnvelope.create(
      kind: 'preservation_bounty',
      keyPair: posterKp,
      payload: {
        ...posted.toJson(),
        'origin_agent_id': svcA.agentId,
        'escrow_attestation': {
          'attestor_pubkey': await _pubHex(attestor),
          'bounty_id': posted.id,
          'cid': posted.cid,
          'amount_milli': 20000,
          'expires_at': exp,
          'sig': base64Encode(attSig.bytes),
        },
      },
    );
    await svcB.ingestBountyEnvelope(fundedEnv);
    stored = svcB.activeBounties.firstWhere((b) => b.id == posted.id);
    expect(stored.funded, isTrue);

    // 3. Claim wins → the signed claim event rides the mesh back to
    //    the poster.
    expect(await svcB.claimBounty(posted.id), isTrue);
    expect(csB.balance, 70.0);
    await _settle();

    expect(svcA.isRemotelyClaimed(posted.id), isTrue);
    final claim = svcA.remoteClaimFor(posted.id);
    expect(claim, isNotNull);
    expect(claim!.claimantAgentId, svcB.agentId);
    expect(await svcA.cancelBounty(posted.id), isFalse);
    expect(csA.balance, 80.0); // escrow locked, never refunded
  });
}
