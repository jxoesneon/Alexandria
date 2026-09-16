// Tests for the round-5 residual closure: post-handshake channel
// binding in MeshTransportService. The handshake (round-3/4) proved
// identity but derived no key material — a relay passing the HELLO/ACK
// could splice later frames. Now every frame is
// seq ‖ payload ‖ HMAC-SHA256(channelKey, …) where the channel key is
// HKDF-SHA256(salt = ephemeral X25519 shared secret, ikm = handshake
// transcript).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/mesh_transport_service.dart';

/// Builds a real Ed25519 responder identity + signer, and the
/// self-certifying peerId the multiaddr carries.
Future<({String peerId, Future<Uint8List> Function(Uint8List) signer})>
    _responderIdentity() async {
  final keyPair =
      await Ed25519().newKeyPairFromSeed(List<int>.generate(32, (i) => i + 7));
  final pub = (await keyPair.extractPublicKey()).bytes;
  final identity = AlexandriaIdentity(
    publicKey: Uint8List.fromList(pub),
    privateKey: Uint8List(32),
    createdAt: DateTime(2024),
  );
  return (
    peerId: identity.publicKeyBase58,
    signer: (payload) async => Uint8List.fromList(
        (await Ed25519().sign(payload, keyPair: keyPair)).bytes),
  );
}

/// A fixed ticket both "sides" of a test can share through the
/// sessionProbe seam.
MeshHandshakeTicket _ticket({
  String peerId = 'peer-A',
  String multiaddr = '/ip4/1.2.3.4/tcp/4001/p2p/peer-A',
  String nonce = '0123456789abcdef',
  int secretByte = 9,
}) =>
    MeshHandshakeTicket(
      peerId: peerId,
      multiaddr: multiaddr,
      nonce: nonce,
      responderSignature: Uint8List.fromList(List<int>.generate(64, (i) => i)),
      dialerEphemeral: 'ZGlhbGVyLWVwaA',
      responderEphemeral: 'cmVzcG9uZGVyLWVwaA',
      sharedSecret: Uint8List.fromList(List<int>.filled(32, secretByte)),
    );

