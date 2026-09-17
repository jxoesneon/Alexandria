import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'identity_service.dart';
import 'ipfs_service.dart';
import 'mesh_transport_service.dart';

final rendezvousServiceProvider = Provider((ref) => RendezvousService(ref));

/// Peer discoverability over the real swarm: each running node
/// periodically publishes a SIGNED announce to a well-known gossipsub
/// topic carrying its Alexandria peerId and its ALX-MESH dialable
/// multiaddrs. Subscribers verify the announcement (the peerId is
/// self-certifying - the signature must verify under the key the
/// peerId encodes) and auto-dial the advertised addresses.
///
/// Honesty bounds:
///  * An announce is a CLAIM until a handshake proves it - discovered
///    peers enter as pending and only a completed ALX-MESH/1 mutual
///    handshake marks them reachable (the mesh proof-gating rules).
///  * Advertised addresses are this host's own interface addresses -
///    a NAT'd node announces what it can see, which may not be
///    dialable from the WAN. LAN announces always work.
///  * Announcements expire ([maxAnnounceAge]) and nonces are
///    replay-filtered; a stale or replayed announce is dropped.
class RendezvousService {
  RendezvousService(
    this._ref, {
    this.announceInterval = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Ref _ref;
  final DateTime Function() _now;

  /// How often a running node re-publishes its announce.
  final Duration announceInterval;

  /// Well-known gossipsub topic carrying rendezvous announces.
  static const String topic = '/alexandria/rendezvous/1';

  /// Signing domain for announce payloads - distinct from every other
  /// signature domain in the codebase so an announce can never be
  /// replayed as a handshake, vote, or receipt signature.
  static const String signDomain = 'ALX-RENDEZVOUS/1';

  /// Announces older than this are dropped (and future-dated ones
  /// beyond the same skew) - a captured announce has a bounded life.
  static const Duration maxAnnounceAge = Duration(minutes: 10);

  static const int _maxAddrs = 8;
  static const int _maxMessageBytes = 8192;
  static const int _maxSeenNonces = 4096;

  /// Bounded replay cache (FIFO eviction).
  final LinkedHashSet<String> _seenNonces = LinkedHashSet();

  Timer? _announceTimer;
  StreamSubscription<Map<String, String>>? _sub;
  bool _running = false;

  bool get isRunning => _running;

  /// Starts announce + discovery. Requires: the IPFS engine networked
  /// (there is no swarm to gossip to otherwise), a bound mesh listener
  /// (there is nothing to announce without a dialable port), and a
  /// local identity (announces are signed). Fails closed to inert -
  /// [isRunning] reports the truth.
  Future<void> start() async {
    if (_running) return;
    final ipfs = _ref.read(ipfsServiceProvider);
    final mesh = _ref.read(meshTransportServiceProvider);
    if (!ipfs.isNetworked || mesh.listenPort == null) return;
    final identity = await _ref.read(identityServiceProvider).getIdentity();
    if (identity == null) return;
    _running = true;
    try {
      await ipfs.subscribeTopic(topic);
    } catch (_) {}
    _sub = ipfs.pubsubStream.listen(_onMessage);
    await _announce(identity.publicKeyBase58, mesh.listenPort!);
    _announceTimer = Timer.periodic(
        announceInterval,
        (_) => unawaited(
            _announce(identity.publicKeyBase58, mesh.listenPort ?? 0)));
  }

  Future<void> stop() async {
    _running = false;
    _announceTimer?.cancel();
    _announceTimer = null;
    await _sub?.cancel();
    _sub = null;
  }

  /// Canonical sign bytes for an announce:
  /// `ALX-RENDEZVOUS/1|peerId|addr1,addr2,...|ts|nonce`, extended for
  /// v2 with `|ipfsPeerId|ipfsAddr1,ipfsAddr2,...`. With no IPFS-layer
  /// coordinates the preimage is byte-identical to v1, so legacy
  /// announces still verify.
  static Uint8List announceSignBytes(
      String peerId, List<String> addrs, int ts, String nonce,
      {String ipfsPeerId = '', List<String> ipfsAddrs = const []}) {
    final base = '$signDomain|$peerId|${addrs.join(',')}|$ts|$nonce';
    final ext = ipfsPeerId.isEmpty ? '' : '|$ipfsPeerId|${ipfsAddrs.join(',')}';
    return Uint8List.fromList(utf8.encode('$base$ext'));
  }

  Future<void> _announce(String peerId, int listenPort) async {
    if (listenPort <= 0) return;
    final addrs = await _dialableAddrs(listenPort, peerId);
    if (addrs.isEmpty) return; // nothing honest to advertise
    final ipfs = _ref.read(ipfsServiceProvider);
    final ipfsAddrs = ipfs.listenAddrs;
    // A libp2p peer id with no dialable addr is useless to a receiver
    // (and rejected by intake) - announce both or neither.
    final ipfsPeerId = ipfsAddrs.isEmpty ? '' : (ipfs.nodePeerId ?? '');
    final ts = _now().millisecondsSinceEpoch;
    final nonce = MeshTransportService.randomNonceHex();
    try {
      final sig = await _ref.read(identityServiceProvider).sign(
          announceSignBytes(peerId, addrs, ts, nonce,
              ipfsPeerId: ipfsPeerId, ipfsAddrs: ipfsAddrs));
      final payload = jsonEncode({
        'v': 2,
        'peerId': peerId,
        'addrs': addrs,
        'ts': ts,
        'nonce': nonce,
        'ipfsPeerId': ipfsPeerId,
        'ipfsAddrs': ipfsAddrs,
        'sig': base64Encode(sig),
      });
      await ipfs.publishToPubsub(topic, payload);
    } catch (_) {
      // Announce failure leaves discovery silent, not forged.
    }
  }

  /// Builds the honest announce set: every non-loopback, non-link-local
  /// IPv4 address on this host plus the bound mesh port. Announcing
  /// what the host can see is truthful - reachability is still proven
  /// per-dial by the handshake.
  Future<List<String>> _dialableAddrs(int port, String peerId) async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      final addrs = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          addrs.add('/ip4/${addr.address}/tcp/$port/p2p/$peerId');
          if (addrs.length >= _maxAddrs) return addrs;
        }
      }
      return addrs;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _onMessage(Map<String, String> msg) async {
    if (msg['topic'] != topic) return;
    final data = msg['data'] ?? '';
    if (data.isEmpty || data.length > _maxMessageBytes) return;

    Map<String, dynamic> decoded;
    try {
      final d = jsonDecode(data);
      if (d is! Map) return;
      decoded = Map<String, dynamic>.from(d);
    } catch (_) {
      return;
    }
    final version = decoded['v'];
    if (version != 1 && version != 2) return;
    final peerId = decoded['peerId'];
    final addrsRaw = decoded['addrs'];
    final ts = decoded['ts'];
    final nonce = decoded['nonce'];
    final sigB64 = decoded['sig'];
    if (peerId is! String ||
        addrsRaw is! List ||
        ts is! int ||
        nonce is! String ||
        sigB64 is! String) {
      return;
    }
    if (addrsRaw.length > _maxAddrs || nonce.length > 64) return;

    // v2 IPFS-layer coordinates: the libp2p peer id and its dialable
    // addrs, so the receiver can open a swarm connection (bitswap/DHT)
    // alongside the ALX-MESH channel. Both fields must be present in
    // v2; absent-or-empty means "no swarm endpoint", which is valid.
    var ipfsPeerId = '';
    var ipfsAddrs = const <String>[];
    if (version == 2) {
      final ip = decoded['ipfsPeerId'];
      final ia = decoded['ipfsAddrs'];
      if (ip is! String || ia is! List) return;
      if (ip.isNotEmpty || ia.isNotEmpty) {
        if (ip.isEmpty || ia.isEmpty || ia.length > _maxAddrs) return;
        final checked = <String>[];
        for (final a in ia) {
          if (a is! String || a.length > 256) return;
          // Each libp2p addr must name the announced ipfsPeerId - the
          // same anti-grafting rule as mesh addrs.
          if (MeshTransportService.peerIdFromMultiaddr(a) != ip) return;
          checked.add(a);
        }
        ipfsPeerId = ip;
        ipfsAddrs = checked;
      }
    }

    // Freshness: drop stale or implausibly future-dated announces.
    final age = _now().millisecondsSinceEpoch - ts;
    if (age.abs() > maxAnnounceAge.inMilliseconds) return;

    // Replay: a nonce already honored is never honored twice.
    if (_seenNonces.contains(nonce)) return;

    // Self-certifying check: the peerId must decode to a real Ed25519
    // public key, and the signature must verify under it.
    Uint8List key;
    try {
      key = AlexandriaIdentity.decodePublicKeyBase58(peerId);
      if (key.length != 32) return;
    } catch (_) {
      return;
    }
    Uint8List sig;
    try {
      sig = base64Decode(sigB64);
    } catch (_) {
      return;
    }
    if (sig.length != 64) return;

    final addrs = <String>[];
    for (final a in addrsRaw) {
      if (a is! String || a.length > 256) return;
      // Every advertised address must name the SIGNER's peerId - an
      // announce cannot graft a victim's identity onto an attacker's
      // endpoint.
      if (MeshTransportService.peerIdFromMultiaddr(a) != peerId) return;
      addrs.add(a);
    }
    if (addrs.isEmpty) return;

    bool verified;
    try {
      verified = await Ed25519().verify(
        announceSignBytes(peerId, addrs, ts, nonce,
            ipfsPeerId: ipfsPeerId, ipfsAddrs: ipfsAddrs),
        signature: Signature(
          sig,
          publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
        ),
      );
    } catch (_) {
      return;
    }
    if (!verified) return;

    // Never dial ourselves.
    final self = await _ref.read(identityServiceProvider).getIdentity();
    if (self != null && self.publicKeyBase58 == peerId) return;

    _seenNonces.add(nonce);
    if (_seenNonces.length > _maxSeenNonces) {
      _seenNonces.remove(_seenNonces.first);
    }

    // Verified announce → unproven candidate → real dial attempts.
    // The mesh's own gating decides what reachability means.
    final mesh = _ref.read(meshTransportServiceProvider);
    for (final addr in addrs) {
      mesh.registerPeer(MeshPeer(
        peerId: peerId,
        address: addr,
        tier: TransportTier.webrtcDirect,
        latencyMs: 0,
        isPending: true,
      ));
    }
    for (final addr in addrs) {
      if (await mesh.connectToPeer(addr)) break;
    }

    // Swarm-layer dial: the announced libp2p addrs give bitswap/DHT/
    // gossipsub connectivity even before the ALX-MESH handshake
    // completes - a verified announce's ipfsPeerId is signed, so this
    // dials exactly the endpoint the signer advertised.
    if (ipfsAddrs.isNotEmpty) {
      final ipfsSvc = _ref.read(ipfsServiceProvider);
      for (final addr in ipfsAddrs) {
        unawaited(ipfsSvc.swarmConnect(addr));
      }
    }
  }
}
