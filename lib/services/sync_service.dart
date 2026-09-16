import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ipfs_service.dart';
import 'secure_storage_service.dart';

final syncServiceProvider = Provider((ref) => SyncService(ref));
final syncStatusProvider = StateProvider<SyncStatus>((ref) => SyncStatus.idle);

enum SyncStatus { idle, syncing, offline, error }

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

  factory QueuedOperation.fromJson(Map<String, dynamic> json) =>
      QueuedOperation(
        id: json['id'] as String,
        collectionId: json['collectionId'] as String,
        operation: json['operation'] as String,
        data: json['data'] as Map<String, dynamic>,
        timestamp: DateTime.parse(json['timestamp'] as String),
        retries: json['retries'] as int? ?? 0,
      );
}

class SyncService {
  final Ref _ref;
  final List<QueuedOperation> _offlineQueue = [];
  Timer? _syncTimer;

  /// (slot-C sweep) Allowed shape for fields that land in the pubsub
  /// topic `/alexandria/sync/v1/<collectionId>`: an identifier with `/`
  /// or whitespace in it escapes the topic namespace, so collection and
  /// operation names are restricted to a safe grammar. Applies to new
  /// operations AND to entries rehydrated from storage (a corrupted
  /// queue file is skipped rather than published).
  static final RegExp _fieldPattern =
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');

  static bool _isValidField(String value) => _fieldPattern.hasMatch(value);

  SyncService(this._ref);

  List<QueuedOperation> get offlineQueue => List.unmodifiable(_offlineQueue);

  Future<void> init() async {
    await _loadQueue();
    _startSyncLoop();
  }

  void _startSyncLoop() {
    _syncTimer?.cancel();
    _syncTimer =
        Timer.periodic(const Duration(minutes: 5), (_) => processQueue());
  }

  Future<void> queueOperation({
    required String collectionId,
    required String operation,
    required Map<String, dynamic> data,
  }) async {
    if (!_isValidField(collectionId) || !_isValidField(operation)) {
      throw ArgumentError(
          'Invalid sync operation field (must match ${_fieldPattern.pattern})');
    }
    // A queued op must be persistable AND publishable — both paths go
    // through jsonEncode. Refuse unencodable data at enqueue rather
    // than wedging the queue with an op that can never be drained.
    try {
      jsonEncode(data);
    } catch (_) {
      throw ArgumentError('Sync operation data is not JSON-encodable');
    }
    final op = QueuedOperation(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      collectionId: collectionId,
      operation: operation,
      data: data,
      timestamp: DateTime.now(),
    );
    _offlineQueue.add(op);
    await _saveQueue();
    await processQueue();
  }

  Future<void> processQueue() async {
    if (_offlineQueue.isEmpty) return;
    final ipfs = _ref.read(ipfsServiceProvider);

    final completed = <QueuedOperation>[];
    for (final op in _offlineQueue) {
      // (slot-C sweep) a poison op must not wedge the queue: an
      // unencodable `data` or a throwing transport previously aborted
      // the whole loop, permanently blocking every operation queued
      // behind it. Count the failure like any other — the op ages out
      // at the retry bound instead of poisoning the queue.
      try {
        final topic = '/alexandria/sync/v1/${op.collectionId}';
        final success = await ipfs.publishToPubsub(topic, jsonEncode(op.data));
        if (success) {
          completed.add(op);
        } else {
          op.retries++;
        }
      } catch (_) {
        op.retries++;
      }
    }
    _offlineQueue
        .removeWhere((op) => completed.contains(op) || op.retries >= 5);
    await _saveQueue();
  }

  Future<void> _saveQueue() async {
    final storage = _ref.read(secureStorageServiceProvider);
    final raw = jsonEncode(_offlineQueue.map((e) => e.toJson()).toList());
    await storage.write('sync_queue', raw);
  }

  Future<void> _loadQueue() async {
    final storage = _ref.read(secureStorageServiceProvider);
    final raw = await storage.read('sync_queue');
    if (raw == null) return;
    // (round-5 red finding) a corrupt persisted queue must not crash
    // init() — undecodable JSON starts an empty queue, and individually
    // malformed entries are skipped rather than discarding the good
    // operations around them.
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! List) return;
    _offlineQueue.clear();
    for (final item in decoded) {
      try {
        final op = QueuedOperation.fromJson(item as Map<String, dynamic>);
        // (slot-C sweep) shape-check the fields that land in the pubsub
        // topic — a corrupted/tampered queue file must not let a
        // stored collectionId escape the /alexandria/sync/v1/
        // namespace.
        if (!_isValidField(op.collectionId) || !_isValidField(op.operation)) {
          continue;
        }
        _offlineQueue.add(op);
      } catch (_) {
        // Skip the malformed entry; keep the rest of the queue.
      }
    }
  }

  void dispose() {
    _syncTimer?.cancel();
  }
}
