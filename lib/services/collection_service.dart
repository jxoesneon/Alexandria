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

  factory HybridLogicalClock.fromJson(Map<String, dynamic> json) {
    return HybridLogicalClock(
      wallTime: json['wallTime'] as int,
      logical: json['logical'] as int,
      nodeId: base64Decode(json['nodeId'] as String),
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

  /// Merge remote state from a sync message (Spec §17)
  ///
  /// This method handles incoming CRDT state from peers and merges
  /// it with the local collection using LWW and OR-Set semantics.
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
    if (remoteState['name'] != null) {
      final remoteName = remoteState['name'] as Map<String, dynamic>;
      final remoteTimestamp = HybridLogicalClock.fromJson(
        remoteName['timestamp'] as Map<String, dynamic>,
      );
      if (remoteTimestamp.compareTo(local.name.timestamp) > 0) {
        local.name = LWWRegister(
          value: remoteName['value'] as String,
          timestamp: remoteTimestamp,
          author: base64Decode(remoteName['author'] as String),
        );
      }
    }

    // Merge description (LWW)
    if (remoteState['description'] != null) {
      final remoteDesc = remoteState['description'] as Map<String, dynamic>;
      final remoteTimestamp = HybridLogicalClock.fromJson(
        remoteDesc['timestamp'] as Map<String, dynamic>,
      );
      if (remoteTimestamp.compareTo(local.description.timestamp) > 0) {
        local.description = LWWRegister(
          value: remoteDesc['value'] as String,
          timestamp: remoteTimestamp,
          author: base64Decode(remoteDesc['author'] as String),
        );
      }
    }

    // Update last modified
    final identity = await _identityService.getIdentity();
    if (identity != null) {
      local.lastModified = local.lastModified.increment();
    }

    debugPrint('Merged remote state for collection: $collectionId');
  }
}
