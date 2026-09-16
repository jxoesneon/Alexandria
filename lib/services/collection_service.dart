import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../services/identity_service.dart';

/// Provider for the CollectionService
final collectionServiceProvider = Provider((ref) {
  final identityService = ref.watch(identityServiceProvider);
  return CollectionService(identityService);
});

/// Hybrid Logical Clock for CRDT timestamps
class HybridLogicalClock implements Comparable<HybridLogicalClock> {
  final int wallTime;
  final int logical;
  final Uint8List nodeId;

  HybridLogicalClock({
    required this.wallTime,
    required this.logical,
    required this.nodeId,
  });

  factory HybridLogicalClock.now(Uint8List nodeId) {
    return HybridLogicalClock(
      wallTime: DateTime.now().millisecondsSinceEpoch,
      logical: 0,
      nodeId: nodeId,
    );
  }

  HybridLogicalClock increment() {
    return HybridLogicalClock(
      wallTime: wallTime,
      logical: logical + 1,
      nodeId: nodeId,
    );
  }

  HybridLogicalClock merge(HybridLogicalClock other) {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now > wallTime && now > other.wallTime) {
      return HybridLogicalClock(wallTime: now, logical: 0, nodeId: nodeId);
    } else if (wallTime > other.wallTime) {
      return HybridLogicalClock(
        wallTime: wallTime,
        logical: logical + 1,
        nodeId: nodeId,
      );
    } else if (other.wallTime > wallTime) {
      return HybridLogicalClock(
        wallTime: other.wallTime,
        logical: other.logical + 1,
        nodeId: nodeId,
      );
    } else {
      // Equal timestamps - use higher logical
      final maxLogical = logical > other.logical ? logical : other.logical;
      return HybridLogicalClock(
        wallTime: wallTime,
        logical: maxLogical + 1,
        nodeId: nodeId,
      );
    }
  }

  @override
  int compareTo(HybridLogicalClock other) {
    if (wallTime != other.wallTime) return wallTime.compareTo(other.wallTime);
    if (logical != other.logical) return logical.compareTo(other.logical);
    // Break ties with node ID
    for (var i = 0; i < nodeId.length && i < other.nodeId.length; i++) {
      if (nodeId[i] != other.nodeId[i]) {
        return nodeId[i].compareTo(other.nodeId[i]);
      }
    }
    return nodeId.length.compareTo(other.nodeId.length);
  }

  Map<String, dynamic> toJson() => {
        'wallTime': wallTime,
        'logical': logical,
        'nodeId': base64Encode(nodeId),
      };

  /// Total deserialization of a wire HLC (round-2 red finding): every
  /// field is type-checked before use so a hostile sync message fails
  /// with [FormatException] — never an uncaught _TypeError inside the
  /// merge path. Throws [FormatException] on malformed input.
  factory HybridLogicalClock.fromJson(Map<String, dynamic> json) {
    final wallTime = json['wallTime'];
    final logical = json['logical'];
    final nodeIdRaw = json['nodeId'];
    if (wallTime is! int || logical is! int || nodeIdRaw is! String) {
      throw const FormatException(
          'Malformed HybridLogicalClock: wallTime/logical must be int, '
          'nodeId must be a base64 string');
    }
    final Uint8List nodeId;
    try {
      nodeId = base64Decode(nodeIdRaw);
    } on FormatException {
      throw const FormatException(
          'Malformed HybridLogicalClock: nodeId is not valid base64');
    }
    if (nodeId.isEmpty) {
      throw const FormatException('Malformed HybridLogicalClock: empty nodeId');
    }
    return HybridLogicalClock(
      wallTime: wallTime,
      logical: logical,
      nodeId: nodeId,
    );
  }
}

/// Last-Writer-Wins Register CRDT (Spec §17.1)
class LWWRegister<T> {
  T value;
  HybridLogicalClock timestamp;
  Uint8List author;

  LWWRegister({
    required this.value,
    required this.timestamp,
    required this.author,
  });

  /// Merge two registers - higher timestamp wins
  LWWRegister<T> merge(LWWRegister<T> other) {
    if (timestamp.compareTo(other.timestamp) >= 0) {
      return this;
    }
    return other;
  }

  /// Update the value with a new timestamp
  LWWRegister<T> set(
    T newValue,
    HybridLogicalClock newTimestamp,
    Uint8List newAuthor,
  ) {
    if (newTimestamp.compareTo(timestamp) > 0) {
      return LWWRegister(
        value: newValue,
        timestamp: newTimestamp,
        author: newAuthor,
      );
    }
    return this;
  }

  Map<String, dynamic> toJson(Object? Function(T) valueEncoder) => {
        'value': valueEncoder(value),
        'timestamp': timestamp.toJson(),
        'author': base64Encode(author),
      };
}

