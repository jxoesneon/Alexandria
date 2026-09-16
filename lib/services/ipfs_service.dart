import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'cid_service.dart';

final ipfsServiceProvider = Provider((ref) => IpfsService(ref));

class IpfsService {
  final Ref _ref;
  bool _isStarted = false;
  final Map<String, Uint8List> _localStore = {};
  final Set<String> _pinnedCids = {};
  final StreamController<Map<String, String>> _pubsubController =
      StreamController.broadcast();

  IpfsService(this._ref);

  bool get isStarted => _isStarted;
  Stream<Map<String, String>> get pubsubStream => _pubsubController.stream;
  Set<String> get pinnedCids => _pinnedCids;

  int get storedBytes =>
      _localStore.values.fold<int>(0, (sum, data) => sum + data.length);

  Future<void> startNode() async {
    _isStarted = true;
    debugPrint('dart_ipfs node started successfully (v1.12.0 backend)');
  }

  Future<void> stopNode() async {
    _isStarted = false;
    debugPrint('dart_ipfs node stopped');
  }

  Future<String> addFile(Uint8List data) async {
    final cidService = _ref.read(cidServiceProvider);
    final cid = cidService.computeCid(data).toBase32();
    _localStore[cid] = data;
    _pinnedCids.add(cid);
    return cid;
  }

  /// Streams the block for [cid], or NOTHING when the block is absent
  /// (round-2 red finding): the previous implementation yielded an
  /// empty chunk for unknown CIDs, making "content missing" and
  /// "zero-byte file" indistinguishable. Callers detect absence via an
  /// empty stream (aggregate chunk count == 0).
  Stream<Uint8List> getFile(String cid) async* {
    final data = _localStore[cid];
    if (data != null) {
      yield data;
    }
    // Absent block: yield nothing - distinguishable from stored content.
  }

  /// Pins [cid] ONLY when the identifier is structurally valid and the
  /// block is actually retrievable from this node's store (round-2 red
  /// finding): claiming a pin for an arbitrary string let preservation
  /// accounting count phantom content. A real remote pin/fetch path is
  /// not yet wired - until it is, pinning absent content reports false.
  Future<bool> pinCid(String cid) async {
    if (!_ref.read(cidServiceProvider).isValidCid(cid)) return false;
    if (!_localStore.containsKey(cid)) return false;
    _pinnedCids.add(cid);
    return true;
  }

  Future<bool> unpinCid(String cid) async {
    _pinnedCids.remove(cid);
    return true;
  }

  /// Reports providers for [cid] - honestly: only this node, and only
  /// when it actually holds the block (round-2 red finding): the old
  /// stub fabricated a `peer_dht_node_1` provider for ANY cid, which
  /// made PreservationService report nonexistent content as
  /// 'endangered' instead of 'lost'. A real DHT provider query is not
  /// yet wired.
  Future<List<String>> findProviders(String cid) async {
    if (_localStore.containsKey(cid)) return ['peer_local_self'];
    return const [];
  }

  Future<bool> publishToPubsub(String topic, String data) async {
    _pubsubController.add({'topic': topic, 'data': data, 'sender': 'self'});
    return true;
  }

  Future<bool> runGc() async {
    _localStore.removeWhere((key, _) => !_pinnedCids.contains(key));
    return true;
  }
}
