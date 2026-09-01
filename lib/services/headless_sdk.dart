import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ipfs_service.dart';

final headlessSdkProvider = Provider((ref) => HeadlessSdk(ref));

class DaemonConfig {
  final int rpcPort;
  final String host;
  final int maxStorageMb;
  final bool enableAutoHealing;
  final String dataDirectory;

  const DaemonConfig({
    this.rpcPort = 9099,
    this.host = '127.0.0.1',
    this.maxStorageMb = 4096, // 4 GB
    this.enableAutoHealing = true,
    this.dataDirectory = '~/.alexandria_daemon',
  });
}

class HeadlessSdk {
  final Ref _ref;
  final DaemonConfig config;
  bool _isRunning = false;
  final DateTime _startTime = DateTime.now();
  int _totalBytesIngested = 0;
  int _totalQueriesServed = 0;

  HeadlessSdk(this._ref, {this.config = const DaemonConfig()});

  bool get isRunning => _isRunning;

  Future<void> startDaemon() async {
    _isRunning = true;
    final ipfs = _ref.read(ipfsServiceProvider);
    await ipfs.startNode();
  }

  Future<void> stopDaemon() async {
    _isRunning = false;
    final ipfs = _ref.read(ipfsServiceProvider);
    await ipfs.stopNode();
  }

  Future<Map<String, dynamic>> executeRpc(String jsonString) async {
    _totalQueriesServed++;
    try {
      final request = jsonDecode(jsonString) as Map<String, dynamic>;
      final method = request['method'] as String?;
      final params = request['params'] as Map<String, dynamic>? ?? {};
      final id = request['id'];

      final result = await _dispatchMethod(method, params);
      return {
        'jsonrpc': '2.0',
        'result': result,
        'id': id,
      };
    } catch (e) {
      return {
        'jsonrpc': '2.0',
        'error': {'code': -32603, 'message': e.toString()},
        'id': null,
      };
    }
  }

  Future<dynamic> _dispatchMethod(
      String? method, Map<String, dynamic> params) async {
    final ipfs = _ref.read(ipfsServiceProvider);

    switch (method) {
      case 'alexandria.status':
        return {
          'status': _isRunning ? 'running' : 'stopped',
          'uptimeSeconds': DateTime.now().difference(_startTime).inSeconds,
          'rpcPort': config.rpcPort,
          'totalBytesIngested': _totalBytesIngested,
          'totalQueriesServed': _totalQueriesServed,
        };

      case 'alexandria.pin':
        final cid = params['cid'] as String?;
        if (cid == null) throw ArgumentError('Missing cid parameter');
        return await ipfs.pinCid(cid);

      case 'alexandria.unpin':
        final cid = params['cid'] as String?;
        if (cid == null) throw ArgumentError('Missing cid parameter');
        return await ipfs.unpinCid(cid);

      case 'alexandria.import':
        final dataBase64 = params['dataBase64'] as String?;
        if (dataBase64 == null) {
          throw ArgumentError('Missing dataBase64 parameter');
        }
        final bytes = base64Decode(dataBase64);
        final cid = await ipfs.addFile(bytes);
        _totalBytesIngested += bytes.length;
        return {'cid': cid, 'sizeBytes': bytes.length};

      case 'alexandria.verify':
        final cid = params['cid'] as String?;
        if (cid == null) throw ArgumentError('Missing cid parameter');
        final providers = await ipfs.findProviders(cid);
        return {
          'cid': cid,
          'providerCount': providers.length,
          'isHealthy': providers.length >= 3
        };

      default:
        throw UnsupportedError('Unknown RPC method: $method');
    }
  }
}
