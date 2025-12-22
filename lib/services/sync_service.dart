import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'collection_service.dart';
import 'identity_service.dart';
import 'secure_storage_service.dart';
import 'ipfs_service.dart';

/// Provider for the SyncService
final syncServiceProvider = Provider((ref) {
  final collectionService = ref.watch(collectionServiceProvider);
  final identityService = ref.watch(identityServiceProvider);
  final secureStorage = ref.watch(secureStorageServiceProvider);
  final ipfsService = ref.watch(ipfsServiceProvider);
  return SyncService(
    collectionService,
    identityService,
    secureStorage,
    ipfsService,
  );
});

/// Provider for sync status
final syncStatusProvider = StateProvider<SyncStatus>((ref) => SyncStatus.idle);

/// Sync status
enum SyncStatus { idle, syncing, offline, error }

/// Sync message types
enum SyncMessageType {
  push, // Send local changes to peer
  pull, // Request changes from peer
  ack, // Acknowledge received changes
  state, // Full state snapshot
}

/// Sync message for communication between peers
class SyncMessage {
  final SyncMessageType type;
  final String collectionId;
  final String senderId;
  final int timestamp;
  final Map<String, dynamic>? payload;
  final String? signature;

  SyncMessage({
    required this.type,
    required this.collectionId,
    required this.senderId,
    required this.timestamp,
    this.payload,
    this.signature,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'collectionId': collectionId,
    'senderId': senderId,
    'timestamp': timestamp,
    'payload': payload,
    'signature': signature,
  };

  factory SyncMessage.fromJson(Map<String, dynamic> json) {
    return SyncMessage(
      type: SyncMessageType.values.firstWhere((t) => t.name == json['type']),
      collectionId: json['collectionId'] as String,
      senderId: json['senderId'] as String,
      timestamp: json['timestamp'] as int,
      payload: json['payload'] as Map<String, dynamic>?,
      signature: json['signature'] as String?,
    );
  }
}

/// Queued operation for offline sync
class QueuedOperation {
  final String id;
  final String collectionId;
  final String operation;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  int retries;

  QueuedOperation({
    required this.id,
    required this.collectionId,
    required this.operation,
    required this.data,
    required this.timestamp,
    this.retries = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'collectionId': collectionId,
    'operation': operation,
    'data': data,
    'timestamp': timestamp.toIso8601String(),
    'retries': retries,
  };

  factory QueuedOperation.fromJson(Map<String, dynamic> json) {
    return QueuedOperation(
      id: json['id'] as String,
      collectionId: json['collectionId'] as String,
      operation: json['operation'] as String,
      data: json['data'] as Map<String, dynamic>,
      timestamp: DateTime.parse(json['timestamp'] as String),
      retries: json['retries'] as int? ?? 0,
    );
  }
}

/// Sync configuration
class SyncConfig {
  static const Duration pullInterval = Duration(minutes: 5);
  static const Duration retryDelay = Duration(seconds: 30);
  static const int maxRetries = 5;
  static const int maxQueueSize = 1000;
}

/// Service for P2P synchronization using CRDTs (Spec §17)
///
/// This service manages the offline queue and sync protocol for
/// collaborative collections. It uses CRDT merging to resolve
/// conflicts automatically.
class SyncService {
  final CollectionService _collectionService;
  final IdentityService _identityService;
  final SecureStorageService _storage;
  final IpfsService _ipfsService;

  final List<QueuedOperation> _offlineQueue = [];
  final Map<String, int> _lastSyncTimestamp = {};

  Timer? _pullTimer;
  bool _isOnline = true;
  String? _localPeerId;

  SyncService(
    this._collectionService,
    this._identityService,
    this._storage,
    this._ipfsService,
  );

  /// Initialize the sync service
  Future<void> init() async {
    await _loadOfflineQueue();
    await _loadSyncState();
    await _initPeerId();
    _startBackgroundSync();
    debugPrint('SyncService initialized');
  }

  Future<void> _initPeerId() async {
    final identity = await _identityService.getIdentity();
    _localPeerId = identity?.publicKeyBase58;
  }

  /// Start background sync timer
  void _startBackgroundSync() {
    _pullTimer?.cancel();
    _pullTimer = Timer.periodic(SyncConfig.pullInterval, (_) {
      if (_isOnline) {
        _processOfflineQueue();
      }
    });
  }

  /// Queue an operation for sync
  Future<void> queueOperation({
    required String collectionId,
    required String operation,
    required Map<String, dynamic> data,
  }) async {
    final op = QueuedOperation(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      collectionId: collectionId,
      operation: operation,
      data: data,
      timestamp: DateTime.now(),
    );

    _offlineQueue.add(op);

    // Trim queue if too large
    if (_offlineQueue.length > SyncConfig.maxQueueSize) {
      _offlineQueue.removeAt(0);
    }

    await _saveOfflineQueue();

    if (_isOnline) {
      await _processOfflineQueue();
    }
  }

