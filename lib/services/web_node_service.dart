import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'cid_service.dart';

final webNodeServiceProvider = Provider((ref) => WebNodeService(ref));

enum WebNodeState { uninitialized, connected, disconnected }

class IndexedDbBlockStore {
  /// Insertion-ordered map doubles as the LRU list: an accessed entry is
  /// reinserted at the end, and eviction always removes the FIRST (least
  /// recently used) key.
  final Map<String, Uint8List> _blocks = {};
  final int maxCapacityBytes;
  int _currentUsageBytes = 0;

  IndexedDbBlockStore({this.maxCapacityBytes = 256 * 1024 * 1024}); // 256 MB

  int get currentUsage => _currentUsageBytes;

  /// Stores [data] under [cid], evicting least-recently-used blocks as
  /// needed. A block LARGER than [maxCapacityBytes] is REFUSED outright
  /// (round-2 red finding): the previous loop evicted everything and
  /// then stored it anyway, leaving currentUsage > capacity — a remote
  /// quota-exhaustion primitive that also wiped the whole store.
  Future<bool> putBlock(String cid, Uint8List data) async {
    if (_blocks.containsKey(cid)) {
      _touch(cid);
      return true;
    }
    if (data.length > maxCapacityBytes) {
      return false; // Oversized: refuse before evicting anything.
    }
    while (_currentUsageBytes + data.length > maxCapacityBytes &&
        _blocks.isNotEmpty) {
      final oldestCid = _blocks.keys.first;
      _currentUsageBytes -= _blocks[oldestCid]!.length;
      _blocks.remove(oldestCid);
    }
    _blocks[cid] = data;
    _currentUsageBytes += data.length;
    return true;
  }

  void _touch(String cid) {
    final data = _blocks.remove(cid);
    if (data != null) _blocks[cid] = data;
  }

  Future<Uint8List?> getBlock(String cid) async {
    final data = _blocks[cid];
    if (data != null) _touch(cid); // LRU: a hit makes the block newest.
    return data;
  }

  Future<bool> hasBlock(String cid) async => _blocks.containsKey(cid);
  Future<void> clear() async {
    _blocks.clear();
    _currentUsageBytes = 0;
  }
}

class WebNodeService {
  final Ref _ref;
  final IndexedDbBlockStore blockStore;
  final Set<String> _connectedWebRtcPeers = {};
  WebNodeState _state = WebNodeState.uninitialized;

  WebNodeService(this._ref, {IndexedDbBlockStore? blockStore})
      : blockStore = blockStore ?? IndexedDbBlockStore();

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

  /// Stores [data] and returns its computed CID. Throws [StateError]
  /// when the store refuses the block (slot-C sweep fix: the previous
  /// code returned a CID even when `putBlock` had refused an oversized
  /// block — a "successfully preserved" handle that always retrieved
  /// null).
  Future<String> preserveInBrowser(Uint8List data) async {
    final cidService = _ref.read(cidServiceProvider);
    final cid = cidService.computeCid(data).toBase32();
    final stored = await blockStore.putBlock(cid, data);
    if (!stored) {
      throw StateError(
          'Block refused by store (exceeds ${blockStore.maxCapacityBytes} '
          'bytes): $cid');
    }
    return cid;
  }

  /// Retrieves a block by CID. (slot-C sweep fix) Content-addressing
  /// integrity: the store is caller-keyed, so a poisoned or mistaken
  /// `putBlock` could alias a CID to foreign bytes. The returned bytes
  /// are re-hashed and the CID re-derived — a mismatch is refused
  /// (fail closed) rather than silently serving mislabeled content.
  Future<Uint8List?> retrieveFromBrowser(String cid) async {
    final data = await blockStore.getBlock(cid);
    if (data == null) return null;
    final cidService = _ref.read(cidServiceProvider);
    final computed = cidService.computeCid(data).toBase32();
    if (computed != cid.toLowerCase()) {
      return null;
    }
    return data;
  }
}
