import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final meshTransportServiceProvider =
    Provider((ref) => MeshTransportService(bootstrap: true));

enum TransportTier {
  lanMdns,
  wifiDirect,
  webrtcDirect,
  bleProximity,
  circuitRelay,
}

class MeshPeer {
  final String peerId;
  final String address;
  final TransportTier tier;
  final int latencyMs;
  final bool isReachable;
  final bool isPending;

  MeshPeer({
    required this.peerId,
    required this.address,
    required this.tier,
    required this.latencyMs,
    this.isReachable = true,
    this.isPending = false,
  });

  MeshPeer copyWith({
    String? peerId,
    String? address,
    TransportTier? tier,
    int? latencyMs,
    bool? isReachable,
    bool? isPending,
  }) {
    return MeshPeer(
      peerId: peerId ?? this.peerId,
      address: address ?? this.address,
      tier: tier ?? this.tier,
      latencyMs: latencyMs ?? this.latencyMs,
      isReachable: isReachable ?? this.isReachable,
      isPending: isPending ?? this.isPending,
    );
  }
}

class MeshTransportService {
  final Map<String, MeshPeer> _peers = {};
  final StreamController<MeshPeer> _peerDiscoveryController =
      StreamController.broadcast();
  final StreamController<Uint8List> _incomingPayloadController =
      StreamController.broadcast();
  final StreamController<List<MeshPeer>> _peerListController =
      StreamController.broadcast();

  final Set<TransportTier> _activeTiers = {
    TransportTier.lanMdns,
    TransportTier.wifiDirect,
    TransportTier.webrtcDirect,
    TransportTier.bleProximity,
    TransportTier.circuitRelay,
  };

  MeshTransportService({bool bootstrap = false}) {
    if (bootstrap) {
      bootstrapDefaultPeers();
    }
  }

  /// Seeds the well-known bootstrap/relay addresses.
  ///
  /// HONESTY: these are *candidate* endpoints, not proven peers. They
  /// start `isReachable: false` with `isPending: true` and
  /// `latencyMs: 0` — no reachability or latency is claimed until a
  /// real handshake (e.g. [connectToPeer]) completes. Callers should
  /// treat them as dial targets, not as active peers.
  void bootstrapDefaultPeers() {
    final defaultBootstrap = [
      MeshPeer(
        peerId: 'QmBootstrapNode1AlexandriaAlpha',
        address: '/dns4/node1.alexandria.alexandria.network/tcp/4001/p2p/QmBootstrapNode1AlexandriaAlpha',
        tier: TransportTier.webrtcDirect,
        latencyMs: 0,
        isReachable: false,
        isPending: true,
      ),
      MeshPeer(
        peerId: 'QmBootstrapNode2AlexandriaBeta',
        address: '/dns4/node2.alexandria.alexandria.network/tcp/4001/p2p/QmBootstrapNode2AlexandriaBeta',
        tier: TransportTier.webrtcDirect,
        latencyMs: 0,
        isReachable: false,
        isPending: true,
      ),
      MeshPeer(
        peerId: 'QmRelayNodeEuropeanLibraryCommons',
        address: '/dns4/relay.alexandria.network/tcp/4001/p2p/QmRelayNodeEuropeanLibraryCommons',
        tier: TransportTier.circuitRelay,
        latencyMs: 0,
        isReachable: false,
        isPending: true,
      ),
      MeshPeer(
        peerId: 'QmLocalMeshDiscoveryRelay',
        address: '/ip4/127.0.0.1/tcp/4001/p2p/QmLocalMeshDiscoveryRelay',
        tier: TransportTier.lanMdns,
        latencyMs: 0,
        isReachable: false,
        isPending: true,
      ),
    ];

    for (final peer in defaultBootstrap) {
      if (!_peers.containsKey(peer.peerId)) {
        _peers[peer.peerId] = peer;
      }
    }
  }

  Stream<MeshPeer> get onPeerDiscovered => _peerDiscoveryController.stream;
  Stream<Uint8List> get onPayloadReceived => _incomingPayloadController.stream;
  Stream<List<MeshPeer>> get peerListStream => _peerListController.stream;

  List<MeshPeer> get activePeers =>
      _peers.values.where((p) => p.isReachable).toList();

  List<MeshPeer> get peers => List.unmodifiable(_peers.values);

  void registerPeer(MeshPeer peer) {
    _peers[peer.peerId] = peer;
    _peerDiscoveryController.add(peer);
    _emitPeerList();
  }