  /// Process the offline queue
  Future<void> _processOfflineQueue() async {
    if (_offlineQueue.isEmpty) return;

    final toRemove = <QueuedOperation>[];

    for (final op in _offlineQueue) {
      try {
        // Send to peer via IPFS PubSub
        // Topic: /alexandria/sync/v1/<collectionId>
        final topic = '/alexandria/sync/v1/${op.collectionId}';
        final success = await _ipfsService.publishToPubsub(
          topic,
          jsonEncode(op.data),
        );

        if (success) {
          debugPrint('Sync op sent: ${op.id} to $topic');
          toRemove.add(op);
        } else {
          throw Exception('PubSub publish failed');
        }
      } catch (e) {
        op.retries++;
        if (op.retries >= SyncConfig.maxRetries) {
          debugPrint('Operation failed after max retries: ${op.id}');
          toRemove.add(op);
        }
      }
    }

    for (final op in toRemove) {
      _offlineQueue.remove(op);
    }

    await _saveOfflineQueue();
  }

  /// Create a sync message for a collection
  Future<SyncMessage> createPushMessage(String collectionId) async {
    final collection = _collectionService.getCollection(collectionId);
    if (collection == null) {
      throw Exception('Collection not found: $collectionId');
    }

    return SyncMessage(
      type: SyncMessageType.push,
      collectionId: collectionId,
      senderId: _localPeerId ?? 'unknown',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: collection.toJson(),
    );
  }

  /// Handle an incoming sync message
  Future<SyncMessage?> handleMessage(SyncMessage message) async {
    debugPrint(
      'Received sync message: ${message.type} for ${message.collectionId}',
    );

    switch (message.type) {
      case SyncMessageType.push:
        // Merge via CollectionService
        if (message.payload != null) {
          await _collectionService.mergeRemoteState(
            message.collectionId,
            message.payload!,
          );
        }
        return _createAck(message);

      case SyncMessageType.pull:
        // Send our current state
        return await createPushMessage(message.collectionId);

      case SyncMessageType.ack:
        // Update sync timestamp
        _lastSyncTimestamp[message.collectionId] = message.timestamp;
        await _saveSyncState();
        return null;

      case SyncMessageType.state:
        // Full state replacement (for new peers)
        if (message.payload != null) {
          await _collectionService.mergeRemoteState(
            message.collectionId,
            message.payload!,
          );
        }
        return _createAck(message);
    }
  }

  SyncMessage _createAck(SyncMessage original) {
    return SyncMessage(
      type: SyncMessageType.ack,
      collectionId: original.collectionId,
      senderId: _localPeerId ?? 'unknown',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Set online status
  void setOnline(bool online) {
    _isOnline = online;
    if (online) {
      _processOfflineQueue();
    }
  }

  /// Get pending operations count
  int get pendingOperations => _offlineQueue.length;

  /// Get last sync time for a collection
  DateTime? getLastSync(String collectionId) {
    final ts = _lastSyncTimestamp[collectionId];
    return ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null;
  }

  /// Load offline queue from storage
  Future<void> _loadOfflineQueue() async {
    final data = await _storage.read('sync_queue');
    if (data != null) {
      try {
        final list = jsonDecode(data) as List;
        _offlineQueue.clear();
        for (final item in list) {
          _offlineQueue.add(
            QueuedOperation.fromJson(item as Map<String, dynamic>),
          );
        }
      } catch (e) {
        debugPrint('Error loading offline queue: $e');
      }
    }
  }

  /// Save offline queue to storage
  Future<void> _saveOfflineQueue() async {
    final data = jsonEncode(_offlineQueue.map((op) => op.toJson()).toList());
    await _storage.write('sync_queue', data);
  }

  /// Load sync state from storage
  Future<void> _loadSyncState() async {
    final data = await _storage.read('sync_state');
    if (data != null) {
      try {
        final map = jsonDecode(data) as Map<String, dynamic>;
        _lastSyncTimestamp.clear();
        map.forEach((key, value) {
          _lastSyncTimestamp[key] = value as int;
        });
      } catch (e) {
        debugPrint('Error loading sync state: $e');
      }
    }
  }

  /// Save sync state to storage
  Future<void> _saveSyncState() async {
    final data = jsonEncode(_lastSyncTimestamp);
    await _storage.write('sync_state', data);
  }

  /// Dispose resources
  void dispose() {
    _pullTimer?.cancel();
  }
}
