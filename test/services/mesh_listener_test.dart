import 'dart:async';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/mesh_transport_service.dart';

/// Real Ed25519 identity + signer + self-certifying peerId - same
/// helper pattern as mesh_mutual_auth_test.
Future<({String peerId, Future<Uint8List> Function(Uint8List) signer})>
    _identity(int seed) async {
  final keyPair = await Ed25519()
      .newKeyPairFromSeed(List<int>.generate(32, (i) => i + seed));
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

Future<bool> _waitFor(bool Function() cond,
    {Duration limit = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(limit);
  while (DateTime.now().isBefore(deadline)) {
    if (cond()) return true;
    await Future.delayed(const Duration(milliseconds: 20));
  }
  return cond();
}

void main() {
  group('inbound listener', () {
    test('binds a real port and reports listen state honestly', () async {
      final id = await _identity(11);
      final svc = MeshTransportService(
          localPeerId: id.peerId, identitySigner: id.signer);
      addTearDown(svc.dispose);

      expect(svc.isListening, isFalse);
      expect(svc.listenPort, isNull);

      final port = await svc.startListening();
      expect(port, greaterThan(0));
      expect(svc.isListening, isTrue);
      expect(svc.listenPort, port);

      // Idempotent: a second start returns the same bound port.
      expect(await svc.startListening(), port);

      await svc.stopListening();
      expect(svc.isListening, isFalse);
      expect(svc.listenPort, isNull);
    });

    test('refuses to listen without identity material', () async {
      final svc = MeshTransportService();
      addTearDown(svc.dispose);
      expect(await svc.startListening(), 0);
      expect(svc.isListening, isFalse);
    });

    test(
        'mutual inbound handshake admits the dialer as a proven peer '
        'with a working bidirectional channel', () async {
      final listenerId = await _identity(21);
      final dialerId = await _identity(33);

      final listener = MeshTransportService(
          localPeerId: listenerId.peerId, identitySigner: listenerId.signer);
      final dialer = MeshTransportService(
          localPeerId: dialerId.peerId, identitySigner: dialerId.signer);
      addTearDown(listener.dispose);
      addTearDown(dialer.dispose);

      final port = await listener.startListening();
      expect(port, greaterThan(0));

      final dialAddr = '/ip4/127.0.0.1/tcp/$port/p2p/${listenerId.peerId}';
      expect(await dialer.connectToPeer(dialAddr), isTrue);
      expect(dialer.hasChannelBinding(listenerId.peerId), isTrue);

      // The LISTENER must admit the verified dialer: reachable, with a
      // channel - the inbound half of the mesh is real now.
      expect(
          await _waitFor(() =>
              listener.activePeers.any((p) => p.peerId == dialerId.peerId)),
          isTrue,
          reason: 'inbound mutual handshake must admit the dialer');
      expect(listener.hasChannelBinding(dialerId.peerId), isTrue);

      // Bidirectional payload exchange over the bound channels.
      final listenerGot = Completer<Uint8List>();
      final dialerGot = Completer<Uint8List>();
      listener.onPayloadReceived.listen((d) => listenerGot.complete(d));
      dialer.onPayloadReceived.listen((d) => dialerGot.complete(d));

      expect(
          await dialer.sendPayload(listenerId.peerId,
              Uint8List.fromList('dialer-to-listener'.codeUnits)),
          isTrue);
      expect(
          await listener.sendPayload(dialerId.peerId,
              Uint8List.fromList('listener-to-dialer'.codeUnits)),
          isTrue);

      expect(
          String.fromCharCodes(
              await listenerGot.future.timeout(const Duration(seconds: 5))),
          'dialer-to-listener');
      expect(
          String.fromCharCodes(
              await dialerGot.future.timeout(const Duration(seconds: 5))),
          'listener-to-dialer');
    });

    test('anonymous inbound dial is served but never admitted', () async {
      final listenerId = await _identity(41);
      final listener = MeshTransportService(
          localPeerId: listenerId.peerId, identitySigner: listenerId.signer);
      addTearDown(listener.dispose);
      final port = await listener.startListening();

      // Anonymous dialer: no identity, no signer.
      final anon = MeshTransportService();
      addTearDown(anon.dispose);
      final addr = '/ip4/127.0.0.1/tcp/$port/p2p/${listenerId.peerId}';
      // The handshake itself succeeds - the dialer verified the
      // responder's signature. What must NOT happen is the listener
      // attributing a peer record to an identity-less endpoint.
      await anon.connectToPeer(addr);
      await Future.delayed(const Duration(milliseconds: 300));
      expect(listener.peers, isEmpty,
          reason: 'anonymous inbound carries no bindable identity');
    });
  });

  group('dialPending', () {
    test('dials registered pending peers and marks proven ones', () async {
      final listenerId = await _identity(51);
      final dialerId = await _identity(61);
      final listener = MeshTransportService(
          localPeerId: listenerId.peerId, identitySigner: listenerId.signer);
      final dialer = MeshTransportService(
          localPeerId: dialerId.peerId, identitySigner: dialerId.signer);
      addTearDown(listener.dispose);
      addTearDown(dialer.dispose);

      final port = await listener.startListening();
      dialer.registerPeer(MeshPeer(
        peerId: listenerId.peerId,
        address: '/ip4/127.0.0.1/tcp/$port/p2p/${listenerId.peerId}',
        tier: TransportTier.webrtcDirect,
        latencyMs: 0,
        isPending: true,
      ));

      expect(await dialer.dialPending(), 1);
      expect(
          dialer.peers
              .firstWhere((p) => p.peerId == listenerId.peerId)
              .isReachable,
          isTrue);
    });

    test('never dials self and leaves failed dials pending', () async {
      final selfId = await _identity(71);
      final svc = MeshTransportService(
          localPeerId: selfId.peerId, identitySigner: selfId.signer);
      addTearDown(svc.dispose);
      final port = await svc.startListening();

      svc.registerPeer(MeshPeer(
        peerId: selfId.peerId,
        address: '/ip4/127.0.0.1/tcp/$port/p2p/${selfId.peerId}',
        tier: TransportTier.webrtcDirect,
        latencyMs: 0,
        isPending: true,
      ));
      svc.registerPeer(MeshPeer(
        peerId: 'QmDefinitelyUnreachableNode999',
        address: '/ip4/127.0.0.1/tcp/1/p2p/QmDefinitelyUnreachableNode999',
        tier: TransportTier.webrtcDirect,
        latencyMs: 0,
        isPending: true,
      ));

      // Self is skipped; the dead address fails honestly. Both stay
      // pending/unproven.
      expect(await svc.dialPending(), 0);
      final self = svc.peers.firstWhere((p) => p.peerId == selfId.peerId);
      expect(self.isReachable, isFalse);
    });
  });
}
