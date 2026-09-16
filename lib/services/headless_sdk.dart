import 'dart:convert';
import 'dart:math';
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

  /// Per-run RPC bearer token (round-3 red finding): the dispatcher
  /// previously had no authentication at all — anything able to reach
  /// rpcPort could pin/unpin/import. The token is minted on
  /// [startDaemon] and destroyed on [stopDaemon]; calls must present it
  /// via a top-level `authToken` field or `params.authToken`.
  String? _rpcAuthToken;

  /// Per-call cap on an `alexandria.import` payload (round-3 red
  /// finding): base64-decoding unbounded attacker input into memory —
  /// then storing AND pinning it — was a one-line memory-exhaustion
  /// primitive. 4 MiB comfortably covers document-scale imports.
  static const int maxImportBytes = 4 * 1024 * 1024;

  /// Base64 inflates ~4/3; reject overlong encodings before decoding so
  /// the decoded buffer can never exceed [maxImportBytes].
  static const int maxImportBase64Length = ((maxImportBytes + 2) ~/ 3) * 4 + 8;

  HeadlessSdk(this._ref, {this.config = const DaemonConfig()});

  bool get isRunning => _isRunning;

  /// The current RPC bearer token, or null while stopped. Callers on
  /// this node read it once the daemon is up and present it on every
  /// mutating RPC.
  String? get rpcAuthToken => _isRunning ? _rpcAuthToken : null;

  Future<void> startDaemon() async {
    _isRunning = true;
    _rpcAuthToken = _mintToken();
    final ipfs = _ref.read(ipfsServiceProvider);
    await ipfs.startNode();
  }

  Future<void> stopDaemon() async {
    _isRunning = false;
    _rpcAuthToken = null;
    final ipfs = _ref.read(ipfsServiceProvider);
    await ipfs.stopNode();
  }

  static String _mintToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Constant-time bearer-token comparison: XOR-folds every byte pair
  /// without early exit, and folds the length difference into the same
  /// accumulator so a wrong-length token does not reveal itself via a
  /// short-circuit either. (The residual timing signal of different
  /// UTF-8 lengths is unavoidable for string input; the token itself
  /// is fixed-length hex.)
  static bool _constantTimeTokenEquals(String presented, String expected) {
    final a = utf8.encode(presented);
    final b = utf8.encode(expected);
    var diff = a.length ^ b.length;
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  Future<Map<String, dynamic>> executeRpc(String jsonString) async {
    _totalQueriesServed++;
    try {
      final request = jsonDecode(jsonString) as Map<String, dynamic>;
      final method = request['method'] as String?;
      final params = request['params'] as Map<String, dynamic>? ?? {};
      final id = request['id'];

      // (round-3 red finding) Liveness gate: a stopped daemon answers
      // ONLY the non-mutating status probe — every other method is an
      // error, so the RPC surface is never live while the node is "off".
      if (method != 'alexandria.status' && !_isRunning) {
        return {
          'jsonrpc': '2.0',
          'error': {
            'code': -32603,
            'message': 'daemon is not running',
          },
          'id': id,
        };
      }

      // (round-3 red finding) Authentication gate: everything except
      // status requires the per-run bearer token minted by startDaemon.
      // (this round) The comparison is CONSTANT-TIME — Dart `==` on
      // strings short-circuits at the first differing byte, which on a
      // remote-reachable dispatcher would leak the token prefix through
      // response latency. The XOR-fold over UTF-8 never early-exits on
      // content, and the length difference is folded into the
      // accumulator rather than returned first.
      if (method != 'alexandria.status') {
        final presented = request['authToken'] ?? params['authToken'];
        final expected = _rpcAuthToken;
        if (expected == null ||
            presented is! String ||
            !_constantTimeTokenEquals(presented, expected)) {
          return {
            'jsonrpc': '2.0',
            'error': {
              'code': -32603,
              'message': 'unauthorized: valid authToken required',
            },
            'id': id,
          };
        }
      }

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
        // (round-3 red finding) bound the payload BEFORE decode — the
        // encoded size alone must already respect the import cap, and
        // the decoded buffer is checked again before it is stored and
        // auto-pinned (pinned blocks evade GC forever).
        if (dataBase64.length > maxImportBase64Length) {
          throw ArgumentError(
              'Import payload exceeds the ${maxImportBytes ~/ (1024 * 1024)} MiB cap');
        }
        final bytes = base64Decode(dataBase64);
        if (bytes.length > maxImportBytes) {
          throw ArgumentError(
              'Import payload exceeds the ${maxImportBytes ~/ (1024 * 1024)} MiB cap');
        }
        // Enforce the daemon's configured storage budget — auto-pinned
        // imports must not grow the node past maxStorageMb.
        final budgetBytes = config.maxStorageMb * 1024 * 1024;
        if (ipfs.storedBytes + bytes.length > budgetBytes) {
          throw StateError('Import would exceed the daemon storage budget '
              '(${config.maxStorageMb} MB)');
        }
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
