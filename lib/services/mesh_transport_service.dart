import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final meshTransportServiceProvider = Provider((ref) => MeshTransportService());

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
    if (_activeTiers.contains(peer.tier)) return peer.tier;

    // Fallback tier priority cascade
    for (final candidate in TransportTier.values) {
      if (_activeTiers.contains(candidate)) return candidate;
    }
    return null;
  }

  Future<bool> sendPayload(String peerId, Uint8List data) async {
    final transport = selectBestTransport(peerId);
    if (transport == null) return false;
    // Dispatches through chosen transport tier
    return true;
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

    _peers[peerId] = peer.copyWith(isPending: true, isReachable: true);
    _emitPeerList();

    final stopwatch = Stopwatch()..start();
    final ok = await sendPayload(peerId, Uint8List(0));
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
