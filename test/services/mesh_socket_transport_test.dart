// Tests for the frame-dispatch residual closure: sendPayload's MAC'd
// frames are written length-prefixed (`len(4 BE) ‖ seq ‖ payload ‖
// mac`) to the SAME socket that carried the handshake, and the receive
// pump parses socket chunks, verifies MAC + direction + sequence, and
// surfaces payloads on onPayloadReceived. Socket close demotes the
// peer under the round-6 TOCTOU rules (re-read the peer row; demote
// only the failed address).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/mesh_transport_service.dart';

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

/// Polls [check] until it holds or the timeout expires — socket
/// teardown is delivered asynchronously through the pump.
Future<void> _eventually(bool Function() check,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!check()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  group('frame transport over the handshake socket', () {
    test('frames flow both directions over the real wire and surface '
        'on onPayloadReceived', () async {
      final responder = await _identity(7);
      MeshHandshakeTicket? responderTicket;
      final server = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(server.close);
      server.listen((socket) {
        MeshTransportService.serveHandshake(socket, responder.peerId,
            identitySigner: responder.signer,
            onSessionBound: (t) => responderTicket = t);
      });

      final dialer = MeshTransportService();
      addTearDown(dialer.dispose);
      final multiaddr =
          '/ip4/127.0.0.1/tcp/${server.port}/p2p/${responder.peerId}';
      expect(await dialer.connectToPeer(multiaddr), isTrue);

      // Stand up the responder-side service on the SAME ticket — its
      // socket + broadcast stream attach a symmetric pump.
      final responderSvc = MeshTransportService(
        sessionProbe: (_) async => responderTicket,
      );
      addTearDown(responderSvc.dispose);
      expect(await responderSvc.connectToPeer(multiaddr), isTrue);

      final dialerInbox = <Uint8List>[];
      final responderInbox = <Uint8List>[];
      dialer.onPayloadReceived.listen(dialerInbox.add);
      responderSvc.onPayloadReceived.listen(responderInbox.add);

      // Dialer → responder: the MAC'd frame is written to the
      // handshake socket and parsed out the other end.
      final p1 = Uint8List.fromList(utf8.encode('ping responder'));
      expect(await dialer.sendPayload(responder.peerId, p1), isTrue);
      await _eventually(() => responderInbox.isNotEmpty);
      expect(responderInbox.single, equals(p1));

      // Responder → dialer over the same connection.
      final p2 = Uint8List.fromList(utf8.encode('pong dialer'));
      expect(
          await responderSvc.sendPayload(responder.peerId, p2), isTrue);
      await _eventually(() => dialerInbox.isNotEmpty);
      expect(dialerInbox.single, equals(p2));
    });

    test('wire frames are length-prefixed and MAC-verified — a '
        'tampered frame is dropped before release', () async {
      final responder = await _identity(7);
      MeshHandshakeTicket? responderTicket;
      final server = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(server.close);
      server.listen((socket) {
        MeshTransportService.serveHandshake(socket, responder.peerId,
            identitySigner: responder.signer,
            onSessionBound: (t) => responderTicket = t);
      });

      final dialer = MeshTransportService();
      addTearDown(dialer.dispose);
      final multiaddr =
          '/ip4/127.0.0.1/tcp/${server.port}/p2p/${responder.peerId}';
      expect(await dialer.connectToPeer(multiaddr), isTrue);
      final inbox = <Uint8List>[];
      dialer.onPayloadReceived.listen(inbox.add);

      // Feed a MAC-invalid frame directly onto the responder's socket
      // — the wire path must parse the prefix, verify, and drop.
      final key =
          MeshTransportService.deriveSessionKey(responderTicket!);
      // Direction 1 = responder→dialer — what the dialer's channel
      // expects inbound.
      final badFrame = MeshTransportService.encodeFrame(
          key, 0, Uint8List.fromList([1, 2, 3]), 1)
        ..[12] ^= 0xff; // payload-region bit flip
      final sock = responderTicket!.socket!;
      sock.add((BytesBuilder()
            ..add((ByteData(4)..setUint32(0, badFrame.length))
                .buffer
                .asUint8List())
            ..add(badFrame))
          .toBytes());
      await sock.flush();

      // A VALID frame behind it still parses — the tampered one is
      // dropped by receiveFrame, not the stream.
      final goodFrame = MeshTransportService.encodeFrame(
          key, 1, Uint8List.fromList([9, 9, 9]), 1);
      sock.add((BytesBuilder()
            ..add((ByteData(4)..setUint32(0, goodFrame.length))
                .buffer
                .asUint8List())
            ..add(goodFrame))
          .toBytes());
      await sock.flush();

      await _eventually(() => inbox.isNotEmpty);
      expect(inbox, hasLength(1));
      expect(inbox.single, equals(Uint8List.fromList([9, 9, 9])));
    });

    test('socket close demotes the peer and drops the channel',
        () async {
      final responder = await _identity(7);
      MeshHandshakeTicket? responderTicket;
      final server = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(server.close);
      server.listen((socket) {
        MeshTransportService.serveHandshake(socket, responder.peerId,
            identitySigner: responder.signer,
            onSessionBound: (t) => responderTicket = t);
      });

      final dialer = MeshTransportService();
      addTearDown(dialer.dispose);
      final multiaddr =
          '/ip4/127.0.0.1/tcp/${server.port}/p2p/${responder.peerId}';
      expect(await dialer.connectToPeer(multiaddr), isTrue);
      expect(dialer.hasChannelBinding(responder.peerId), isTrue);

      responderTicket!.socket!.destroy();
      await _eventually(() => !dialer.peers
          .firstWhere((p) => p.peerId == responder.peerId)
          .isReachable);
      expect(dialer.hasChannelBinding(responder.peerId), isFalse);
      expect(
          await dialer.sendPayload(responder.peerId, Uint8List(3)),
          isFalse);
    });

    test('a dead OLD socket does not demote the peer\'s fresh '
        'address (round-6 demote-only-the-failed-address rule)',
        () async {
      final responder = await _identity(7);
      MeshHandshakeTicket? ticketA;
      final serverA = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(serverA.close);
      serverA.listen((socket) {
        MeshTransportService.serveHandshake(socket, responder.peerId,
            identitySigner: responder.signer,
            onSessionBound: (t) => ticketA = t);
      });
      MeshHandshakeTicket? ticketB;
      final serverB = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(serverB.close);
      serverB.listen((socket) {
        MeshTransportService.serveHandshake(socket, responder.peerId,
            identitySigner: responder.signer,
            onSessionBound: (t) => ticketB = t);
      });

      final dialer = MeshTransportService();
      addTearDown(dialer.dispose);
      final addrA =
          '/ip4/127.0.0.1/tcp/${serverA.port}/p2p/${responder.peerId}';
      final addrB =
          '/ip4/127.0.0.1/tcp/${serverB.port}/p2p/${responder.peerId}';
      expect(await dialer.connectToPeer(addrA), isTrue);
      expect(await dialer.connectToPeer(addrB), isTrue);
      expect(
          dialer.peers
              .firstWhere((p) => p.peerId == responder.peerId)
              .address,
          equals(addrB));

      // Kill the stale A link — the peer's record points at B and the
      // installed channel is B's, so nothing may demote.
      ticketA!.socket!.destroy();
      await serverA.close();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
          dialer.peers
              .firstWhere((p) => p.peerId == responder.peerId)
              .isReachable,
          isTrue,
          reason: 'a dead stale socket must not demote the fresh '
              'address');
      expect(dialer.hasChannelBinding(responder.peerId), isTrue);

      // Now kill the CURRENT (B) link — that one demotes.
      ticketB!.socket!.destroy();
      await _eventually(() => !dialer.peers
          .firstWhere((p) => p.peerId == responder.peerId)
          .isReachable);
      expect(dialer.hasChannelBinding(responder.peerId), isFalse);
    });

    test('a frame declaring more than maxFrameBytes tears down the '
        'link (memory-exhaustion guard)', () async {
      final responder = await _identity(7);
      MeshHandshakeTicket? responderTicket;
      final server = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(server.close);
      server.listen((socket) {
        MeshTransportService.serveHandshake(socket, responder.peerId,
            identitySigner: responder.signer,
            onSessionBound: (t) => responderTicket = t);
      });

      final dialer = MeshTransportService();
      addTearDown(dialer.dispose);
      final multiaddr =
          '/ip4/127.0.0.1/tcp/${server.port}/p2p/${responder.peerId}';
      expect(await dialer.connectToPeer(multiaddr), isTrue);

      final sock = responderTicket!.socket!;
      // Declare a 0xFFFFFFFF frame — the pump must refuse to buffer.
      sock.add(Uint8List.fromList([0xff, 0xff, 0xff, 0xff, 0x00]));
      await sock.flush();

      await _eventually(() => !dialer.peers
          .firstWhere((p) => p.peerId == responder.peerId)
          .isReachable);
      expect(dialer.hasChannelBinding(responder.peerId), isFalse);
    });
  });
}
