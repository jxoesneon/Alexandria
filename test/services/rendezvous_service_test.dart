import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/mesh_transport_service.dart';
import 'package:alexandria/services/rendezvous_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

/// Identity bundle: real Ed25519 keypair + self-certifying peerId.
Future<
    ({
      String peerId,
      AlexandriaIdentity identity,
      Future<Uint8List> Function(Uint8List) signer
    })> _identity(int seed) async {
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
    identity: identity,
    signer: (p) async =>
        Uint8List.fromList((await Ed25519().sign(p, keyPair: keyPair)).bytes),
  );
}

class _FakeIpfs extends IpfsService {
  _FakeIpfs(super.ref);
  final controller = StreamController<Map<String, String>>.broadcast();
  final List<String> subscribed = [];
  final List<String> published = [];
  final List<String> swarmConnected = [];
  bool networked = true;
  String? peerId = '12D3KooWFakeSelfPeerId';
  List<String> addrs = const [];

  @override
  bool get isNetworked => networked;
  @override
  String? get nodePeerId => peerId;
  @override
  List<String> get listenAddrs => addrs;
  @override
  Stream<Map<String, String>> get pubsubStream => controller.stream;
  @override
  Future<void> subscribeTopic(String t) async => subscribed.add(t);
  @override
  Future<bool> publishToPubsub(String t, String d) async {
    published.add(d);
    return true;
  }

  @override
  Future<bool> swarmConnect(String multiaddr) async {
    swarmConnected.add(multiaddr);
    return true;
  }
}

class _FakeIdentity extends IdentityService {
  _FakeIdentity(this._identity, this._signer) : super(SecureStorageService());
  final AlexandriaIdentity _identity;
  final Future<Uint8List> Function(Uint8List) _signer;

  @override
  Future<AlexandriaIdentity?> getIdentity() async => _identity;
  @override
  Future<Uint8List> sign(Uint8List data) => _signer(data);
}

class _FakeMesh extends MeshTransportService {
  final List<MeshPeer> registered = [];
  final List<String> dialed = [];

  @override
  int? get listenPort => 4401;
  @override
  bool get isListening => true;
  @override
  void registerPeer(MeshPeer p) => registered.add(p);
  @override
  Future<bool> connectToPeer(String addr) async {
    dialed.add(addr);
    return true;
  }
}

/// Builds a signed announce payload exactly as the service produces.
/// Defaults to the current wire version (v2, empty IPFS coordinates).
Future<String> _announce({
  required String peerId,
  required List<String> addrs,
  required Future<Uint8List> Function(Uint8List) signer,
  int v = 2,
  String ipfsPeerId = '',
  List<String> ipfsAddrs = const [],
  int? ts,
  String nonce = 'aabbccdd',
}) async {
  final t = ts ?? DateTime.now().millisecondsSinceEpoch;
  final sig = await signer(RendezvousService.announceSignBytes(
      peerId, addrs, t, nonce,
      ipfsPeerId: ipfsPeerId, ipfsAddrs: ipfsAddrs));
  return jsonEncode({
    'v': v,
    'peerId': peerId,
    'addrs': addrs,
    'ts': t,
    'nonce': nonce,
    if (v == 2) 'ipfsPeerId': ipfsPeerId,
    if (v == 2) 'ipfsAddrs': ipfsAddrs,
    'sig': base64Encode(sig),
  });
}