  void unregisterPeer(String peerId) {
    _peers.remove(peerId);
    _emitPeerList();
  }

  void setTierEnabled(TransportTier tier, bool enabled) {
    if (enabled) {
      _activeTiers.add(tier);
    } else {
      _activeTiers.remove(tier);
    }
    _emitPeerList();
  }

  bool isTierEnabled(TransportTier tier) => _activeTiers.contains(tier);

  TransportTier? selectBestTransport(String peerId) {
    final peer = _peers[peerId];
    if (peer == null || !peer.isReachable) return null;
    return _bestTierFor(peer);
  }

  /// Picks the peer's own tier when enabled, else falls back through
  /// the tier priority cascade. Returns null when no tier is active.
  TransportTier? _bestTierFor(MeshPeer peer) {
    if (_activeTiers.contains(peer.tier)) return peer.tier;

    // Fallback tier priority cascade
    for (final candidate in TransportTier.values) {
      if (_activeTiers.contains(candidate)) return candidate;
    }
    return null;
  }

  /// Attempts to send [data] to [peerId].
  ///
  /// Returns `false` when the peer is unknown or not currently
  /// reachable (i.e. no handshake has proven it — including unproven
  /// bootstrap candidates), or when no transport tier is available.
  /// Only peers marked `isReachable` (set by [connectToPeer] or by
  /// registering an already-proven peer) dispatch. NOTE: the actual
  /// transport dispatch is still a stub — `true` here means a route
  /// exists and the send was attempted, not that delivery was
  /// acknowledged; wire that to real transport ACKs when they land.
  Future<bool> sendPayload(String peerId, Uint8List data) =>
      _attemptSend(peerId, data, allowPending: false);

  /// Shared dispatch gate for [sendPayload] and the [connectToPeer]
  /// handshake. A peer is dialable when it is proven `isReachable`, or
  /// — only for handshake traffic — when it is `isPending` and
  /// [allowPending] is set, since a pending peer must be dialed to
  /// *prove* reachability. Ordinary payload sends to pending or
  /// unreachable peers are refused (returns `false`).
  Future<bool> _attemptSend(
    String peerId,
    Uint8List data, {
    required bool allowPending,
  }) async {
    final peer = _peers[peerId];
    if (peer == null) return false;
    final dialable = peer.isReachable || (allowPending && peer.isPending);
    if (!dialable) return false;
    return _bestTierFor(peer) != null;
  }

  Stream<List<MeshPeer>> watchPeers() async* {
    yield peers;
    yield* _peerListController.stream;
  }

  Future<bool> connectToPeer(String multiaddr) async {
    final peerId = _peerIdFromMultiaddr(multiaddr);
    if (peerId == null || peerId.isEmpty) return false;

    MeshPeer? peer = _peers[peerId];
    if (peer == null) {
      peer = MeshPeer(
        peerId: peerId,
        address: multiaddr,
        tier: TransportTier.webrtcDirect,
        latencyMs: 0,
      );
      _peers[peerId] = peer;
    }

    // Mark dial-in-progress WITHOUT claiming reachability — the peer
    // stays unproven (isReachable: false) until the handshake ping
    // below actually succeeds.
    _peers[peerId] = peer.copyWith(isPending: true, isReachable: false);
    _emitPeerList();

    final stopwatch = Stopwatch()..start();
    // Handshake ping to the pending (unproven) peer.
    final ok = await _attemptSend(peerId, Uint8List(0), allowPending: true);
    stopwatch.stop();

    _peers[peerId] = peer.copyWith(
      isPending: false,
      isReachable: ok,
      latencyMs: ok ? stopwatch.elapsedMilliseconds : peer.latencyMs,
    );
    _emitPeerList();
    return ok;
  }

  Future<void> disconnectPeer(String peerId) async {
    final peer = _peers[peerId];
    if (peer != null) {
      _peers[peerId] = peer.copyWith(isReachable: false, isPending: false);
      _emitPeerList();
    }
  }

  String? _peerIdFromMultiaddr(String multiaddr) {
    final match = RegExp(r'/p2p/([^/]+)$').firstMatch(multiaddr);
    return match?.group(1);
  }

  void _emitPeerList() {
    if (!_peerListController.isClosed) {
      _peerListController.add(peers);
    }
  }

  void dispose() {
    _peerDiscoveryController.close();
    _incomingPayloadController.close();
    _peerListController.close();
  }
}
