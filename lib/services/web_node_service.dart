import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'cid_service.dart';

final webNodeServiceProvider = Provider((ref) => WebNodeService(ref));

enum WebNodeState { uninitialized, connected, disconnected }

class IndexedDbBlockStore {
  final Map<String, Uint8List> _blocks = {};
  final int maxCapacityBytes;
  int _currentUsageBytes = 0;

  IndexedDbBlockStore({this.maxCapacityBytes = 256 * 1024 * 1024}); // 256 MB

  int get currentUsage => _currentUsageBytes;

  Future<void> putBlock(String cid, Uint8List data) async {
    if (_blocks.containsKey(cid)) return;
    while (_currentUsageBytes + data.length > maxCapacityBytes &&
        _blocks.isNotEmpty) {
      final oldestCid = _blocks.keys.first;
      _currentUsageBytes -= _blocks[oldestCid]!.length;
      _blocks.remove(oldestCid);
    }
    _blocks[cid] = data;
    _currentUsageBytes += data.length;
  }

  Future<Uint8List?> getBlock(String cid) async => _blocks[cid];
  Future<bool> hasBlock(String cid) async => _blocks.containsKey(cid);
  Future<void> clear() async {
    _blocks.clear;
    _currentUsageBytes = 0;
  }
}

class WebNodeService {
  final Ref _ref;
  final IndexedDbBlockStore blockStore = IndexedDbBlockStore();
  final Set<String> _connectedWebRtcPeers = {};
  WebNodeState _state = WebNodeState.uninitialized;

  WebNodeService(this._ref);

  WebNodeState get state => _state;
  List<String> get connectedPeers => _connectedWebRtcPeers.toList();

  Future<void> initializeWebNode() async {
    _state = WebNodeState.connected;
  }

  Future<void> terminate() async {
    _state = WebNodeState.disconnected;
    _connectedWebRtcPeers.clear();
  }

  void registerPeer(String peerId) {
    _connectedWebRtcPeers.add(peerId);
  }

  void deregisterPeer(String peerId) {
    _connectedWebRtcPeers.remove(peerId);
  }

  Future<String> preserveInBrowser(Uint8List data) async {
    final cidService = _ref.read(cidServiceProvider);
    final cid = cidService.computeCid(data).toBase32();
    await blockStore.putBlock(cid, data);
    return cid;
  }

  Future<Uint8List?> retrieveFromBrowser(String cid) async {
    return await blockStore.getBlock(cid);
  }
}
