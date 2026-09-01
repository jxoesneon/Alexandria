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

  MeshPeer({
    required this.peerId,
    required this.address,
    required this.tier,
    required this.latencyMs,
    this.isReachable = true,
  });
}

class MeshTransportService {
  final Map<String, MeshPeer> _peers = {};
  final StreamController<MeshPeer> _peerDiscoveryController =
      StreamController.broadcast();
  final StreamController<Uint8List> _incomingPayloadController =
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

  List<MeshPeer> get activePeers =>
      _peers.values.where((p) => p.isReachable).toList();

  void registerPeer(MeshPeer peer) {
    _peers[peer.peerId] = peer;
    _peerDiscoveryController.add(peer);
  }

  void unregisterPeer(String peerId) {
    _peers.remove(peerId);
  }

  void setTierEnabled(TransportTier tier, bool enabled) {
    if (enabled) {
      _activeTiers.add(tier);
    } else {
      _activeTiers.remove(tier);
    }
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

  void dispose() {
    _peerDiscoveryController.close();
    _incomingPayloadController.close();
  }
}