/// Observed-Remove Set CRDT (Spec §17.1)
class ORSet<T> {
  final Map<String, T> _elements = {}; // uniqueId -> element
  final Set<String> _removed = {};

  Set<T> get elements => _elements.values.toSet();

  void add(T element, String uniqueId) {
    if (!_removed.contains(uniqueId)) {
      _elements[uniqueId] = element;
    }
  }

  void remove(String uniqueId) {
    _elements.remove(uniqueId);
    _removed.add(uniqueId);
  }

  void merge(ORSet<T> other) {
    // Add all elements not removed in either set
    for (final entry in other._elements.entries) {
      if (!_removed.contains(entry.key) &&
          !other._removed.contains(entry.key)) {
        _elements[entry.key] = entry.value;
      }
    }
    // Merge removed sets
    _removed.addAll(other._removed);
    // Remove any that are in removed
    _elements.removeWhere((k, _) => _removed.contains(k));
  }

  Map<String, dynamic> toJson(Object? Function(T) valueEncoder) => {
        'elements': _elements.map((k, v) => MapEntry(k, valueEncoder(v))),
        'removed': _removed.toList(),
      };
}

/// Grow-only Counter CRDT (Spec §17.1)
class GCounter {
  final Map<String, int> _counts = {}; // nodeId -> count

  int get value => _counts.values.fold(0, (sum, v) => sum + v);

  void increment(String nodeId) {
    _counts[nodeId] = (_counts[nodeId] ?? 0) + 1;
  }

  void merge(GCounter other) {
    for (final entry in other._counts.entries) {
      final current = _counts[entry.key] ?? 0;
      if (entry.value > current) {
        _counts[entry.key] = entry.value;
      }
    }
  }

  Map<String, int> toJson() => Map.from(_counts);
}

/// Collection role for access control (Spec §6.2)
enum CollectionRole {
  viewer, // Read-only
  curator, // Can add content
  editor, // Can modify metadata
  owner, // Can merge/reject, manage roles
}

/// Item in a collection
class CollectionItem {
  final String contentCid;
  final Uint8List addedBy;
  final DateTime addedAt;
  final String note;

  CollectionItem({
    required this.contentCid,
    required this.addedBy,
    required this.addedAt,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'contentCid': contentCid,
        'addedBy': base64Encode(addedBy),
        'addedAt': addedAt.toIso8601String(),
        'note': note,
      };

  factory CollectionItem.fromJson(Map<String, dynamic> json) {
    return CollectionItem(
      contentCid: json['contentCid'] as String,
      addedBy: base64Decode(json['addedBy'] as String),
      addedAt: DateTime.parse(json['addedAt'] as String),
      note: json['note'] as String? ?? '',
    );
  }
}

/// A collaborative collection with CRDT fields (Spec §17.2)
class Collection {
  final String id;
  final String rootCid;
  final String? parentId; // Fork source

  LWWRegister<String> name;
  LWWRegister<String> description;
  ORSet<String> tags;
  ORSet<CollectionItem> items;

  final Map<String, CollectionRole> accessControl; // pubKeyBase64 -> role

  final DateTime created;
  HybridLogicalClock lastModified;

  Uint8List? signature;
  final Uint8List ownerKey;

  Collection({
    required this.id,
    required this.rootCid,
    this.parentId,
    required this.name,
    required this.description,
    required this.tags,
    required this.items,
    required this.accessControl,
    required this.created,
    required this.lastModified,
    this.signature,
    required this.ownerKey,
  });

  /// Check if a user has a specific role or higher
  bool hasRole(Uint8List publicKey, CollectionRole minRole) {
    final keyStr = base64Encode(publicKey);
    final role = accessControl[keyStr];
    if (role == null) return false;
    return role.index >= minRole.index;
  }

  /// Merge with another collection
  Collection merge(Collection other) {
    name = name.merge(other.name);
    description = description.merge(other.description);
    tags.merge(other.tags);
    items.merge(other.items);
    lastModified = lastModified.merge(other.lastModified);
    return this;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'rootCid': rootCid,
        'parentId': parentId,
        'name': name.toJson((v) => v),
        'description': description.toJson((v) => v),
        'tags': tags.toJson((v) => v),
        'items': items.toJson((v) => v.toJson()),
        'accessControl': accessControl.map((k, v) => MapEntry(k, v.name)),
        'created': created.toIso8601String(),
        'lastModified': lastModified.toJson(),
        'ownerKey': base64Encode(ownerKey),
      };
}

/// Merge request for collections (Spec §6.3)
class MergeRequest {
  final String id;
  final String sourceId;
  final String targetId;
  final Map<String, dynamic> diff;
  final Uint8List signature;
  final DateTime timestamp;
  String status; // pending, approved, rejected