void main() {
  late ProviderContainer container;
  late _FakeIpfs ipfs;
  late _FakeMesh mesh;
  late RendezvousService service;
  late String selfPeerId;

  Future<void> setup({int selfSeed = 5}) async {
    final self = await _identity(selfSeed);
    selfPeerId = self.peerId;
    container = ProviderContainer(overrides: [
      ipfsServiceProvider.overrideWith((ref) {
        ipfs = _FakeIpfs(ref);
        return ipfs;
      }),
      meshTransportServiceProvider.overrideWith((ref) => mesh),
      identityServiceProvider
          .overrideWith((ref) => _FakeIdentity(self.identity, self.signer)),
    ]);
    mesh = _FakeMesh();
    service = container.read(rendezvousServiceProvider);
  }

  tearDown(() async {
    await service.stop();
    container.dispose();
  });

  group('start gating', () {
    test('announces and subscribes when fully wired', () async {
      await setup();
      await service.start();
      expect(service.isRunning, isTrue);
      expect(ipfs.subscribed, contains(RendezvousService.topic));
      expect(ipfs.published, hasLength(1));

      // The published announce verifies under our own peerId.
      final decoded = jsonDecode(ipfs.published.single) as Map<String, dynamic>;
      expect(decoded['v'], 2);
      expect(decoded['peerId'], selfPeerId);
      expect(decoded, contains('ipfsPeerId'));
      expect(decoded, contains('ipfsAddrs'));
      final sig = base64Decode(decoded['sig'] as String);
      final addrs = (decoded['addrs'] as List).cast<String>();
      expect(addrs, isNotEmpty);
      expect(
          addrs.every(
              (a) => MeshTransportService.peerIdFromMultiaddr(a) == selfPeerId),
          isTrue);
      final ok = await Ed25519().verify(
        RendezvousService.announceSignBytes(
            selfPeerId, addrs, decoded['ts'] as int, decoded['nonce'] as String,
            ipfsPeerId: decoded['ipfsPeerId'] as String,
            ipfsAddrs: (decoded['ipfsAddrs'] as List).cast<String>()),
        signature: Signature(
          sig,
          publicKey: SimplePublicKey(
              AlexandriaIdentity.decodePublicKeyBase58(selfPeerId),
              type: KeyPairType.ed25519),
        ),
      );
      expect(ok, isTrue);
    });

    test('stays inert when the engine is not networked', () async {
      await setup();
      // Force THIS container's fake into existence before mutating it -
      // the override creates it lazily on first read.
      (container.read(ipfsServiceProvider) as _FakeIpfs).networked = false;
      await service.start();
      expect(service.isRunning, isFalse);
      expect(ipfs.published, isEmpty);
    });
  });

  group('announce intake', () {
    Future<void> feed(String payload) async {
      ipfs.controller.add(
          {'topic': RendezvousService.topic, 'data': payload, 'sender': 'x'});
      // _onMessage is async - give it a few turns.
      for (var i = 0; i < 50; i++) {
        await Future.delayed(const Duration(milliseconds: 10));
        if (mesh.registered.isNotEmpty || mesh.dialed.isNotEmpty) return;
      }
    }

    test('valid signed announce registers and dials the peer', () async {
      await setup();
      await service.start();
      final remote = await _identity(77);
      final addr = '/ip4/203.0.113.7/tcp/4401/p2p/${remote.peerId}';
      await feed(await _announce(
          peerId: remote.peerId, addrs: [addr], signer: remote.signer));
      expect(mesh.registered.map((p) => p.address), contains(addr));
      expect(mesh.dialed, contains(addr));
    });

    test('forged signature is dropped', () async {
      await setup();
      await service.start();
      final remote = await _identity(77);
      final other = await _identity(99); // different key signs
      final addr = '/ip4/203.0.113.7/tcp/4401/p2p/${remote.peerId}';
      await feed(await _announce(
          peerId: remote.peerId, addrs: [addr], signer: other.signer));
      await Future.delayed(const Duration(milliseconds: 200));
      expect(mesh.registered, isEmpty);
      expect(mesh.dialed, isEmpty);
    });

    test('stale announce is dropped', () async {
      await setup();
      await service.start();
      final remote = await _identity(77);
      final addr = '/ip4/203.0.113.7/tcp/4401/p2p/${remote.peerId}';
      final stale = DateTime.now()
          .subtract(const Duration(minutes: 30))
          .millisecondsSinceEpoch;
      await feed(await _announce(
          peerId: remote.peerId,
          addrs: [addr],
          signer: remote.signer,
          ts: stale));
      await Future.delayed(const Duration(milliseconds: 200));
      expect(mesh.registered, isEmpty);
    });

    test('replayed nonce is dropped', () async {
      await setup();
      await service.start();
      final remote = await _identity(77);
      final addr = '/ip4/203.0.113.7/tcp/4401/p2p/${remote.peerId}';
      final payload = await _announce(
          peerId: remote.peerId, addrs: [addr], signer: remote.signer);
      await feed(payload);
      expect(mesh.registered, hasLength(1));
      // Same payload again - the nonce was already honored.
      ipfs.controller.add(
          {'topic': RendezvousService.topic, 'data': payload, 'sender': 'x'});
      await Future.delayed(const Duration(milliseconds: 200));
      expect(mesh.registered, hasLength(1));
    });

    test('self-announce is ignored', () async {
      await setup();
      await service.start();
      // Our own announce (published above) loops back - ignore it.
      final own = ipfs.published.single;
      ipfs.controller
          .add({'topic': RendezvousService.topic, 'data': own, 'sender': 'x'});
      await Future.delayed(const Duration(milliseconds: 200));
      expect(mesh.registered, isEmpty);
      expect(mesh.dialed, isEmpty);
    });

    test('address grafting a foreign peerId is dropped', () async {
      await setup();
      await service.start();
      final remote = await _identity(77);
      final victim = await _identity(88);
      // Signed by remote, but the address names the victim's peerId.
      final grafted = '/ip4/203.0.113.7/tcp/4401/p2p/${victim.peerId}';
      await feed(await _announce(
          peerId: remote.peerId, addrs: [grafted], signer: remote.signer));
      await Future.delayed(const Duration(milliseconds: 200));
      expect(mesh.registered, isEmpty);
    });

    test('malformed payloads are dropped', () async {
      await setup();
      await service.start();
      for (final bad in [
        'not json',
        '{"v":2}',
        jsonEncode({'v': 1, 'peerId': 42}),
        'x' * 9000,
      ]) {
        ipfs.controller.add(
            {'topic': RendezvousService.topic, 'data': bad, 'sender': 'x'});
      }
      await Future.delayed(const Duration(milliseconds: 200));
      expect(mesh.registered, isEmpty);
    });

    test('v2 announce swarm-connects each signed libp2p addr', () async {
      await setup();
      await service.start();
      final remote = await _identity(77);
      final addr = '/ip4/203.0.113.7/tcp/4401/p2p/${remote.peerId}';
      const ipfsPeer = '12D3KooWRemoteSwarmPeer';
      const swarm1 = '/ip4/203.0.113.7/tcp/4001/p2p/$ipfsPeer';
      const swarm2 = '/ip4/203.0.113.7/tcp/4002/p2p/$ipfsPeer';
      await feed(await _announce(
          peerId: remote.peerId,
          addrs: [addr],
          signer: remote.signer,
          ipfsPeerId: ipfsPeer,
          ipfsAddrs: [swarm1, swarm2]));
      expect(mesh.registered.map((p) => p.address), contains(addr));
      expect(ipfs.swarmConnected, containsAll([swarm1, swarm2]));
    });

    test('v1 announce dials mesh only - no swarm connect', () async {
      await setup();
      await service.start();
      final remote = await _identity(77);
      final addr = '/ip4/203.0.113.7/tcp/4401/p2p/${remote.peerId}';
      await feed(await _announce(
          peerId: remote.peerId, addrs: [addr], signer: remote.signer, v: 1));
      expect(mesh.registered.map((p) => p.address), contains(addr));
      expect(ipfs.swarmConnected, isEmpty);
    });

    test('swarm addr grafting a foreign ipfsPeerId is dropped', () async {
      await setup();
      await service.start();
      final remote = await _identity(77);
      final addr = '/ip4/203.0.113.7/tcp/4401/p2p/${remote.peerId}';
      // Signed ipfsPeerId is A, but the addr names a different peer.
      const grafted =
          '/ip4/203.0.113.7/tcp/4001/p2p/12D3KooWNotTheAnnouncedPeer';
      await feed(await _announce(
          peerId: remote.peerId,
          addrs: [addr],
          signer: remote.signer,
          ipfsPeerId: '12D3KooWRemoteSwarmPeer',
          ipfsAddrs: [grafted]));
      await Future.delayed(const Duration(milliseconds: 200));
      expect(mesh.registered, isEmpty);
      expect(ipfs.swarmConnected, isEmpty);
    });

    test('v2 ipfsAddrs without ipfsPeerId is dropped', () async {
      await setup();
      await service.start();
      final remote = await _identity(77);
      final addr = '/ip4/203.0.113.7/tcp/4401/p2p/${remote.peerId}';
      // Sign the consistent empty form, then strip the peerId - the
      // payload is malformed on its face regardless of signature.
      final t = DateTime.now().millisecondsSinceEpoch;
      const nonce = 'cc1122';
      final sig = await remote.signer(
          RendezvousService.announceSignBytes(remote.peerId, [addr], t, nonce));
      await feed(jsonEncode({
        'v': 2,
        'peerId': remote.peerId,
        'addrs': [addr],
        'ts': t,
        'nonce': nonce,
        'ipfsPeerId': '',
        'ipfsAddrs': ['/ip4/203.0.113.7/tcp/4001/p2p/12D3KooWAnything'],
        'sig': base64Encode(sig),
      }));
      await Future.delayed(const Duration(milliseconds: 200));
      expect(mesh.registered, isEmpty);
      expect(ipfs.swarmConnected, isEmpty);
    });
  });
}
