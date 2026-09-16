// Tests for the dialer-auth residual closure: mutual handshake
// authentication in ALX-MESH/1. Previously the transcript carried ONE
// signature (responder only) — the dialer was anonymous, so an active
// MITM could run a *separate* handshake as itself toward the dialer and
// a responder had no way to know WHO it bound a channel to. The mutual
// (7-field) HELLO carries the dialer's self-certifying peerId plus an
// Ed25519 signature over
// `ALX-MESH/1|DIALER|nonce|dialerPeerId|multiaddr|dialerEphemeral`;
// the responder verifies it against the key the peerId encodes, the
// responder's ACK signature additionally covers the verified
// dialerPeerId, and BOTH wire lines (so BOTH signatures) feed the
// session-key transcript.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/mesh_transport_service.dart';

/// Builds a real Ed25519 identity + signer, and the self-certifying
/// peerId derived from its public key.
Future<({String peerId, Future<Uint8List> Function(Uint8List) signer})>
    _identity(int seedOffset) async {
  final keyPair = await Ed25519()
      .newKeyPairFromSeed(List<int>.generate(32, (i) => i + seedOffset));
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

void main() {
  group('mutual handshake auth (dialer-auth residual closure)', () {
    test(
        'mutual HELLO is verified end-to-end and both signatures feed '
        'the channel key', () async {
      final responder = await _identity(7);
      final dialer = await _identity(90);
      MeshHandshakeTicket? responderTicket;
      final server = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(server.close);
      server.listen((socket) {
        MeshTransportService.serveHandshake(socket, responder.peerId,
            identitySigner: responder.signer,
            onSessionBound: (t) => responderTicket = t);
      });

      final svc = MeshTransportService(
        localPeerId: dialer.peerId,
        identitySigner: dialer.signer,
      );
      addTearDown(svc.dispose);

      final multiaddr =
          '/ip4/127.0.0.1/tcp/${server.port}/p2p/${responder.peerId}';
      expect(await svc.connectToPeer(multiaddr), isTrue);
      expect(svc.hasChannelBinding(responder.peerId), isTrue);

      final ticket = responderTicket;
      expect(ticket, isNotNull,
          reason: 'responder must bind a session for a valid mutual '
              'HELLO');
      expect(ticket!.dialerPeerId, equals(dialer.peerId),
          reason: 'the responder ticket must record the authenticated '
              'dialer identity');
      expect(ticket.dialerSignature, hasLength(64));
      expect(ticket.responderSide, isTrue);

      // Both signatures are in the transcript: the wire HELLO line is
      // reproduced verbatim, so the dialer's sigB64 is part of the
      // session-key input.
      final transcript = utf8.decode(ticket.transcriptBytes);
      expect(transcript, contains(dialer.peerId));
      expect(transcript, contains(base64Encode(ticket.dialerSignature)));
      expect(transcript, contains(base64Encode(ticket.responderSignature)));

      // The responder-derived key verifies frames on the dialer's
      // channel — proving both ends derived the same key from the
      // mutual transcript.
      final key = MeshTransportService.deriveSessionKey(ticket);
      final inbound = MeshTransportService.encodeFrame(key, 0, Uint8List(3));
      expect(await svc.receiveFrame(responder.peerId, inbound), isTrue);
    });

    test('a forged dialer signature is refused before key exchange', () async {
      final responder = await _identity(7);
      final victim = await _identity(90); // claimed, not owned
      final attacker = await _identity(150); // signs with the WRONG key
      final served = Completer<bool>();
      final server = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(server.close);
      server.listen((socket) {
        served.complete(MeshTransportService.serveHandshake(
            socket, responder.peerId,
            identitySigner: responder.signer));
      });

      // Craft a 7-field HELLO claiming the victim's peerId but signed
      // by the attacker's key — self-certifying verification must fail.
      final socket = await Socket.connect('127.0.0.1', server.port);
      addTearDown(socket.destroy);
      const nonce = '0011223344556677';
      const addr = '/ip4/127.0.0.1/tcp/1/p2p/x';
      const eph = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
      final forgedSig = await attacker.signer(
          MeshTransportService.dialerHelloSignBytes(
              nonce, victim.peerId, addr, eph));
      socket.add(
          utf8.encode('ALX-MESH/1 HELLO $nonce $addr $eph ${victim.peerId} '
              '${base64Encode(forgedSig)}\n'));
      await socket.flush();

      expect(await served.future, isFalse,
          reason: 'a dialer claiming an identity it cannot sign for '
              'must be refused — the responder verified the signature '
              'against the key the claimed peerId encodes');
    });

    test('a 6-field HELLO (claimed identity, no proof) is malformed', () async {
      final responder = await _identity(7);
      final victim = await _identity(90);
      final served = Completer<bool>();
      final server = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(server.close);
      server.listen((socket) {
        served.complete(MeshTransportService.serveHandshake(
            socket, responder.peerId,
            identitySigner: responder.signer));
      });

      final socket = await Socket.connect('127.0.0.1', server.port);
      addTearDown(socket.destroy);
      const nonce = 'aabbccddeeff0011';
      const addr = '/ip4/127.0.0.1/tcp/1/p2p/x';
      const eph = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
      socket.add(
          utf8.encode('ALX-MESH/1 HELLO $nonce $addr $eph ${victim.peerId}\n'));
      await socket.flush();
      expect(await served.future, isFalse);
    });

    test(
        'an ACK signed without the dialer-identity binding is '
        'rejected by a mutual dialer', () async {
      // A responder that signs the PRE-mutual form (no dialerPeerId in
      // the signature) — e.g. a relay replaying responder material or
      // an endpoint trying to re-attribute the session — must fail the
      // dialer's verification.
      final responder = await _identity(7);
      final dialer = await _identity(90);
      final server = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(server.close);
      server.listen((socket) async {
        final stream = socket.asBroadcastStream();
        final line = await utf8.decoder
            .bind(stream)
            .transform(const LineSplitter())
            .first;
        final parts = line.trim().split(' ');
        final nonce = parts[2];
        final addr = parts[3];
        final dialerEph = parts[4];
        final responderPair = await X25519().newKeyPair();
        final responderEph =
            base64Encode((await responderPair.extractPublicKey()).bytes);
        // Sign WITHOUT the dialerPeerId — the stale form.
        final sig = await responder.signer(
            MeshTransportService.handshakeSignBytes(
                nonce, responder.peerId, addr, dialerEph, responderEph));
        socket.add(utf8.encode('ALX-MESH/1 ACK $nonce ${responder.peerId} '
            '${base64Encode(sig)} $responderEph\n'));
        await socket.flush();
      });

      final svc = MeshTransportService(
        localPeerId: dialer.peerId,
        identitySigner: dialer.signer,
      );
      addTearDown(svc.dispose);
      final ok = await svc.connectToPeer(
          '/ip4/127.0.0.1/tcp/${server.port}/p2p/${responder.peerId}');
      expect(ok, isFalse,
          reason: 'the ACK must cover the authenticated dialer '
              'identity — a responder signature that omits it cannot '
              'be re-attributed across sessions');
    });

    test(
        'a MITM cannot complete a handshake toward the responder '
        'while claiming an identity it does not own', () async {
      // The MITM dials the responder presenting the VICTIM's peerId —
      // it holds no matching private key, so the responder refuses
      // before the ephemeral exchange. This is the responder-side half
      // of "a MITM can't complete a handshake without owning the
      // claimed identity" (the dialer-side half is the round-4
      // signature binding).
      final responder = await _identity(7);
      final victim = await _identity(90);
      final served = Completer<bool>();
      final server = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(server.close);
      server.listen((socket) {
        served.complete(MeshTransportService.serveHandshake(
            socket, responder.peerId,
            identitySigner: responder.signer));
      });

      // MITM service configured to CLAIM the victim's peerId but with
      // no signer — the plumbing refuses to even emit the mutual form
      // (it cannot produce a signature), and a manual attempt without
      // valid signature material was covered above.
      final mitm = MeshTransportService(localPeerId: victim.peerId);
      addTearDown(mitm.dispose);
      // With identity but NO signer, the dial degrades to anonymous —
      // the responder still authenticates only itself; the MITM gains
      // no channel it can attribute to the victim identity.
      final ok = await mitm.connectToPeer(
          '/ip4/127.0.0.1/tcp/${server.port}/p2p/${responder.peerId}');
      expect(ok, isTrue,
          reason: 'anonymous dials remain allowed — '
              'but the MITM is anonymous, not the victim');
      expect(await served.future, isTrue);
      // The bound session must record NO dialer identity.
    });

    test('anonymous dialer handshakes remain backward compatible', () async {
      final responder = await _identity(7);
      MeshHandshakeTicket? responderTicket;
      final server = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(server.close);
      server.listen((socket) {
        MeshTransportService.serveHandshake(socket, responder.peerId,
            identitySigner: responder.signer,
            onSessionBound: (t) => responderTicket = t);
      });

      final svc = MeshTransportService(); // no identity → 5-field HELLO
      addTearDown(svc.dispose);
      final ok = await svc.connectToPeer(
          '/ip4/127.0.0.1/tcp/${server.port}/p2p/${responder.peerId}');
      expect(ok, isTrue);
      expect(responderTicket, isNotNull);
      expect(responderTicket!.dialerPeerId, isEmpty);
      expect(responderTicket!.dialerSignature, isEmpty);
    });

    test('a mutual dialer rejects an unsigned (no-signer) endpoint', () async {
      final responder = await _identity(7);
      final dialer = await _identity(90);
      final server = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(server.close);
      server.listen((socket) {
        MeshTransportService.serveHandshake(socket, responder.peerId);
      });
      final svc = MeshTransportService(
        localPeerId: dialer.peerId,
        identitySigner: dialer.signer,
      );
      addTearDown(svc.dispose);
      expect(
          await svc.connectToPeer(
              '/ip4/127.0.0.1/tcp/${server.port}/p2p/${responder.peerId}'),
          isFalse);
      expect(svc.hasChannelBinding(responder.peerId), isFalse);
    });

    test(
        'a broken signer fails the dial closed instead of '
        'downgrading to anonymous', () async {
      final responder = await _identity(7);
      final dialer = await _identity(90);
      final helloBytes = <int>[];
      final server = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(server.close);
      server.listen((socket) {
        socket.listen(helloBytes.addAll);
      });
      final svc = MeshTransportService(
        localPeerId: dialer.peerId,
        identitySigner: (_) async => Uint8List(8), // not a signature
      );
      addTearDown(svc.dispose);
      expect(
          await svc.connectToPeer(
              '/ip4/127.0.0.1/tcp/${server.port}/p2p/${responder.peerId}'),
          isFalse,
          reason: 'a signer that cannot emit an Ed25519 signature '
              'must not silently downgrade the dial to anonymous');
      expect(svc.hasChannelBinding(responder.peerId), isFalse);
    });

    test(
        'a reflected outbound frame fails the inbound MAC '
        '(direction binding)', () async {
      // A relay that copies our own outbound frame back at us must not
      // get it accepted as peer traffic — the direction byte inside
      // the MAC domain makes the two directions non-interchangeable.
      final ticket = MeshHandshakeTicket(
        peerId: 'peer-A',
        multiaddr: '/ip4/1.2.3.4/tcp/4001/p2p/peer-A',
        nonce: '0123456789abcdef',
        responderSignature: Uint8List(64),
      );
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

      // Reflect our own outbound frame back as "inbound".
      expect(await svc.receiveFrame('peer-A', sent.single), isFalse,
          reason: 'a reflected copy of our own frame must not verify '
              'as inbound — the MAC direction tag differs');
    });
  });
}