void main() {
  group('mesh channel binding (round-5 residual closure)', () {
    test('real socket handshake binds the same key on both ends', () async {
      final id = await _responderIdentity();
      MeshHandshakeTicket? responderTicket;
      final server = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(server.close);
      server.listen((socket) {
        MeshTransportService.serveHandshake(socket, id.peerId,
            identitySigner: id.signer,
            onSessionBound: (t) => responderTicket = t);
      });

      // Dialer captures its outbound frames; the handshake itself uses
      // the production default probe over the real socket.
      final sent = <Uint8List>[];
      final dialer = MeshTransportService(
        frameTransport: (peerId, frame) async {
          sent.add(frame);
          return true;
        },
      );
      addTearDown(dialer.dispose);

      final multiaddr = '/ip4/127.0.0.1/tcp/${server.port}/p2p/${id.peerId}';
      expect(await dialer.connectToPeer(multiaddr), isTrue);
      expect(dialer.hasChannelBinding(id.peerId), isTrue);
      expect(responderTicket, isNotNull,
          reason: 'responder must observe the session being bound');

      final responderKey =
          MeshTransportService.deriveSessionKey(responderTicket!);

      // Responder → dialer direction: a frame MAC'd under the
      // responder-derived key must verify on the dialer's channel —
      // proving both ends derived the same secret.
      final payload = Uint8List.fromList(utf8.encode('hello dialer'));
      final inbound =
          MeshTransportService.encodeFrame(responderKey, 0, payload);
      expect(await dialer.receiveFrame(id.peerId, inbound), isTrue);

      // Dialer → responder direction: the frame the dialer dispatched
      // must verify under the responder's key. Stand up the responder
      // side of the channel by injecting its ticket into a second
      // service instance.
      final responder = MeshTransportService(
        sessionProbe: (_) async => responderTicket,
      );
      addTearDown(responder.dispose);
      expect(
          await responder.connectToPeer(
              '/ip4/127.0.0.1/tcp/${server.port}/p2p/${id.peerId}'),
          isTrue);

      final outboundPayload = Uint8List.fromList(utf8.encode('ping'));
      expect(await dialer.sendPayload(id.peerId, outboundPayload), isTrue);
      expect(sent, hasLength(1));
      // seq(8) ‖ payload ‖ mac(32)
      expect(sent.first.length, equals(8 + outboundPayload.length + 32));
      expect(await responder.receiveFrame(id.peerId, sent.first), isTrue);
    });

    test(
        'peers without a completed handshake cannot send or receive '
        'frames', () async {
      final svc = MeshTransportService();
      addTearDown(svc.dispose);
      svc.registerPeer(MeshPeer(
        peerId: 'unproven',
        address: '/ip4/1.2.3.4/tcp/1/p2p/unproven',
        tier: TransportTier.lanMdns,
        latencyMs: 0,
      ));
      expect(svc.hasChannelBinding('unproven'), isFalse);
      expect(await svc.sendPayload('unproven', Uint8List(4)), isFalse);
      expect(await svc.receiveFrame('unproven', Uint8List(64)), isFalse);
    });

    test('frames carry a sequence-verified MAC — tampering is rejected',
        () async {
      final ticket = _ticket();
      final received = <Uint8List>[];
      final svc = MeshTransportService(
        sessionProbe: (_) async => ticket,
        frameTransport: (_, __) async => true,
      );
      addTearDown(svc.dispose);
      svc.onPayloadReceived.listen(received.add);
      expect(await svc.connectToPeer(ticket.multiaddr), isTrue);

      final key = MeshTransportService.deriveSessionKey(ticket);
      final payload = Uint8List.fromList(utf8.encode('frame zero'));
      final frame = MeshTransportService.encodeFrame(key, 0, payload);
      expect(await svc.receiveFrame('peer-A', frame), isTrue);
      expect(received.single, equals(payload));

      // Bit-flip in the payload region.
      final tampered = Uint8List.fromList(frame)..[10] ^= 0x01;
      expect(await svc.receiveFrame('peer-A', tampered), isFalse);
      // Bit-flip in the MAC region.
      final badMac = Uint8List.fromList(frame)..[frame.length - 1] ^= 0x01;
      expect(await svc.receiveFrame('peer-A', badMac), isFalse);
      // Truncated frame.
      expect(
          await svc.receiveFrame('peer-A', frame.sublist(0, frame.length - 10)),
          isFalse);
      expect(received, hasLength(1),
          reason: 'forged frames must not reach onPayloadReceived');
    });

    test('replayed and out-of-order frames are rejected', () async {
      final ticket = _ticket();
      final svc = MeshTransportService(
        sessionProbe: (_) async => ticket,
        frameTransport: (_, __) async => true,
      );
      addTearDown(svc.dispose);
      await svc.connectToPeer(ticket.multiaddr);
      final key = MeshTransportService.deriveSessionKey(ticket);

      final f0 = MeshTransportService.encodeFrame(key, 0, Uint8List(4));
      final f5 = MeshTransportService.encodeFrame(key, 5, Uint8List(4));
      expect(await svc.receiveFrame('peer-A', f5), isTrue);
      // Older seq after a newer one — replay.
      expect(await svc.receiveFrame('peer-A', f0), isFalse);
      // Exact replay of the accepted frame.
      expect(await svc.receiveFrame('peer-A', f5), isFalse);
      // Gap ahead is fine — seq only needs to be ahead.
      expect(
          await svc.receiveFrame(
              'peer-A', MeshTransportService.encodeFrame(key, 9, Uint8List(4))),
          isTrue);
    });

    test(
        'a forward-only relay cannot forge frames — the transcript '
        'alone does not yield the channel key', () async {
      final ticket = _ticket();
      final sent = <Uint8List>[];
      final svc = MeshTransportService(
        sessionProbe: (_) async => ticket,
        frameTransport: (_, frame) async {
          sent.add(frame);
          return true;
        },
      );
      addTearDown(svc.dispose);
      await svc.connectToPeer(ticket.multiaddr);
      await svc.sendPayload('peer-A', Uint8List.fromList([1, 2, 3]));

      // Attacker holds the full public transcript (HELLO+ACK lines)
      // but NOT the ephemeral DH secret. A transcript-only derivation
      // — what a transcript-binding-only design would produce — must
      // not verify.
      final eavesdropperKey =
          MeshTransportService.deriveSessionKey(MeshHandshakeTicket(
        peerId: ticket.peerId,
        multiaddr: ticket.multiaddr,
        nonce: ticket.nonce,
        responderSignature: ticket.responderSignature,
        dialerEphemeral: ticket.dialerEphemeral,
        responderEphemeral: ticket.responderEphemeral,
        sharedSecret: Uint8List(32), // zeroed — no DH knowledge
      ));
      final forged = MeshTransportService.encodeFrame(
          eavesdropperKey, 99, Uint8List.fromList([9, 9, 9]));
      expect(await svc.receiveFrame('peer-A', forged), isFalse,
          reason: 'a relay that observed the handshake must not be able to '
              'MAC frames — the key needs the ephemeral DH secret');
    });

    test(
        'channel is dropped on disconnect, unregister, and address '
        're-registration', () async {
      final ticket = _ticket();
      final svc = MeshTransportService(
        sessionProbe: (_) async => ticket,
        frameTransport: (_, __) async => true,
      );
      addTearDown(svc.dispose);
      await svc.connectToPeer(ticket.multiaddr);
      expect(svc.hasChannelBinding('peer-A'), isTrue);

      final key = MeshTransportService.deriveSessionKey(ticket);
      final frame = MeshTransportService.encodeFrame(key, 0, Uint8List(3));

      await svc.disconnectPeer('peer-A');
      expect(svc.hasChannelBinding('peer-A'), isFalse);
      expect(await svc.receiveFrame('peer-A', frame), isFalse);
      expect(await svc.sendPayload('peer-A', Uint8List(3)), isFalse);

      // Re-handshake restores a channel.
      await svc.connectToPeer(ticket.multiaddr);
      expect(svc.hasChannelBinding('peer-A'), isTrue);
      expect(await svc.receiveFrame('peer-A', frame), isTrue);

      // unregister drops everything.
      svc.unregisterPeer('peer-A');
      expect(svc.hasChannelBinding('peer-A'), isFalse);

      // Address change on an existing proven record invalidates the
      // binding (the channel is transcript-bound to the old multiaddr).
      final svc2 = MeshTransportService(
        sessionProbe: (_) async => ticket,
        frameTransport: (_, __) async => true,
      );
      addTearDown(svc2.dispose);
      await svc2.connectToPeer(ticket.multiaddr);
      expect(svc2.hasChannelBinding('peer-A'), isTrue);
      svc2.registerPeer(MeshPeer(
        peerId: 'peer-A',
        address: '/ip4/9.9.9.9/tcp/1/p2p/peer-A', // different address
        tier: TransportTier.lanMdns,
        latencyMs: 0,
      ));
      expect(svc2.hasChannelBinding('peer-A'), isFalse);
      expect(await svc2.sendPayload('peer-A', Uint8List(3)), isFalse);
    });

    test(
        'a failed probe of a different address keeps the bound '
        'channel', () async {
      final ticket = _ticket();
      final svc = MeshTransportService(
        sessionProbe: (addr) async => addr.contains('1.2.3.4') ? ticket : null,
        frameTransport: (_, __) async => true,
      );
      addTearDown(svc.dispose);
      await svc.connectToPeer(ticket.multiaddr);
      // Failed dial of a NEW address must not strip the proven channel.
      expect(
          await svc.connectToPeer('/ip4/8.8.8.8/tcp/4001/p2p/peer-A'), isFalse);
      expect(svc.hasChannelBinding('peer-A'), isTrue);
      final key = MeshTransportService.deriveSessionKey(ticket);
      expect(
          await svc.receiveFrame(
              'peer-A', MeshTransportService.encodeFrame(key, 0, Uint8List(2))),
          isTrue);
    });

    test('legacy bool probe produces a working local-only channel', () async {
      final sent = <Uint8List>[];
      final svc = MeshTransportService(
        handshakeProbe: (_) async => true,
        frameTransport: (_, frame) async {
          sent.add(frame);
          return true;
        },
      );
      addTearDown(svc.dispose);
      const addr = '/ip4/1.2.3.4/tcp/4001/p2p/legacy-peer';
      expect(await svc.connectToPeer(addr), isTrue);
      expect(svc.hasChannelBinding('legacy-peer'), isTrue);
      expect(await svc.sendPayload('legacy-peer', Uint8List.fromList([7])),
          isTrue);
      // Synthetic tickets still produce framed traffic: seq 0.
      expect(sent.single.length, equals(8 + 1 + 32));
      expect(ByteData.sublistView(sent.single).getUint64(0), equals(0));
    });

    test(
        'legacy 3-field HELLO gets an identity ACK but binds no '
        'channel', () async {
      final id = await _responderIdentity();
      MeshHandshakeTicket? bound;
      final server = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(server.close);
      server.listen((socket) {
        MeshTransportService.serveHandshake(socket, id.peerId,
            identitySigner: id.signer, onSessionBound: (t) => bound = t);
      });

      final socket = await Socket.connect('127.0.0.1', server.port);
      addTearDown(socket.destroy);
      const nonce = 'aabbccddeeff0011';
      const addr = '/ip4/127.0.0.1/tcp/1/p2p/x';
      socket.add(utf8.encode('ALX-MESH/1 HELLO $nonce $addr\n'));
      await socket.flush();
      final line = await utf8.decoder
          .bind(socket.cast<List<int>>())
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 5));
      final parts = line.trim().split(' ');
      // Legacy 5-part ACK: proto ACK nonce peerId sig — no eph field.
      expect(parts.length, equals(5));
      expect(parts[1], equals('ACK'));
      expect(bound, isNull,
          reason: 'no ephemeral exchange means no channel ticket');
    });

    test('unsigned ACK answers never bind a channel', () async {
      // The endpoint claims a REAL self-certifying peerId but holds no
      // private key — the unsigned ACK must be rejected before any
      // channel exists.
      final id = await _responderIdentity();
      final server = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(server.close);
      server.listen((socket) {
        MeshTransportService.serveHandshake(socket, id.peerId);
      });
      final svc = MeshTransportService();
      addTearDown(svc.dispose);
      final ok = await svc
          .connectToPeer('/ip4/127.0.0.1/tcp/${server.port}/p2p/${id.peerId}');
      expect(ok, isFalse);
      expect(svc.hasChannelBinding(id.peerId), isFalse);
    });
  });
}