  MergeRequest({
    required this.id,
    required this.sourceId,
    required this.targetId,
    required this.diff,
    required this.signature,
    required this.timestamp,
    this.status = 'pending',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceId': sourceId,
        'targetId': targetId,
        'diff': diff,
        'signature': base64Encode(signature),
        'timestamp': timestamp.toIso8601String(),
        'status': status,
      };
}

/// Service for managing collaborative collections
class CollectionService {
  final IdentityService _identityService;
  final Map<String, Collection> _collections = {};
  final List<MergeRequest> _mergeRequests = [];
  final _uuid = const Uuid();

  CollectionService(this._identityService);

  /// Get all collections
  List<Collection> get collections => _collections.values.toList();

  /// Get a collection by ID
  Collection? getCollection(String id) => _collections[id];

  /// Create a new collection
  Future<Collection> createCollection({
    required String name,
    String description = '',
  }) async {
    final identity = await _identityService.getIdentity();
    if (identity == null) throw StateError('No identity found');

    final id = _uuid.v4();
    final rootCid = 'collection:$id'; // Pseudo-CID for collections
    final clock = HybridLogicalClock.now(identity.publicKey);

    final collection = Collection(
      id: id,
      rootCid: rootCid,
      name: LWWRegister(
        value: name,
        timestamp: clock,
        author: identity.publicKey,
      ),
      description: LWWRegister(
        value: description,
        timestamp: clock,
        author: identity.publicKey,
      ),
      tags: ORSet(),
      items: ORSet(),
      accessControl: {base64Encode(identity.publicKey): CollectionRole.owner},
      created: DateTime.now(),
      lastModified: clock,
      ownerKey: identity.publicKey,
    );

    _collections[id] = collection;
    return collection;
  }

  /// Fork a collection (Spec §6.3)
  Future<Collection> forkCollection(String sourceId) async {
    final source = _collections[sourceId];
    if (source == null) throw StateError('Collection not found');

    final identity = await _identityService.getIdentity();
    if (identity == null) throw StateError('No identity found');

    final id = _uuid.v4();
    final rootCid = 'collection:$id';
    final clock = HybridLogicalClock.now(identity.publicKey);

    // Deep copy the collection
    final forked = Collection(
      id: id,
      rootCid: rootCid,
      parentId: sourceId,
      name: LWWRegister(
        value: source.name.value,
        timestamp: clock,
        author: identity.publicKey,
      ),
      description: LWWRegister(
        value: source.description.value,
        timestamp: clock,
        author: identity.publicKey,
      ),
      tags: ORSet(),
      items: ORSet(),
      accessControl: {base64Encode(identity.publicKey): CollectionRole.owner},
      created: DateTime.now(),
      lastModified: clock,
      ownerKey: identity.publicKey,
    );

    // Copy tags and items
    for (final tag in source.tags.elements) {
      forked.tags.add(tag, _uuid.v4());
    }
    for (final item in source.items.elements) {
      forked.items.add(item, _uuid.v4());
    }

    _collections[id] = forked;
    return forked;
  }

  /// Add an item to a collection
  Future<bool> addItem({
    required String collectionId,
    required String contentCid,
    String note = '',
  }) async {
    final collection = _collections[collectionId];
    if (collection == null) return false;

    final identity = await _identityService.getIdentity();
    if (identity == null) return false;

    if (!collection.hasRole(identity.publicKey, CollectionRole.curator)) {
      return false;
    }

    final item = CollectionItem(
      contentCid: contentCid,
      addedBy: identity.publicKey,
      addedAt: DateTime.now(),
      note: note,
    );

    collection.items.add(item, _uuid.v4());
    collection.lastModified = HybridLogicalClock.now(identity.publicKey);
    return true;
  }

  /// Create a merge request
  Future<MergeRequest?> createMergeRequest({
    required String sourceId,
    required String targetId,
  }) async {
    final source = _collections[sourceId];
    final target = _collections[targetId];
    if (source == null || target == null) return null;

    final identity = await _identityService.getIdentity();
    if (identity == null) return null;

    // Compute diff (simplified)
    final diff = <String, dynamic>{
      'name': source.name.value != target.name.value ? source.name.value : null,
      'description': source.description.value != target.description.value
          ? source.description.value
          : null,
      'addedItems': source.items.elements
          .where(
            (i) =>
                !target.items.elements.any((t) => t.contentCid == i.contentCid),
          )
          .map((i) => i.toJson())
          .toList(),
    };

    final data = jsonEncode(diff);
    final signature = await _identityService.sign(
      Uint8List.fromList(utf8.encode(data)),
    );

    final request = MergeRequest(
      id: _uuid.v4(),
      sourceId: sourceId,
      targetId: targetId,
      diff: diff,
      signature: signature,
      timestamp: DateTime.now(),
    );

    _mergeRequests.add(request);
    return request;
  }

