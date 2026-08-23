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

  factory QueuedOperation.fromJson(Map<String, dynamic> json) => QueuedOperation(
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

  SyncService(this._ref);

  List<QueuedOperation> get offlineQueue => List.unmodifiable(_offlineQueue);

  Future<void> init() async {
    await _loadQueue();
    _startSyncLoop();
  }

  void _startSyncLoop() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) => processQueue());
  }

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
    await _saveQueue();
    await processQueue();
  }

  Future<void> processQueue() async {
    if (_offlineQueue.isEmpty) return;
    final ipfs = _ref.read(ipfsServiceProvider);

    final completed = <QueuedOperation>[];
    for (final op in _offlineQueue) {
      final topic = '/alexandria/sync/v1/${op.collectionId}';
      final success = await ipfs.publishToPubsub(topic, jsonEncode(op.data));
      if (success) {
        completed.add(op);
      } else {
        op.retries++;
      }
    }
    _offlineQueue.removeWhere((op) => completed.contains(op) || op.retries >= 5);
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
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _offlineQueue.clear();
      for (final item in list) {
        _offlineQueue.add(QueuedOperation.fromJson(item as Map<String, dynamic>));
      }
    }
  }

  void dispose() {
    _syncTimer?.cancel();
  }
}