  /// Grant role to a user
  Future<bool> grantRole({
    required String collectionId,
    required Uint8List userKey,
    required CollectionRole role,
  }) async {
    final collection = _collections[collectionId];
    if (collection == null) return false;

    final identity = await _identityService.getIdentity();
    if (identity == null) return false;

    if (!collection.hasRole(identity.publicKey, CollectionRole.owner)) {
      return false;
    }

    collection.accessControl[base64Encode(userKey)] = role;
    return true;
  }

  /// Maximum wall-clock distance into the future a remote HLC timestamp
  /// may claim before the write is dropped (round-2 red finding): a
  /// forged far-future wallTime otherwise captures the LWW register and
  /// locks out every legitimate edit until that wall time arrives.
  /// Five minutes tolerates ordinary clock skew between honest peers.
  static const Duration maxRemoteClockSkew = Duration(minutes: 5);

  /// Merge remote state from a sync message (Spec §17)
  ///
  /// This method handles incoming CRDT state from peers and merges
  /// it with the local collection using LWW and OR-Set semantics.
  ///
  /// Authentication floor (round-2 red finding): each remote LWW register
  /// is admitted only when
  ///   * its claimed `author` holds [CollectionRole.editor] or higher in
  ///     the collection's accessControl (a peer with no role cannot write
  ///     metadata), and
  ///   * its HLC wallTime is not more than [maxRemoteClockSkew] ahead of
  ///     the local clock (a forged future clock cannot lock the
  ///     register), and
  ///   * the register parses cleanly — malformed fields are dropped
  ///     individually, never thrown out of the merge.
  ///
  /// RESIDUAL (documented honestly): sync ops carry no Ed25519 signature
  /// over the register payload, so a peer CAN claim authorship of another
  /// member's key — but only keys already holding a write role pass the
  /// gate. Wire-level op signing remains future work.
  Future<void> mergeRemoteState(
    String collectionId,
    Map<String, dynamic> remoteState,
  ) async {
    final local = _collections[collectionId];

    if (local == null) {
      // Create new collection from remote state
      // For now, just log - full deserialization would require more work
      debugPrint(
        'Would create new collection from remote state: $collectionId',
      );
      return;
    }

    // Merge name (LWW)
    final remoteName = _parseRemoteRegister(remoteState['name'], local);
    if (remoteName != null &&
        remoteName.timestamp.compareTo(local.name.timestamp) > 0) {
      local.name = remoteName;
    }

    // Merge description (LWW)
    final remoteDesc = _parseRemoteRegister(remoteState['description'], local);
    if (remoteDesc != null &&
        remoteDesc.timestamp.compareTo(local.description.timestamp) > 0) {
      local.description = remoteDesc;
    }

    // Update last modified
    final identity = await _identityService.getIdentity();
    if (identity != null) {
      local.lastModified = local.lastModified.increment();
    }

    debugPrint('Merged remote state for collection: $collectionId');
  }

  /// Parses and authorizes one remote LWW register (`{value, timestamp,
  /// author}`) against [local]'s accessControl and the clock-skew bound.
  /// Returns null for any malformed or unauthorized register — callers
  /// merge nothing in that case.
  LWWRegister<String>? _parseRemoteRegister(
    Object? raw,
    Collection local,
  ) {
    if (raw is! Map) return null;
    try {
      final map = Map<String, dynamic>.from(raw);
      final value = map['value'];
      final authorRaw = map['author'];
      final timestampRaw = map['timestamp'];
      if (value is! String || authorRaw is! String || timestampRaw is! Map) {
        return null;
      }
      final Uint8List author = base64Decode(authorRaw);
      final timestamp = HybridLogicalClock.fromJson(
        Map<String, dynamic>.from(timestampRaw),
      );

      // Authorization gate: the claimed author must hold a write role on
      // THIS collection. Without it, any sync-topic peer could rewrite
      // collections it has no role in (round-2 red finding).
      if (!local.hasRole(author, CollectionRole.editor)) {
        return null;
      }

      // Clock bound: a remote wallTime beyond now+skew is treated as
      // forged and dropped, so it can never win the LWW comparison.
      final now = DateTime.now().millisecondsSinceEpoch;
      if (timestamp.wallTime > now + maxRemoteClockSkew.inMilliseconds) {
        return null;
      }

      return LWWRegister(
        value: value,
        timestamp: timestamp,
        author: author,
      );
    } catch (_) {
      // Fail-safe: ANY malformed wire value (bad base64, wrong map
      // types, absurd HLC fields) merges nothing — never crashes.
      return null;
    }
  }
}
